# X v3 生产验证恢复链 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以 2026-08-04 08:00 已冻结的三个已纳入来源，执行一次独立、不可变的 v3 post → window → daily 验证链，并安全展示在正式 `/x`，且不创建或改变任何定时任务。

**Architecture:** 新增独立的 verification replay persistence/RPC 边界，而不是复用或修改已终态的 scheduled batch。一次性 CLI 命令通过已有 Worker credential 调用新 Worker API，读取冻结 canonical 上下文并在一个 completion 事务中持久化 v3 事实、verification segments 与 verification judgement。Reader 将验证结果作为带明示标签的附加结果投影，原失败卡保持不变。

**Tech Stack:** PostgreSQL/Supabase pgTAP、Next.js TypeScript/Vitest、Python unittest、现有 Codex CLI Provider 边界、Vercel、现有 `com.investhub.x-worker` credential。

## Global Constraints

- 仅允许 source batch 为 2026-08-04 08:00、状态 `judgement_failed`、且冻结来源的 `settlement_status = included`；禁止调用 OpenCLI、浏览器、采集、`run-scheduled`、`ensure_due_x_collection_batches` 或任何 launchd/cron 改动。
- 原 batch、原 daily run、v2 analyses/segments、coverage、checkpoint 与已有 schedule 不得插入、更新、删除、回刷或被标记成功。
- 单帖使用 `v3-x-post-analysis-1` / `v3-x-post-analysis` 和 `analysis_version = 2`；窗口使用 `v3-x-window-1` / `v3-x-window`；每日判断使用 `v3-x-cross-blogger-1` / `v3-x-cross-blogger`。
- replay 不自动重试；仅当前管理员创建一次，显式 `run-x-v3-verification --replay-id` 命令只运行一次。所有错误以安全枚举持久化，失败不得留下 partial v3 segment 或 verification daily version。
- Reader 必须显示“验证恢复（非定时任务）”，并且不得返回/显示 task、replay、analysis、segment、evidence ID、Prompt、原始正文、本机路径或 Provider telemetry。

---

### Task 1: Append-only verification replay database contract

**Files:**
- Create: generated `supabase/migrations/<timestamp>_x_v3_verification_replay.sql`
- Create: `supabase/tests/033_x_v3_verification_replay.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`

**Interfaces:**
- Consumes: a current admin id and source batch id.
- Produces: `create_x_v3_verification_replay(uuid, uuid)`, `claim_x_v3_verification_replay(uuid, uuid)`, `get_x_v3_verification_replay_context(uuid, integer, uuid)`, `complete_x_v3_verification_replay(uuid, integer, uuid, jsonb)`, and `fail_x_v3_verification_replay(uuid, integer, uuid, text)` service-role functions.

- [ ] **Step 1: Generate migration and add RED pgTAP tests.**

Run `supabase migration new x_v3_verification_replay`. In the generated migration define no application behavior yet. Add tests that expect the five RPCs and the three new append-only tables (`x_v3_verification_replays`, `x_v3_verification_replay_sources`, `x_v3_verification_segments`) plus `x_v3_verification_versions` to exist. Include these assertions:

```sql
select throws_ok(
  $$select public.create_x_v3_verification_replay('00000000-0000-0000-0000-000000033020', '00000000-0000-0000-0000-000000033010')$$,
  '42501', 'actor_not_authorized',
  'ordinary users cannot create a verification replay'
);
select is((select count(*) from public.x_daily_judgement_runs), 1::bigint,
  'creating a verification replay does not insert a scheduled daily run');
```

- [ ] **Step 2: Verify RED.**

Run: `supabase test db --file supabase/tests/033_x_v3_verification_replay.sql`

Expected: FAIL because the replay tables and RPCs are absent.

- [ ] **Step 3: Implement the immutable replay contract.**

Create the four tables with RLS enabled; grant table access to neither `anon` nor `authenticated`, and grant only the five RPCs to `service_role`. `x_v3_verification_replays` has a unique `source_batch_id`, target version fields, `status`, `attempt`, lease fields, safe `failure_class`, creator and timestamps. `x_v3_verification_replay_sources` copies exactly each included source, original range task, original v2 segment and canonical post IDs at creation time. `x_v3_verification_segments` and `x_v3_verification_versions` reject update/delete via the existing immutable trigger pattern.

`create_x_v3_verification_replay` must check both admin identity and the exact source batch properties before freezing sources. `claim_*` must claim only the caller-provided replay ID, increment attempt once and set a bounded lease; it must never scan scheduled work. `get_*_context` must return only frozen source IDs/display names, post/context input, and opaque replay identity. `complete_*` validates exact post coverage, v3 parser-compatible payload shape and daily ownership, then atomically inserts version-2 post analyses, replay segments and one daily version before status `succeeded`. `fail_*` accepts only `timeout`, `provider_failure`, `empty_response`, `invalid_json`, `schema_error`, `persistence_failure` and sets terminal `failed` without retry.

