# X 当日判断总结最终边界修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使跨博主 X 当日判断满足已批准 Spec 的冻结来源、上海自然日、失败隔离、证据归属、Reader 完整性和最小权限要求。

**Architecture:** 以 additive migration 收紧数据库为最终 authority：按逻辑 cutoff 冻结所有 enabled/resolved X 来源，批次/租约/失败状态只能通过受限 RPC 转移，judgement completion 在 DB 验证完整证据归属。Reader 由 immutable batch snapshot 建日期状态骨架，再叠加单博主 segment；HTTP 在安全 DTO 边界继续白名单化。Worker 仍使用原有 claim/context/complete 路径，不新增采集器或自动 regeneration。

**Tech Stack:** Supabase SQL/pgTAP，Next.js/TypeScript/Vitest，Python Worker unittest，现有 V2 deterministic runner。

## Global Constraints

- 不得重新采集、改写来源 snapshot、coverage、checkpoint、posts、analyses、segments 或 immutable judgement versions。
- 00:00 上海 cutoff 归属前一自然日；每个 judgement 只使用 `segment.natural_date = batch.natural_date` 的同日证据。
- 每个 scheduled cutoff 冻结所有当时 enabled + resolved X sources；落后/失败来源必须安全地记录为 excluded/delayed，不能从 snapshot 消失。
- 普通/管理员 JWT 不得直接 DML batch、batch source、run 或 version；状态转移只能经必要的 service-role RPC，Reader 只读安全投影。
- judgement 仅由 online、`x_sync` capable 且与 batch X source authorized worker 相符的 Worker 领取；lease owner 继续约束 context/complete/fail。
- initial failure 无成功版本时终态为 `judgement_failed`；regeneration failure 保留既有 succeeded version；lease expiry 受既有三次上限约束。
- 一切 completion authority（Worker parser、HTTP、DB）均须拒绝跨 source analysis/evidence、重复 ID、support/dissent overlap、空证据和任意 frozen opaque ID 出现在展示文本。
- `/x` 保持 all/source/date URL 语义；日期 → judgement（最新 cutoff 展开）→ 按 snapshot 的 blogger blocks；无 segment 状态不可消失。
- 仅本地测试/fixture；不得调用真实 X/OpenCLI/Browser/Codex、远端 migration、部署或 Worker restart。

---

### Task 1: Correct batch identity, source snapshot and Worker authority

**Files:**
- Create: `supabase/migrations/20260801150000_x_daily_judgement_batch_identity.sql`
- Create: `supabase/tests/027_v2_x_daily_judgement_batch_identity.sql`
- Modify: `apps/control-plane/src/lib/db/repositories/tasks.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/tasks.test.ts`

**Interfaces:** consumes existing scheduled X source configuration/worker authorization; produces an idempotent `ensure_due_x_collection_batches` that freezes all enabled/resolved sources per logical cutoff and claims only X-capable authorized Workers.

- [ ] **Step 1: Write failing pgTAP/repository tests.** Cover next-day 00:00 mapping to prior natural date, two sources where one is behind while the other reaches a later cutoff (both snapshot rows exist; behind one is excluded/delayed; output partial), multi-worker source ownership, Discord-only worker rejection, and segment selection exclusion when natural dates differ.
- [ ] **Step 2: Run RED.** Run the new pgTAP file and focused task repository tests; expect current cutoff/current-worker snapshot and claim behavior to fail.
- [ ] **Step 3: Implement additive DB authority.** Add logical-date helper and use it in batch creation/checks; build the snapshot from all enabled/resolved X sources, binding due tasks only where exact range exists and marking nonmatching/behind source safe excluded state; retain immutable source name. Restrict judgement claim/ensure to enrolled online `x_sync` capable authorized X Worker(s), and make task scheduler surface a safe `judgement_dispatch_failed` result without rolling back source scheduling.
- [ ] **Step 4: Green verify and commit.** Run local database reset/pgTAP, focused Node tests, lint and diff check; commit `fix(v2): harden X judgement batch identity`.

### Task 2: Lock lifecycle, retries, RLS and evidence authority

**Files:**
- Create: `supabase/migrations/20260801160000_x_daily_judgement_state_security.sql`
- Create: `supabase/tests/028_v2_x_daily_judgement_state_security.sql`
- Modify: `apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts`
- Modify: corresponding route tests
- Modify: `workers/v0/src/invest_hub_worker/structured.py`
- Modify: `workers/v0/tests/test_x_cross_blogger_judgements.py`

**Interfaces:** consumes Task 1 logical batch/snapshot; produces terminal-safe settlement/claim/failure RPCs and identical source-analysis-evidence validation at parser, HTTP and DB layers.

