# X v3 验证回放 completion 修复与独立验收 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复真实 v3 replay completion payload 的数据库契约，并以一个独立、一次性的 acceptance run 完成生产 Worker → `/x` 验收，而不重试原 failed replay 或变更定时任务。

**Architecture:** completion RPC 在其入口处将 wire-level `daily` 规范化为纯 output 后再调用既有 validator 与写入版本表。新的 acceptance run 仅引用 failed parent replay 已冻结的 source/post snapshot，拥有独立的 lifecycle、v3 segment/version 输出和 Worker/API 路径；它复用 v3 runtime，不进入任何正常采集或调度路径。

**Tech Stack:** Supabase migration/pgTAP、Next.js/Vitest、Python unittest、既有 Codex CLI Provider、Vercel。

## Global Constraints

- 原 failed replay、原 batch、daily run、v2/v3 历史行、coverage/checkpoint 绝不更新；不得放宽 `x_v3_verification_replays.source_batch_id` 的唯一约束。
- 不调用 OpenCLI/Browser，不创建或变更 launchd、cron、scheduler、X sync task 或正常 `run-scheduled` 行为。
- acceptance run 只允许一个终态 failed parent replay，且每父 replay 至多一条；它失败后不重试。
- completion 必须仍是单一原子事务；任何校验失败都不得留下 analysis、segment、version 或 Reader 投影的部分写入。
- `/x` 保留原“判断失败”，仅在 acceptance 成功时附加“验证恢复（非定时任务）”，不得泄露内部 ID、Prompt、原始正文、路径或 telemetry。

### Task 1: 真实 completion wire contract 回归与数据库修复

**Files:**
- Modify: `supabase/tests/033_x_v3_verification_replay_0800.sql`
- Create: `supabase/migrations/20260804180100_x_v3_replay_completion_wire_contract.sql`

**Interfaces:** `complete_x_v3_verification_replay(uuid, integer, uuid, jsonb)` continues to receive `daily` with `schema_version`, `prompt_version`, three viewpoint arrays and `uncertainties`; `x_v3_verification_versions.output` stores only the latter four output fields.

- [ ] **Step 1: Write the failing pgTAP regression**

  Change `pg_temp.valid_completion()` so `daily` includes:

  ```sql
  'schema_version', 'v3-x-cross-blogger',
  'prompt_version', 'v3-x-cross-blogger-1',
  ```

  Add assertions that completion succeeds and that `output` has no `schema_version` or `prompt_version`, while the row columns equal `v3-x-cross-blogger` and `v3-x-cross-blogger-1`.

- [ ] **Step 2: Verify RED**

  Run: `supabase test db --local supabase/tests/033_x_v3_verification_replay_0800.sql`

  Expected: the existing RPC rejects the valid wire payload with `invalid_v3_x_daily_judgement_output`.

- [ ] **Step 3: Add the smallest migration**

  In a new `create or replace function public.complete_x_v3_verification_replay(...)`, add a `v_daily_output jsonb` local and derive it exactly as:

  ```sql
  v_daily_output := p_payload->'daily' - 'schema_version' - 'prompt_version';
  perform public.validate_x_daily_judgement_output_v3(v_daily_output);
  ```

  Preserve every existing payload, frozen-context, evidence, lease and atomic-write guard. Replace only the version insert output argument with `v_daily_output`; leave its independent schema/prompt columns fixed to v3 values.

- [ ] **Step 4: Verify GREEN and commit**

  Run: `supabase test db --local supabase/tests/033_x_v3_verification_replay_0800.sql`

  Expected: all assertions pass, including no metadata in `output`.

  Commit: `fix: normalize X v3 replay completion payload`

### Task 2: 独立 acceptance-run 数据库 authority

**Files:**
- Create: `supabase/tests/034_x_v3_replay_acceptance_run.sql`
- Create: `supabase/migrations/20260804180200_x_v3_replay_acceptance_run.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`

**Interfaces:** add `create_x_v3_verification_acceptance_run(uuid, uuid)`, `claim_x_v3_verification_acceptance_run(uuid, uuid)`, `get_x_v3_verification_acceptance_context(uuid, integer, uuid)`, `complete_x_v3_verification_acceptance_run(uuid, integer, uuid, jsonb)`, and `fail_x_v3_verification_acceptance_run(uuid, integer, uuid, text)`.