- [ ] **Step 4: Extend pgTAP coverage.**

Add cases for duplicate creation, wrong batch status/window, excluded source exclusion, non-v3 payload rejection, mismatched analysis/evidence rejection, atomic rollback after a bad second source, and assertions that original `x_collection_batches`, `x_daily_judgement_runs`, `x_daily_viewpoint_segments` and version-1 analyses remain byte-for-byte unchanged. Add a successful fixture that proves exactly three frozen source rows, v3 `@2` analysis refs, one replay segment per source and one verification version.

- [ ] **Step 5: Verify GREEN and regenerate types.**

Run: `supabase test db --file supabase/tests/033_x_v3_verification_replay.sql`

Expected: PASS. Then run the repository’s discovered `supabase gen types` command and update only the generated additions in `apps/control-plane/src/lib/db/types.ts`.

- [ ] **Step 6: Commit.**

```bash
git add supabase/migrations supabase/tests/033_x_v3_verification_replay.sql apps/control-plane/src/lib/db/types.ts
git commit -m "feat: add X v3 verification replay contract"
```

### Task 2: Control-plane Worker endpoints and safe Reader projection

**Files:**
- Create: `apps/control-plane/src/lib/db/repositories/x-v3-verification-replays.ts`
- Create: `apps/control-plane/src/app/api/admin/x/v3-verification-replays/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-v3-verification-replays/[replayId]/claim/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-v3-verification-replays/[replayId]/context/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-v3-verification-replays/[replayId]/complete/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-v3-verification-replays/[replayId]/failure/route.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx`

**Interfaces:**
- Consumes: authenticated admin creation request and device-authenticated opaque replay ID/attempt/payload.
- Produces: strict JSON endpoints and `XReaderDate.judgement.batches[*].verificationReplay` safe presentation data.

- [ ] **Step 1: Write failing API and Reader tests.**

Add an API test that unauthenticated/ordinary user creation gets `403`, an admin request containing only `{ source_batch_id }` gets `202` and an opaque replay id, and Worker routes reject malformed IDs, attempts and payload fields with `422`. Add Reader/component fixtures containing a failed scheduled batch plus a successful replay and assert:

```tsx
expect(screen.getByText("验证恢复（非定时任务）")).toBeInTheDocument();
expect(screen.getByText("当日判断未能完成，稍后会重试。")).toBeInTheDocument();
expect(screen.queryByText(/replay-|@2|analysis_ids|evidence_post_ids|prompt_version/i)).not.toBeInTheDocument();
```

- [ ] **Step 2: Verify RED.**

Run: `cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/x-reader.test.tsx`

Expected: FAIL because verification endpoints and presentation fields do not exist.

- [ ] **Step 3: Implement repository and routes.**

Implement repository parsers that reject unknown keys and call only the Task 1 RPCs. Admin creation uses `requireRole("admin")`; Worker routes use the existing Worker device authentication helpers and return only public-safe acknowledgements. Context response is available only to the authenticated claiming device and includes no telemetry or task identifiers beyond required opaque provider input.

- [ ] **Step 4: Implement Reader projection.**

Read only succeeded replay versions/segments linked to each displayed original batch. Reuse existing `judgementItems` and v3 segment presentation validators; add a boolean/string `verificationLabel` rather than exposing identity. Render a distinct card after the scheduled judgement card with the exact copy `验证恢复（非定时任务）`. Preserve date descending order, original failure copy, source filters and all legacy v2 rendering.

- [ ] **Step 5: Verify GREEN and commit.**

Run the Task 2 test command; expected PASS. Then:

```bash
git add apps/control-plane/src/lib/db/repositories/x-v3-verification-replays.ts apps/control-plane/src/app/api/admin/x/v3-verification-replays apps/control-plane/src/app/api/worker/x-v3-verification-replays apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/app/api/api.integration.test.ts apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts apps/control-plane/src/components/reader/x-reader.test.tsx
git commit -m "feat: expose X v3 verification replay safely"
```

