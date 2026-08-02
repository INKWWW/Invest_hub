# X 当日判断延迟结算宽限期 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本机 X Worker 在上海自然日后的 01:00 前恢复时，仍可用完整的已持久化采集事实生成当日判断，并在 Reader 明确展示超时未生成判断。

**Architecture:** 新增一个以 batch `natural_date` 为唯一输入的 SQL helper，将新 batch 的不可变 `settlement_deadline_at` 设为上海次日 01:00。现有 settlement、证据、judgement run 与 version 状态机不变。Reader 仅从已有 `exclusion_code` 投影一个安全的布尔标记，再据此替换空 partial judgement 与受影响博主的文案。

**Tech Stack:** Supabase PostgreSQL migrations + pgTAP；Next.js/TypeScript/React；Vitest。

## Global Constraints

- 仅新建 batch 使用 01:00 宽限期；不得改写既有 batch、source settlement、run、version、coverage 或 checkpoint。
- 上海次日 00:00 cutoff 归属前一 `natural_date`，因此与同自然日其他窗口共享该自然日后的 01:00 截止。
- 仅有实际 included 来源时才可创建 Provider judgement run；不得对空或不完整输入调用模型。
- 不新增表、任务状态、Worker 协议、Provider、Prompt、服务或依赖；不改变 RLS/RPC grants。
- Reader 不得返回任务 ID、排除代码、Provider、原文、证据 ID、Prompt、文件路径或其他内部字段。
- 保留所有非超时 partial、筛选、排序、版本历史与当前响应式布局。
- 生产发布前必须验证 migration dry-run、远端 migration history、正式部署、Worker loaded 和已认证 `/x` 页面；不手工伪造采集或 Provider 输出。

---

### Task 1: 数据库宽限期与不可变结算回归

**Files:**
- Create: `supabase/migrations/20260802160849_x_daily_judgement_grace_deadline.sql`
- Create: `supabase/tests/031_v2_x_daily_judgement_grace_deadline.sql`

**Interfaces:**
- Consumes: `public.x_collection_batch_logical_date(timestamptz)`, `public.ensure_due_x_collection_batches(uuid,timestamptz)`, `public.settle_x_collection_batch(uuid,timestamptz)`.
- Produces: `public.x_collection_batch_settlement_deadline(date) returns timestamptz`; new batches persist the helper result in the existing `settlement_deadline_at` column.

- [x] **Step 1: Create the migration shell and write the failing pgTAP contract**

Run:

```bash
supabase migration new x_daily_judgement_grace_deadline
```

Create `031_v2_x_daily_judgement_grace_deadline.sql` with synthetic online X Worker, resolved source, initialized coverage, and these assertions before adding the helper:

```sql
select has_function(
  'public', 'x_collection_batch_settlement_deadline', array['date'],
  'the settlement deadline has one natural-date authority'
);
select is(
  (select public.x_collection_batch_settlement_deadline(date '2099-01-02') at time zone 'Asia/Shanghai')::text,
  '2099-01-03 01:00:00',
  'the natural day settles at Shanghai next-day 01:00'
);
```

Include an 20:00 due batch and next-day 00:00 due batch. Assert both have the prior day’s next-day 01:00 deadline, a successful source with a persisted matching day segment becomes `judgement_pending` at 00:59:59 and queues exactly one judgement run, while an unfinished source at 01:00 is excluded with `settlement_deadline_exceeded` and creates no Provider run.

- [x] **Step 2: Run the focused pgTAP file and verify it fails for the absent helper**

Run:

```bash
supabase db reset --yes
supabase test db --local supabase/tests/031_v2_x_daily_judgement_grace_deadline.sql
```

Expected: FAIL because `public.x_collection_batch_settlement_deadline(date)` does not exist. Do not accept a fixture, syntax, or Docker bootstrap failure as the red result.

- [x] **Step 3: Implement the minimal helper and batch-creation substitution**

In the generated migration, define only:

```sql
create function public.x_collection_batch_settlement_deadline(p_natural_date date)
returns timestamptz
language sql
immutable
strict
set search_path = public
as $$
  select ((p_natural_date + 1)::timestamp + time '01:00') at time zone 'Asia/Shanghai'
$$;
```