- [ ] **Step 1: Write failing pgTAP lifecycle tests**

  Seed one immutable failed parent replay and its replay-source snapshot. Assert: a non-admin caller is rejected; a succeeded parent is rejected; the admin creates one queued acceptance run; duplicate creation is rejected; claim/context expose only the parent frozen inputs; completion uses the real `daily` wire shape; and the original parent replay/batch retain their original status.

  Add an atomic-failure case with an unknown evidence post and assert zero acceptance segments/versions and zero `analysis_version = 2` rows. Add a successful three-source fixture and assert exactly three acceptance segments, one acceptance version and one terminal `succeeded` row.

- [ ] **Step 2: Verify RED**

  Run: `supabase test db --local supabase/tests/034_x_v3_replay_acceptance_run.sql`

  Expected: failure because acceptance tables/RPCs do not exist.

- [ ] **Step 3: Implement isolated persistence**

  Create append-only `x_v3_verification_acceptance_runs`, `x_v3_verification_acceptance_segments`, and `x_v3_verification_acceptance_versions`. Use `parent_replay_id unique`, a terminal `queued | running | succeeded | failed` lifecycle, service-role-only RLS/RPC access, and the existing immutable-row trigger for segment/version rows.

  The create/context/completion functions must read `x_v3_verification_replay_sources` through `parent_replay_id`, never copy from or modify an original batch. Completion must use the Task 1 `v_daily_output` normalization, preserve the same exact post/source/evidence authority rules, and write only acceptance-owned segments/version plus previously absent `analysis_version = 2` rows in one transaction.

- [ ] **Step 4: Generate types, verify GREEN, and commit**

  Run: `supabase test db --local supabase/tests/034_x_v3_replay_acceptance_run.sql`

  Then regenerate `apps/control-plane/src/lib/db/types.ts` with the repository’s existing Supabase type-generation command and verify the new functions/tables are represented.

  Commit: `feat: add isolated X v3 acceptance run authority`

### Task 3: Control Plane endpoints and Reader projection

**Files:**
- Create: `apps/control-plane/src/lib/db/repositories/x-v3-verification-acceptance-runs.ts`
- Create: `apps/control-plane/src/app/api/admin/x/v3-verification-acceptance-runs/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-v3-verification-acceptance-runs/[acceptanceRunId]/{claim,context,complete,failure}/route.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`

**Interfaces:** the admin endpoint accepts exactly `{ replay_id: string }` and returns `{ acceptance_run_id: string, status: "queued" }`; Worker endpoints use the same strict completion shape as Task 1; Reader exposes the existing `verificationRecovery` view model only for a successful acceptance version associated through the parent replay.

- [ ] **Step 1: Write failing API/Reader tests**

  Add tests that deny non-admin create, reject extra request keys, validate malformed Worker IDs/payloads before repository calls, and expose a recovery only when the batch is still `judgement_failed`, parent replay remains `failed`, and its acceptance run/version is `succeeded`/v3. Assert no raw or opaque fields occur in the Reader view model.

- [ ] **Step 2: Verify RED**

  Run: `cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts src/lib/db/repositories/reader-source-navigation.test.ts`

  Expected: failures because acceptance repository/routes/Reader query do not exist.

- [ ] **Step 3: Implement strict mapping and bounded projection**

  Add a repository with exact response parsers matching Task 2 RPC responses. Add admin and Worker routes mirroring the replay route authentication/422/409 behavior. In `reader.ts`, query only successful acceptance runs and their v3 versions, join them through a parent replay whose status is `failed`, and map the stored pure output through `judgementRevision`; do not query or return internal identifiers.

  Preserve the original replay query only for its existing audit semantics; replace its success-based recovery selection with the acceptance-based selection so old failed replay remains visible while the new card is displayed.

- [ ] **Step 4: Verify GREEN and commit**

  Run: `cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts src/lib/db/repositories/reader-source-navigation.test.ts`

  Commit: `feat: expose X v3 acceptance recovery safely`

### Task 4: Explicit Worker acceptance command and error attribution

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/errors.py`
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`
- Modify: `workers/v0/src/invest_hub_worker/cli.py`
- Modify: `workers/v0/tests/test_protocol.py`
- Modify: `workers/v0/tests/test_cli.py`
- Modify: `workers/v0/tests/test_x_v3_verification_replay.py`

**Interfaces:** add five acceptance-run Protocol methods with the Task 2 request/response shapes; add `run-x-v3-verification-acceptance --acceptance-run-id <uuid>`; retain `XVerificationReplayRuntime` as the frozen-input v3 executor.