### Task 3: One-off Worker protocol and v3 replay runtime

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`
- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Modify: `workers/v0/src/invest_hub_worker/cli.py`
- Create: `workers/v0/tests/test_x_v3_verification_replay.py`
- Modify: `workers/v0/tests/test_protocol.py`
- Modify: `workers/v0/tests/test_cli.py`

**Interfaces:**
- Consumes: explicit replay id and current Worker credential.
- Produces: one Provider execution sequence, `post` then `window` then `daily`, and exactly one terminal replay acknowledgement.

- [ ] **Step 1: Write failing Worker tests.**

Add a runtime fixture with two source snapshots and assert the Provider operations occur in this exact order:

```python
assert operations == [
    "v3_x_post_analysis", "v3_x_post_analysis", "v3_x_window",
    "v3_x_post_analysis", "v3_x_window", "v3_x_cross_blogger",
]
```

Add tests that malformed post/window/daily output calls only `fail_x_v3_verification_replay(..., "schema_error")`; no `schedule_tick`, `claim`, OpenCLI invoker or `run_x_daily_judgement_once` is called. Add CLI tests that `run-x-v3-verification` requires `--replay-id`, uses `V2_REAL_X_ACK`, has no `--once`/poll option, and reports only status/error class.

- [ ] **Step 2: Verify RED.**

Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_v3_verification_replay.py' -v`

Expected: FAIL because the one-off command and protocol methods do not exist.

- [ ] **Step 3: Implement strict protocol and runtime.**

Add `claim_x_v3_verification_replay(replay_id)`, `get_x_v3_verification_replay_context(replay_id, attempt)`, `complete_x_v3_verification_replay(completion)` and `fail_x_v3_verification_replay(...)`, each with exact field-set/type validation mirroring existing daily protocol methods. Add `XVerificationReplayRuntime.execute` that derives allowed IDs exclusively from the frozen context, invokes existing v3 post/window parsers and `XDailyJudgementRuntime`-equivalent daily validation, and builds one combined completion payload. No method may import an X connector or an OpenCLI invoker.

- [ ] **Step 4: Add one-off CLI command.**

Add `run-x-v3-verification` to `build_parser` with required `--config`, `--credential`, `--prompt-path`, `--evidence-dir`, `--replay-id` and optional `--worker-name`; do not add it to `_run_scheduled`. Build only provider runtimes and `WorkerProtocol`, heartbeat `idle`, claim the supplied ID, execute once, then print `{status,error}`. Refuse if `V2_REAL_X_ACK != "authorized"` or any config includes non-X sources.

- [ ] **Step 5: Verify GREEN and commit.**

Run focused tests plus `test_protocol.py` and `test_cli.py`; expected PASS. Then:

```bash
git add workers/v0/src/invest_hub_worker/protocol.py workers/v0/src/invest_hub_worker/runtime.py workers/v0/src/invest_hub_worker/cli.py workers/v0/tests/test_x_v3_verification_replay.py workers/v0/tests/test_protocol.py workers/v0/tests/test_cli.py
git commit -m "feat: run one-off X v3 verification replay"
```

### Task 4: Full verification, controlled release, one-off execution and acceptance

**Files:**
- Modify: `docs/superpowers/plans/2026-08-04-x-v3-verification-replay.md`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`
- Modify: `docs/project-status.md`

**Interfaces:**
- Consumes: committed main, remote migration and deployed Worker/Reader contracts.
- Produces: one production verification result and evidence-backed acceptance record.

- [ ] **Step 1: Run full local verification.**

```bash
supabase test db
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
cd apps/control-plane && npm test -- --run && npm run lint && npm run build
cd ../.. && git diff --check && bash scripts/v0/redact-check.sh
```

Expected: every command passes; record any pre-existing production-build environmental failure separately and run only the existing approved fallback.

- [ ] **Step 2: Deploy additively.**

Confirm clean release diff, stop Worker claiming only while applying the one generated migration, dry-run and apply it, push `main`, deploy the linked Vercel production project, verify Ready/stable `/x`, and reload the existing Worker checkout. Do not create or edit a launchd plist, cron job or regular scheduler task.

- [ ] **Step 3: Create and execute exactly one replay.**

Using the authenticated admin API/RPC, create the replay for the exact 08:00 failed batch. Then invoke the explicit new Worker command exactly once from the existing owner-only config/credential/evidence environment. Capture only status/error class and opaque IDs in local operational logs; do not print real X text or credentials.

- [ ] **Step 4: Production acceptance.**

Run read-only SQL aggregate checks proving: original failure still `judgement_failed`; no scheduled batch/run count changed; one succeeded replay has three source snapshots, v3 post/window versions and one daily version. In an existing authenticated production `/x` tab, verify the original failure remains visible, the labelled verification card is visible, v3 reader categories render, date/filter behavior still works, and no internal identifiers or Prompt/telemetry are visible.

- [ ] **Step 5: Record and commit.**

Mark completed plan checkboxes with actual test counts, migration version, commit/deployment and execution outcome. Commit and push the journal/status/plan only after production acceptance; if replay fails, record the terminal failure and stop without retrying.

```bash
git add docs/superpowers/plans/2026-08-04-x-v3-verification-replay.md docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md docs/project-status.md
git commit -m "docs: record X v3 verification replay release"
git push origin main
```