Use a `before insert` trigger on `public.x_collection_batches` to replace the legacy supplied deadline with `public.x_collection_batch_settlement_deadline(new.natural_date)` only when the scheduler wrapper sets a transaction-local flag. Rename the existing dispatch implementation to a private legacy core and introduce a same-signature `security definer` wrapper that sets that flag before delegating; recreate the existing authorization wrapper so cached function plans resolve that new dispatcher. This preserves manual/history inserts with their explicit immutable deadline while keeping the scheduler’s authorization, frozen source snapshot, task creation, conflict isolation and return shape unchanged. Revoke public/anon/authenticated execution of the helper, trigger function and dispatch core; grant only `service_role` on the helper.

- [x] **Step 4: Run focused DB tests and verify the contract is green**

Run:

```bash
supabase db reset --yes
supabase test db --local supabase/tests/031_v2_x_daily_judgement_grace_deadline.sql
supabase test db --local supabase/tests/027_v2_x_daily_judgement_batch_identity.sql
supabase test db --local supabase/tests/029_v2_x_daily_judgement_final_authority.sql
```

Expected: all focused files pass. Confirm the migration does not mutate pre-existing rows by asserting it has no `update public.x_collection_batches` statement.

- [x] **Step 5: Commit the database change**

```bash
git add supabase/migrations/20260802160849_x_daily_judgement_grace_deadline.sql supabase/tests/031_v2_x_daily_judgement_grace_deadline.sql
git commit -m "fix(v2): add X daily judgement grace deadline"
```

### Task 2: 安全投影与超时 Reader 文案

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx`

**Interfaces:**
- Consumes: `x_collection_batch_sources.exclusion_code` only inside the server-side Reader repository.
- Produces: `timedOutSourceCount: number` on a public-safe judgement batch and `timedOut: boolean` on a public-safe blogger card; neither internal source IDs nor exclusion codes leave the repository.

- [x] **Step 1: Write failing repository and component tests**

Add a repository fixture whose succeeded, empty partial batch has one `settlement_deadline_exceeded` source. Assert its public projection is:

```ts
expect(result[0]?.judgement.batches[0]).toMatchObject({
  coverageStatus: "partial", excludedSourceCount: 1, timedOutSourceCount: 1,
});
expect(result[0]?.bloggers).toEqual(expect.arrayContaining([
  expect.objectContaining({ source: { sourceKey: "alpha" }, timedOut: true }),
]));
expect(JSON.stringify(result)).not.toContain("settlement_deadline_exceeded");
```

Add a component test with an empty partial batch and `timedOutSourceCount: 1`; assert it contains “采集超时，未形成判断” and “其中 1 位因采集未在结算截止前完成。”. Add a non-timeout partial fixture and assert it retains “本窗口没有形成新的跨博主判断。” and does not contain the timeout copy. Add a timed-out blogger fixture and assert it contains “采集超时：本机未在结算时间前完成采集。”.

- [x] **Step 2: Run the focused Node tests and verify they fail for missing fields/copy**

Run:

```bash
cd apps/control-plane
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/x-reader.test.tsx
```

Expected: FAIL because `timedOutSourceCount` and `timedOut` are not projected and the new copy is absent.

- [x] **Step 3: Implement the smallest safe projection and rendering change**

In `readXDay`, include `exclusion_code` only in the private batch-source select. Derive counts/booleans by equality with the literal `settlement_deadline_exceeded`; do not return the code. Extend the reader TypeScript shapes with `timedOutSourceCount` and `timedOut`. In `XReader`, use the timeout copy only when the current succeeded revision has no stock/market viewpoint and `timedOutSourceCount > 0`; use the timed-out blogger copy only when `blogger.timedOut` is true. Keep generic `ReaderStatus` unchanged for every other path.

- [x] **Step 4: Run focused Node tests and verify they pass**

Run:

```bash
cd apps/control-plane
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/x-reader.test.tsx
```

Expected: PASS. Verify serialized repository output does not contain `settlement_deadline_exceeded` or other internal fields.

- [x] **Step 5: Commit the Reader change**

```bash
git add apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/components/reader/x-reader.test.tsx
git commit -m "fix(v2): explain X judgement collection timeout"
```

### Task 3: 全量验证、发布记录与受控生产验收

**Files:**
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`

