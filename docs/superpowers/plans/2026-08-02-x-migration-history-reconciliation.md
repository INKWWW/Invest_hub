# X 生产 Migration 历史对账 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改写生产 history 或业务数据的前提下，使仓库可安全应用已批准的 X judgement migrations。

**Architecture:** 用 `20260731084640` 的无副作用历史标记补齐本地 migration identity；空数据库随后由现有 `20260731100000` 定义最终 scheduler 函数。生产只接受 marker 已匹配、dry-run 明确列出十条后续 migration 的发布路径。

**Tech Stack:** Supabase CLI 2.109.1、PostgreSQL/pgTAP、既有 Vercel control-plane 与 `launchd` X Worker。

## Global Constraints

- 禁止 `supabase migration repair`、`supabase db pull`、Dashboard SQL、重写既有 migration 或对 `20260731084640` 重新执行推测性 DDL。
- 新 marker 只能含注释和 `select 1`；不得创建、删除或修改任何对象、数据、RLS、source、coverage、checkpoint、task 或 judgement record。
- 本地验证只运行 migration/pgTAP/格式与脱敏 gate；不因本次对账重跑 Provider、Collector 或前端 build。
- 生产先推送与部署同一 `main` commit；任一 migration、deployment、Worker 或 Reader gate 失败即停止后续步骤。
- 生产回退只停止新的 judgement claiming 并回退 Reader deployment；不得删除或改写 immutable judgement 或既有 X 采集数据。

---

### Task 1: 补齐历史身份并锁定空库语义

**Files:**
- Create: `supabase/migrations/20260731084640_x_defer_terminal_failed_sources_historical_marker.sql`
- Create: `supabase/tests/030_v2_x_migration_history_reconciliation.sql`

**Interfaces:**
- Consumes: production history 中已存在的 version `20260731084640`，以及 `20260731100000_x_defer_terminal_failed_sources.sql` 的 `public.enqueue_due_x_tasks(uuid, timestamptz)`。
- Produces: 本地与远端均可识别的 migration version；空库中的 final scheduler function 仍包含 `deferred_source_ids`。

- [ ] **Step 1: 写入先失败的 pgTAP 对账测试。**

```sql
begin;
select plan(3);
select ok(exists (
  select 1 from supabase_migrations.schema_migrations where version = '20260731084640'
), 'the historical remote marker is recorded locally');
select ok(exists (
  select 1 from supabase_migrations.schema_migrations where version = '20260731100000'
), 'the canonical scheduler migration follows the marker');
select like(
  pg_get_functiondef('public.enqueue_due_x_tasks(uuid,timestamp with time zone)'::regprocedure),
  '%deferred_source_ids%',
  'the canonical scheduler definition preserves terminal-failure isolation output'
);
select * from finish();
rollback;
```

- [ ] **Step 2: 在 marker 不存在时执行该测试，确认它因缺少 `20260731084640` 而失败。**

Run: `supabase db reset --yes && supabase test db --file supabase/tests/030_v2_x_migration_history_reconciliation.sql`

Expected: the first assertion fails because the local migration history has no `20260731084640` version.

- [ ] **Step 3: 新增最小 marker migration。**

```sql
-- Production recorded this version on 2026-07-31 for terminal X failure
-- isolation. The reviewed canonical definition is applied by 20260731100000.
-- This file reconciles repository history only; it intentionally changes no schema.
select 1;
```

- [ ] **Step 4: 重置本地数据库并运行对账与既有隔离测试。**

Run: `supabase db reset --yes && supabase test db --file supabase/tests/030_v2_x_migration_history_reconciliation.sql && supabase test db --file supabase/tests/023_v2_x_terminal_failure_scheduler.sql && supabase migration list --local`

Expected: two pgTAP files pass; local history lists both `20260731084640` and `20260731100000`.

- [ ] **Step 5: 提交最小实现。**

```bash
git add supabase/migrations/20260731084640_x_defer_terminal_failed_sources_historical_marker.sql supabase/tests/030_v2_x_migration_history_reconciliation.sql
git commit -m "fix(v2): reconcile X migration history"
```

### Task 2: 记录对账事实并完成本地发布门禁