- [ ] **Step 1: Write failing Worker tests**

  Add a protocol transport test that sends the exact complete payload to `/api/worker/x-v3-verification-acceptance-runs/<id>/complete` and accepts only `{ status: "succeeded" }`. Add CLI tests that the new command calls only `claim → context → complete`, refuses without `V2_REAL_X_ACK=authorized`, and on a known 422 completion rejection records `schema_error` through only the acceptance failure endpoint. Patch normal `Worker`, `_run_scheduled`, OpenCLI and Browser constructors to throw if touched.

- [ ] **Step 2: Verify RED**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers.v0.tests.test_protocol workers.v0.tests.test_cli workers.v0.tests.test_x_v3_verification_replay -v`

  Expected: missing acceptance Protocol/CLI interfaces.

- [ ] **Step 3: Implement the smallest protocol extension**

  Make `ProtocolError` retain HTTP status for remote failures. In `_request`, populate it for non-409 failures; `_verification_failure_class` maps only HTTP 422 completion validation failures to `schema_error`, retaining `persistence_failure` for transport/5xx/unknown failures.

  Add acceptance Protocol methods by reusing the existing replay context/completion validators and changing only the endpoint path. Add the explicit CLI subcommand with the same X-only config, credential and acknowledgement guards as the original replay command; it may construct only Protocol and the existing v3 replay runtime.

- [ ] **Step 4: Verify GREEN and commit**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers.v0.tests.test_protocol workers.v0.tests.test_cli workers.v0.tests.test_x_v3_verification_replay -v`

  Commit: `feat: run isolated X v3 acceptance verification`

### Task 5: Full verification, production release, and one bounded acceptance run

**Files:**
- Modify: `docs/superpowers/plans/2026-08-04-x-v3-replay-completion-repair.md`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`
- Modify: `docs/project-status.md` only if its stated status changes

- [x] **Step 1: Run the complete local release gate**

  Run:

  ```bash
  supabase test db
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
  cd apps/control-plane && npm test -- --run && npm run lint && npm run build
  git diff --check
  bash scripts/v0/redact-check.sh
  ```

  Expected: all commands exit zero; no secret, raw-content or formatting leak is introduced.

- [x] **Step 2: Release code and migration**

  Push `main`, apply only the two new migrations to the linked production database, deploy the Control Plane to Vercel production, and verify the stable `/x` deployment resolves to the released commit. Do not load or alter any Worker scheduler service.

- [x] **Step 3: Run one production acceptance command**

  Through the authenticated admin endpoint, create exactly one acceptance run for the known failed replay. Execute exactly one `run-x-v3-verification-acceptance` invocation with the existing owner-only X Worker config/credential and `V2_REAL_X_ACK=authorized`. It must not receive an OpenCLI executable argument. If it fails, stop and record the terminal result without retry.

- [x] **Step 4: Read-only production and UI acceptance**

  Query only aggregate/status fields to prove: the parent replay remains `failed`; original batch/run counts and statuses did not change; no new sync/scheduled task was created; acceptance has three frozen sources, v3 analyses, three acceptance segments and one acceptance version. In an authenticated browser, open production `/x` and verify the original failure remains plus the “验证恢复（非定时任务）” card, categories and no internal-field leakage.

- [x] **Step 5: Record and publish evidence**

## Execution record (2026-08-04)

`6e9890b` normalized the v3 completion wire payload; `0287b7c` added the isolated acceptance lifecycle, Worker path and Reader projection; `43d98c3` corrected the acceptance context response to the Worker protocol. The two additive migrations are applied to production. Local gates passed: 39 pgTAP files / 622 assertions, 185 Worker tests, 42 Control Plane files / 238 tests, lint, production build, `git diff --check`, and redaction check.

One acceptance run was created from the already terminal failed replay and executed exactly once. It succeeded with 3 frozen sources, 3 acceptance segments and 1 acceptance version. The parent replay remains failed on attempt 1 with its original `persistence_failure`, the original source batch remains `judgement_failed` with its original daily-run count, and the acceptance window created 0 sync tasks. Authenticated production `/x` retains the original failure and displays `验证恢复（非定时任务）` without internal fields.

  Check completed Plan steps, append the real outcome and bounded counts to the engineering journal, run `git diff --check` and the redaction check again, commit the record, and push `main`.