**Interfaces:**
- Consumes: completed migrations, pgTAP/Node results, Vercel production deployment, linked Supabase history, and the local X Worker service.
- Produces: a redacted production-release record stating the grace deadline, migration result, deployment identifier, Worker status, and Reader acceptance result.

- [x] **Step 1: Run the full deterministic validation suite**

Run serially to avoid pgTAP initialization contention:

```bash
supabase db reset --yes
supabase test db
cd apps/control-plane && npm test && npm run lint
cd ../.. && bash scripts/v0/redact-check.sh && git diff --check
```

Expected: all commands exit zero. Treat the known local Turbopack external-`node_modules` symlink failure as an environment limitation only if it recurs; do not present Webpack as a substitute for the required suite.

- [x] **Step 2: Update redacted project records**

Record that new batch deadlines are Shanghai `natural_date + 1 day 01:00`, prior batches remain immutable, timeout copy is derived from a safe boolean only, and production still has the local-machine / logged-in-X conditional boundary. Do not record real posts, names, prompts, secrets, IDs, or internal exclusion codes.

- [x] **Step 3: Commit release documentation**

```bash
git add docs/project-status.md docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md docs/superpowers/plans/2026-08-03-x-daily-judgement-grace-deadline.md
git commit -m "docs(v2): record X judgement grace deadline"
```

- [x] **Step 4: Publish the reviewed branch and migrate production safely**

Run on the exact reviewed `main` commit after local merge:

```bash
git push origin main
supabase db push --linked --dry-run
supabase db push --linked
supabase migration list --linked
```

Expected: the dry-run lists only `20260803090000_x_daily_judgement_grace_deadline.sql`; after push, local and remote versions match. If any unknown remote history appears, stop; do not use `migration repair`, `db pull`, or Dashboard SQL.

- [x] **Step 5: Deploy, verify Worker, and accept the real Reader**

Deploy the exact `main` commit to the already linked Control Plane Vercel project, then verify its stable `/x` alias. Check `com.investhub.x-worker` is loaded without invoking a fake collection or Provider run. In an authenticated production browser session, verify the normal Reader structure still renders and, using only safe DOM text/structure inspection, confirm the new timeout wording is present if a historical timed-out batch is available; otherwise confirm no internal error or data leak and record that semantic UI copy was covered by deterministic tests rather than fabricating a timeout batch.

- [x] **Step 6: Final verification and handoff**

### Task 4: 判断输入覆盖说明

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx`

**Interfaces:**
- Produces: `includedSourceCount` 与 `noNewSourceCount` 两个 Reader-safe number，和既有 `excludedSourceCount` 一起只描述 batch 的 settlement 覆盖。

- [ ] **Step 1: Write and run the failing Reader component assertion**

Add a successful judgement fixture with `includedSourceCount: 4`、`noNewSourceCount: 2`、`excludedSourceCount: 1`. Assert the rendered HTML contains “输入覆盖：4 位博主观点已纳入，2 位无新增信息，1 位未纳入。” and “下方主题仅列出直接支持或反对该主题的博主。” Then run:

```bash
cd apps/control-plane
npm test -- src/components/reader/x-reader.test.tsx
```

Expected: FAIL because the count fields and copy do not exist.

- [ ] **Step 2: Implement the smallest safe projection and rendering change**

Count `included` and `no_new_information` rows in the existing private `x_collection_batch_sources` result. Add those numbers only to `XReaderDate["judgement"]["batches"]`; render the coverage sentence before the judgement revision only for `succeeded` batches. Do not add source identities, task IDs, exclusion codes, raw content, Provider or Prompt to the Reader DTO.

- [ ] **Step 3: Verify, record and publish**

Run the focused Reader tests, full control-plane test suite, lint, redaction check and `git diff --check`. Commit, push `main`, deploy the Control Plane, and verify the authenticated production `/x` page shows the coverage copy without internal fields.

Re-run `git status --short`, `git log -1 --oneline`, the stable production `/x` HTTP check, and a final authenticated Reader check. Report actual migration/deployment/Worker/Reader evidence and the stable URL. Do not claim cloud or unattended reliability.
