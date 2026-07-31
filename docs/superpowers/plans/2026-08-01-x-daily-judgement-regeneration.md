# X 当日判断总结再生成 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不把 Provider 失败伪装为 Reader 版本的前提下，使已成功 X 批次可由管理员显式再生成并追加 immutable revision，同时闭合 Task 5 的真实跨层验收缺口。

**Architecture:** 首次 judgement run 的失败仍只改变该 run 的 retry 状态；首次成功始终写入 revision 1。新增 service-role RPC 只接受已成功且已有版本的 batch，在锁内创建一条 `regeneration` queued run，并记录发起管理员；既有 claim/context/complete Worker 路径处理该 run，因 append-only 规则自动写入 revision 2。管理员 HTTP route 是唯一产品入口，普通用户、Worker 和调度 tick 均不能主动创建 regeneration。

**Tech Stack:** Supabase SQL/pgTAP，Next.js Route Handler/Vitest，Python Worker 协议测试，现有 V2 deterministic E2E runner。

## Global Constraints

- 只新增 migration；不得修改或删除既有 immutable batch/source/segment/version。
- Provider 失败且没有成功版本时，重试成功写 revision 1；不得记录虚假的失败 Reader version。
- regeneration 不得触发 X/OpenCLI/Browser 采集，不得改来源快照、coverage、checkpoint、原始帖子、分析或旧版本。
- API 普通用户不得触发或读取内部 run/actor/telemetry；Reader 只显示既有安全 DTO 的最新 version。
- 测试只使用公开人工 fixture、mock 或本地数据库；不得调用真实 X、Browser、OpenCLI、Codex CLI、远端 migration 或部署。
- 生产验收仅准备；真实 migration、管理员 regeneration、Worker 重启与线上 `/x` 检查仍需逐项授权。

---

### Task 1: Audited regeneration database contract and admin entry point

**Files:**
- Create: `supabase/migrations/20260801140000_x_daily_judgement_regeneration.sql`
- Create: `supabase/tests/026_v2_x_daily_judgement_regeneration.sql`
- Modify: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts`
- Create: `apps/control-plane/src/app/api/admin/x/daily-judgements/[batchId]/regenerate/route.ts`
- Create: `apps/control-plane/src/app/api/admin/x/daily-judgements/[batchId]/regenerate/route.test.ts`

**Interfaces:**
- Consumes: immutable `x_collection_batches`, `x_daily_judgement_runs`, `x_daily_judgement_versions` and existing `claim_next_x_daily_judgement`/`complete_x_daily_judgement` RPCs.
- Produces: `public.regenerate_x_daily_judgement(p_batch_id uuid, p_requested_by uuid) returns jsonb`; repository `regenerateXDailyJudgement(batchId: string, actorId: string)`; admin `POST /api/admin/x/daily-judgements/:batchId/regenerate` with an empty JSON object body.

- [ ] **Step 1: Write failing database and HTTP tests.**

  pgTAP must construct a succeeded batch with revision 1 and assert a service-role regeneration inserts exactly one queued run with `run_kind='regeneration'`, `requested_by` equal to the actor and `attempt=0`; its normal claim/completion creates immutable revision 2 while revision 1 remains byte-for-byte unchanged. Assert rejection for a batch without a successful version, a collecting/pending/failed batch, an active run, null/invalid actor, ordinary `authenticated` execution, and a second concurrent regeneration. Route tests must assert unauthenticated/ordinary `401/403`, invalid batch id or non-empty body `422`, and an admin-only request forwards the authenticated actor id and returns only `{ runId, status, attempt }`.

- [ ] **Step 2: Run only the new tests and observe RED.**

  Run the new pgTAP file after `supabase db reset`, and the new Vitest route/repository tests. Expected failures: RPC/route/repository are absent and no regeneration run exists.

- [ ] **Step 3: Implement the additive state transition.**

  In migration `20260801140000_x_daily_judgement_regeneration.sql`, add `run_kind text not null default 'initial' check (run_kind in ('initial','regeneration'))` and nullable `requested_by uuid`; backfill existing rows as `initial` with null actor. Implement `regenerate_x_daily_judgement` as `security definer`, lock the target batch, require `status='succeeded'` and at least one immutable version, reject an active run using the existing active-status definition, then insert exactly one queued `regeneration` run with the supplied non-null actor. Do not update batch/source/coverage/version rows. Revoke public/anon/authenticated execution and grant only `service_role`. Repository calls only that RPC. The route uses `requireRole('admin')`, accepts only `{}`, validates UUID format, and emits no batch source, version, prompt, provider or actor data.

- [ ] **Step 4: Run focused Green verification.**

  Run `supabase db reset && supabase test db`, the focused repository/route tests, `npm run lint`, and `git diff --check`. Confirm that the normal Worker claim sees the queued regeneration and `complete_x_daily_judgement` appends revision 2 without changing revision 1.

- [ ] **Step 5: Commit.**

  ```bash
  git add supabase/migrations/20260801140000_x_daily_judgement_regeneration.sql supabase/tests/026_v2_x_daily_judgement_regeneration.sql apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts apps/control-plane/src/app/api/admin/x/daily-judgements/[batchId]/regenerate/route.ts apps/control-plane/src/app/api/admin/x/daily-judgements/[batchId]/regenerate/route.test.ts
  git commit -m "feat(v2): add audited X judgement regeneration"
  ```

### Task 2: Complete real cross-layer evidence and close Task 5

**Files:**
- Modify: `apps/control-plane/src/app/api/reader/x/route.test.ts` (create if absent)
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Modify: `workers/v0/tests/test_x_cross_blogger_judgements.py`
- Modify: `tests/e2e/v2/test_x_cross_blogger_daily_judgements.py`
- Modify: `scripts/v2/run-v2-e2e.sh`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`
- Modify: `docs/project-status.md`