**Files:**
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`

**Interfaces:**
- Consumes: Task 1 的 marker、实际 local pgTAP 结果和此前 dry-run 拒绝证据。
- Produces: 可审计的对账原因、禁止操作、当前发布状态与下一步受控生产序列。

- [ ] **Step 1: 仅记录已发生的本地事实。** 将 project status 和工程日志更新为：远端 version `20260731084640` 已被本地历史 marker 对齐；本地验证通过；remote `db push`、Vercel deploy、Worker restart、真实 X/Codex 读取及 authenticated Reader 验收尚未发生。明确 marker 不重放 DDL，`20260731100000` 才是最终函数定义。

- [ ] **Step 2: 运行最小本地 gate。**

Run: `supabase db reset --yes && supabase test db --file supabase/tests/030_v2_x_migration_history_reconciliation.sql && supabase test db --file supabase/tests/023_v2_x_terminal_failure_scheduler.sql && bash scripts/v0/redact-check.sh && git diff --check`

Expected: all commands exit 0; no secret, raw content or ignored `node_modules` path is staged.

- [ ] **Step 3: 提交文档与本地证据。**

```bash
git add docs/project-status.md docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md
git commit -m "docs(v2): record migration history reconciliation"
```

### Task 3: 受控发布与线上验收

**Files:**
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`

**Interfaces:**
- Consumes: Task 2 完成的 `main` commit、Supabase linked project、Vercel production alias 与本机 `com.investhub.x-worker`。
- Produces: 十条 judgement migrations 的生产 history、Ready deployment、已重启的 X Worker 和受认证 `/x` 验收记录。

- [ ] **Step 1: 以精确 commit 范围推送 main，并在写入前执行远端 dry-run。**

```bash
git push origin main
supabase migration list --linked --output-format json
supabase db push --linked --dry-run
```

Expected: history maps `20260731084640` both locally and remotely; dry-run lists exactly `20260731100000`, `20260801090000`, `20260801100000`, `20260801120000`, `20260801130000`, `20260801140000`, `20260801150000`, `20260801160000`, `20260801170000`, and `20260801180000`, with no missing-local-history error.

- [ ] **Step 2: 仅在 dry-run 完全匹配后应用 migration，并只读核对结果。**

```bash
supabase db push --linked
supabase migration list --linked --output-format json
supabase db query --linked --output-format json "select version from supabase_migrations.schema_migrations where version in ('20260731084640','20260731100000','20260801090000','20260801100000','20260801120000','20260801130000','20260801140000','20260801150000','20260801160000','20260801170000','20260801180000') order by version;"
supabase db query --linked --output-format json "select position('deferred_source_ids' in pg_get_functiondef('public.enqueue_due_x_tasks(uuid,timestamp with time zone)'::regprocedure)) > 0 as preserves_terminal_failure_isolation;"
```

Expected: all eleven versions are returned; `preserves_terminal_failure_isolation` is `true`.

- [ ] **Step 3: 部署同一 main commit，并确认正式别名 Ready。**

```bash
cd apps/control-plane
npx --yes vercel@50.28.0 --prod --yes
npx --yes vercel@50.28.0 inspect https://invest-hub-v0-control-plane.vercel.app
curl --noproxy '*' --silent --show-error --max-time 20 --location --output /dev/null --write-out '%{http_code} %{url_effective}\\n' https://invest-hub-v0-control-plane.vercel.app/x
```

Expected: Vercel target is `production` and status is `Ready`; anonymous `/x` resolves to the login route rather than exposing Reader data.

- [ ] **Step 4: 重启并核对 X Worker，不手动伪造 judgement 输入。**

```bash
launchctl kickstart -k "gui/$(id -u)/com.investhub.x-worker"
bash scripts/v2/verify-launchd-x-worker.sh
```

Expected: launchd reports `com.investhub.x-worker` loaded with its configured X-only executable and configuration. The normal scheduler, not an ad-hoc script, is allowed to claim a future judgement batch.

- [ ] **Step 5: 使用已认证普通用户会话验收 `/x`。** 打开正式 `/x`，确认最新上海日期在首位、判断总结在单博主卡片前、每位博主独立分块、来源/日期筛选仍可用，375px 宽度不横向溢出；仅记录是否通过和可回溯 version，不复制真实帖子、Prompt、模型响应、Cookie 或内部 ID。

- [ ] **Step 6: 将实际生产结果写回工程记录与状态并提交。** 文档必须逐项写明 remote migration、deployment、Worker restart 和 Reader 验收的真实状态与 commit/deployment ID；任何未执行或失败步骤保持未完成，不得以本地测试替代。然后运行 `bash scripts/v0/redact-check.sh && git diff --check` 并提交：

```bash
git add docs/project-status.md docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md
git commit -m "docs(v2): record X judgement production reconciliation"
```

## Plan self-review

Spec 的历史身份、最小范围、禁止 repair/pull、空库语义、远端 dry-run、十条受控 migrations、函数只读核对、部署、Worker 与 Reader 验收均由 Task 1–3 覆盖。计划未引入未定义接口、未留占位步骤，也没有把本地验证写成生产成功。