- [ ] **Step 1: Write failing boundary tests.** Assert successful/no-new batch cannot be settled into another initial run; expired attempt three becomes failed and does not become attempt four; initial terminal failure updates batch to judgement_failed while regeneration failure preserves succeeded; authenticated admin direct DML is denied; direct completion rejects cross-source/duplicate/overlap/empty evidence and opaque source/evidence IDs embedded in statement/uncertainty.
- [ ] **Step 2: Run RED.** Run targeted pgTAP, complete-route and Worker structured tests; observe every above path currently fails or leaks.
- [ ] **Step 3: Implement minimal final authority.** Lock and no-op/reject terminal settlement, remove authenticated DML policies/grants and make snapshot/run lifecycle append-only/state-checked, bound lease-expiry recovery at three attempts, update batch state only under defined initial/regeneration conditions, and enforce exact frozen `analysis→source→evidence` relations plus text token rejection in DB and route. Keep completion's existing lease lock and immutable version trigger.
- [ ] **Step 4: Green verify and commit.** Run database reset/pgTAP, focused Node/Python tests, lint and diff; commit `fix(v2): secure X judgement lifecycle and evidence`.

### Task 3: Restore Reader date/filter/history/status semantics

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Modify: `apps/control-plane/src/app/api/reader/x/route.ts`
- Modify: `apps/control-plane/src/app/api/reader/x/route.test.ts`
- Modify: `apps/control-plane/src/app/x/page.tsx`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Modify: component/page tests and `apps/control-plane/src/app/globals.css` only if required for the existing 375px layout.

**Interfaces:** consumes immutable batch snapshot, versions and safe segment fields; produces safe DTO `revisionHistory` and bloggers whose date status comes from batch source task, plus all/source/date URL-preserving Reader rendering.

- [ ] **Step 1: Write failing repository/component/route tests.** Cover current archived sources with retained judgement history, no-new/pending/failed/excluded blogger placeholder under its batch/date task rather than global latest task, revision history with latest current projection, latest cutoff (even pending/failed) expanded, all dates default, valid `?date=` hydration/share, source change retaining date, date change retaining source, and no hidden IDs/raw text in JSON/HTML.
- [ ] **Step 2: Run RED.** Run the focused Reader tests and observe segment-only/date-reset behavior fail.
- [ ] **Step 3: Implement safe projection/UI.** Query batch/version history independently of enabled current sources, derive blogger status from `x_collection_batch_sources.x_sync_task_id` and safe task attempt, create blocks even without segment, preserve archived history, expose only safe revision display fields, pass legal query date from page, and update both URL selectors atomically without forcing today's date. Expand the first cutoff batch and retain prior-revision details as collapsed safe history.
- [ ] **Step 4: Green verify and commit.** Run focused Reader tests, `npm test`, lint, Webpack build and diff; commit `fix(v2): complete X judgement Reader semantics`.

### Task 4: Full acceptance, governance truth and release gate

**Files:**
- Modify: `tests/e2e/v2/test_x_cross_blogger_daily_judgements.py`
- Modify: `scripts/v2/run-v2-e2e.sh`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`
- Modify: `docs/project-status.md`
- Modify: `docs/superpowers/plans/2026-07-31-x-cross-blogger-daily-judgement-summary.md`

**Interfaces:** consumes corrected DB/Worker/Reader boundaries; produces truthful deterministic evidence and approval/status records.

- [ ] **Step 1: Write failing acceptance cases.** Add state scenarios for lagging source partial coverage, 00:00 prior-day mapping, bounded expired lease, terminal initial/regeneration failure distinction, revision 1→admin regeneration→revision 2, actual Reader route safe output and all/source/date URL restoration.
- [ ] **Step 2: Run RED.** Run V2 runner and focused acceptance set; expect the new requirements to fail before Tasks 1–3.
- [ ] **Step 3: Complete harness and governance.** Keep Python only for actual local state/Worker contract; run actual Node route/repository tests from the V2 script. Update the initial Plan status to approved (user confirmation 2026-07-31), list both implementation plans as approved in project status, list migrations 090000/100000/120000/130000/140000/150000/160000 in order, state no production action executed, and distinguish default Turbopack build environment failure from passing Webpack supplemental evidence.
- [ ] **Step 4: Run final deterministic gate and commit.** Run database reset/pgTAP, full Worker with the existing main V0 virtualenv, V2 runner, control-plane tests/lint/default build/Webpack build/redact/diff. Record exact results; never substitute a failed command with another. Commit `test(v2): verify final X judgement boundaries`.

## Plan self-review

Task 1 addresses snapshot/date/worker authority; Task 2 enforces lifecycle, ACL and evidence correctness at the final authorities; Task 3 closes every Reader/filter/history finding; Task 4 revalidates cross-layer behavior and corrects governance evidence. The plan remains additive, introduces no new provider or collector and preserves the separately authorized regeneration design.