**Interfaces:**
- Consumes: Task 1 RPC/route and existing safe `GET /api/reader/x`/`readXDay` projection.
- Produces: deterministic evidence that a real route returns only the Reader-safe DTO and that `revision 1 → admin regeneration → revision 2` retains history and projects revision 2.

- [ ] **Step 1: Write failing real-boundary tests.**

  Replace the standalone Python-only Reader imitation as the proof of `/api/reader/x`. Add route tests that exercise the actual handler with `getCurrentUser` and `readXDay` mocks, assert ordinary user success, anonymous 401, input filter behavior and exclusion of the raw-content sentinel/internal keys from the actual JSON serialization. Extend repository projection fixtures with revision 1 and revision 2 for a single batch and assert only revision 2 is returned while version history remains in the database contract test. Extend Worker tests so a standard claim processes one regeneration run and preserves independent source task/coverage behavior. The Python E2E may retain only a public schedule-state fixture for duplicate ticks and stale lease behavior; it must remove `api_reader_x`/`reader_html` as claims about the production route and remove the blocked skip.

- [ ] **Step 2: Run the changed tests and observe RED.**

  Run the focused Node Reader/admin route tests, Worker regeneration tests, the V2 E2E file and local pgTAP test. Expected failures: no revision 2 path or no real route assertions.

- [ ] **Step 3: Implement only test-supporting changes.**

  Update fixtures and protocol mocks to represent `run_kind='regeneration'` without adding a new Worker command or an automatic scheduling loop. Ensure the existing `claim_next_x_daily_judgement` path remains the only Worker execution path. The V2 runner must execute the actual Node Reader/admin route tests in addition to the Python schedule contract, then preserve existing V1.1 and no-real-OpenCLI gates.

- [ ] **Step 4: Correct governance evidence.**

  Update the engineering journal and project status to say the approved regeneration semantics are locally verified, not production-deployed. The production checklist must list **all** additive migrations in order: `20260801090000_x_cross_blogger_daily_judgements.sql`, `20260801100000_x_daily_judgement_hardening.sql`, `20260801120000_x_daily_judgement_worker_protocol.sql`, `20260801130000_x_daily_judgement_completion_lease_and_metadata.sql`, and `20260801140000_x_daily_judgement_regeneration.sql`. It must state that default `npm run build` remains a worktree symlink environment failure; it may list passing Webpack build only as supplemental evidence, not substitute the plan-required command.

- [ ] **Step 5: Run deterministic verification.**

  Run `supabase db reset && supabase test db`; Worker tests; `V2_PYTHON_BIN=<existing local venv> bash scripts/v2/run-v2-e2e.sh`; control-plane `npm test`, `npm run lint`, default `npm run build`, `npm run build -- --webpack`, `bash scripts/v0/redact-check.sh`, and `git diff --check`. Record exact pass/fail/skipped counts; no blocked revision test may remain.

- [ ] **Step 6: Commit.**

  ```bash
  git add apps/control-plane/src/app/api/reader/x/route.test.ts apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts workers/v0/tests/test_x_cross_blogger_judgements.py tests/e2e/v2/test_x_cross_blogger_daily_judgements.py scripts/v2/run-v2-e2e.sh docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md docs/project-status.md
  git commit -m "test(v2): close X judgement regeneration acceptance"
  ```

## Plan self-review

Spec §3 and criterion 6 are covered by Task 1's distinction between initial retry/revision 1 and explicit regeneration/revision 2. Task 1 also preserves append-only versions, source isolation and least privilege. Task 2 answers all Task 5 review findings: it tests the actual Reader route instead of a Python imitation, lists every migration including hardening, and reports the default build failure as a remaining environment gate rather than passing it through a Webpack substitute. No task performs production actions or adds a collector/provider.
