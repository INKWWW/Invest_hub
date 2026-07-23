# V2 X 指定博主信息收集与阅读 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Plan status:** Draft — 待用户审阅批准。批准前不得执行任何一个实现任务；真实 X 采集、远程 migration、部署和发布还需要在相应任务开始前取得明确授权。

**Spec:** [V2 X 指定博主信息收集与阅读 Spec](../specs/2026-07-22-v2-x-information-collection-and-reader-design.md)（已批准）

**Goal:** 在不影响既有 Discord 行为的前提下，为管理员指定的 X 博主建立独立、可恢复、可追溯的时间范围采集、每日中文摘要和安全阅读闭环。

**Architecture:** X 作为 `sources` 中独立的 `source_type`，其博主身份与帖子上下文通过 X 专用扩展表保存，而不是复用 Discord 作者规则。控制面继续生成不可变的 `(start_at, end_at]` 范围并在完成回执后推进水位；本地 Worker 通过一个受限的 X Active Adapter 逐页持久化，直到抵达下界或验证历史耗尽。X Reader 只读取安全摘要投影和帖子类型/时间/原始链接，管理员操作、原文与运行诊断保持隔离。

**Tech Stack:** 现有 Next.js App Router + TypeScript 控制面、Supabase/Postgres/RLS/pgTAP、Python 3.11+ Worker、OpenCLI Browser Bridge、Codex CLI/Mock Provider、Vitest、Python `unittest`、既有 V1.1 时间窗与脱敏检查链路。

## Global Constraints

- 仅在用户本人已登录且正常可见的 X 网页会话中采集；不调用直接 X REST API，不自动化普通用户 Token，不将登录态离开 owner-only 本地环境。
- 以 `Asia/Shanghai` 的不可变 `(start_at, end_at]` 范围为完成边界；页数、滚动次数和卡片数量只能作 telemetry，不能作为成功条件。
- 每位博主独立配置、checkpoint、恢复游标、任务、失败状态和摘要版本；一个博主失败不得阻断其他博主。
- 只使用 Codex CLI 作为真实 Provider 候选；Mock 仅用于确定性测试；不实现 GLM 或自动 fallback。
- 图片、视频、PDF、音频、表格与外部文章正文不解析；只保存元数据、链接卡片和不确定性提示。
- 普通 Reader 和其 API 不得返回原始正文、内部 ID、本地引用、Worker/Provider/Prompt 诊断或凭据；管理员功能须在路由、API 与 RLS 三层隔离。
- 真实 X 正文、账户、URL、Cookie、Profile、私有 Prompt、完整模型响应和本地 evidence 不得进入 Git、公开 fixture、Vercel 或普通日志。
- 本 Plan 获批前不写代码、不执行真实 X 会话、不改共享协议、不应用 migration、不部署。

### 已确认的 V2 X 日内增量与恢复语义

- 每位启用博主的逻辑范围截止点固定为 `08:00`、`12:00`、`16:00`、`20:00` 和**次日 `00:00`**（`Asia/Shanghai`）。次日 `00:00` 的日终任务可在 `00:05` 实际启动，但其不可变 `end_at` 仍为 `00:00`；运行时刻不得改变内容时间归属。
- 连续覆盖范围永远从该博主的**最后成功 checkpoint**开始，而不是从上一个计划触发时刻开始。若 `12:00` 任务失败，`16:00` 任务必须补齐自该博主最后成功 checkpoint 至 `16:00` 的未确认连续范围；失败任务不得推进 checkpoint。
- 每次任务在逻辑连续范围之前额外读取最多 30 分钟的重叠复查窗口。稳定帖子 ID 使该窗口幂等；它用于发现页面排序变化、延迟可见和临界加载问题，不能制造重复 Canonical 帖子或重复摘要输入。逻辑连续范围、重叠扫描起点和实际 `end_at` 都须保留在任务快照中。
- 新博主首次启用时，初始连续范围为其启用当日 `00:00` 至最近一个已到达的逻辑截止点；不因此默认发起更早历史补采。若日终任务或任一后续任务跨日恢复，优先补齐最早未确认范围。
- 帖子和每日摘要按帖子 `occurred_at` 换算后的上海自然日归属，而不是按任务运行日期归属。次日补到的前一日帖子更新前一日的追加式摘要版本。
- 只有一个范围完整成功且该博主的任一受影响上海自然日确有新增 Canonical 帖子时，才调用 Codex CLI 生成或更新相应日期的摘要版本；已验证的完整空范围为 `no_new_data`，不调用 Provider，也不伪造新摘要版本。
- Codex CLI 的语义输出采用“逐帖不可变分析 → 窗口不可变综合观点 → 确定性追加式每日视图”。后续调用不得把既有 LLM 结论作为可编辑输入；后续帖子只能追加新的区段或明确的后续变化，绝不回写已展示的逐帖分析或窗口观点。新的每日视图版本只由既有区段按时间顺序确定性拼接而成，旧版本保留并默认折叠。

## 1. 目标文件、依赖与交付顺序

| 阶段 | 主要文件 | 依赖 | 可验收产物 |
| --- | --- | --- | --- |
| 1 | X 数据 migration、pgTAP、类型与契约 | 无 | X 与 Discord 的来源/任务/帖子事实隔离，且旧数据保持有效 |
| 2 | 本地 X 配置、X Active Adapter、公开 fixture | 1 的类型 | 公开 fixture 能验证四类帖子与分页边界；真实路径有 Go/No-Go 门槛 |
| 3 | Worker claim/range runtime、scheduler、持久化 | 1、2 | 每博主逐页持久化、恢复与范围完成不串扰 |
| 4 | X strict schema、Prompt、daily summaries | 1、3 | 每博主每日摘要只引用确认的 X Canonical 帖子 |
| 5 | 管理 API/UI、X Reader 与安全 DTO | 1、4 | 管理员操作可用，普通用户只读安全 X 内容 |
| 6 | 跨层 E2E、真实授权验收、文档与发布证据 | 1–5 | 全量确定性验证、授权结果和状态文档一致 |

每个 Task 先写失败测试、再做最小实现、再运行其聚焦验证并独立提交。任何 X 采集验证失败时，保留失败分类和 owner-only evidence，停止后续真实验收；不得以假空结果、固定页数或替代采集框架继续。

## 2. Task 1 — X 领域模型、权限与任务契约

**Files:**

- Create: `supabase/migrations/012_v2_x_sources_and_posts.sql`
- Create: `supabase/tests/012_v2_x_sources_and_posts.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`
- Modify: `contracts/v0/task-claim.schema.json`, `contracts/v0/worker-persistence.schema.json`, `contracts/v0/window-range-completion.schema.json`
- Modify: `apps/control-plane/contracts/v0/task-claim.schema.json`, `apps/control-plane/contracts/v0/worker-persistence.schema.json`, `apps/control-plane/contracts/v0/window-range-completion.schema.json`
- Modify: `apps/control-plane/src/lib/contracts.test.ts`, `apps/control-plane/src/lib/tasks/state-machine.test.ts`

**Interfaces:**

- `sources.source_type` becomes the exact union `discord | x`; `sync_tasks.task_type` becomes `discord_sync | x_sync`. Database checks reject any other value and reject a source/task type mismatch.
- `x_source_profiles(source_id, requested_handle, account_id, display_name, resolution_status, enabled)` has one row per X source. `resolution_status` is `pending | resolved | ambiguous`; only `resolved` rows may carry a non-null `account_id`.
- `x_post_contexts(canonical_message_id, post_type, post_url, quoted_post_id, reply_to_post_id, reposted_post_id, context_status, attachments)` records one X-specific fact row. `post_type` is `original | quote | reply | repost`; `context_status` is `complete | unavailable | deleted | unresolved`.
- `x_post_analyses(canonical_message_id, analysis_version, blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, evidence_refs)` is append-only and has exactly one accepted analysis for each `(canonical_message_id, analysis_version)`. A quote analysis stores the configured blogger's added commentary separately from the visible quoted-post viewpoint; unavailable context is represented explicitly, never inferred.
- `x_daily_viewpoint_segments(source_id, natural_date, range_task_id, segment_version, occurred_from_at, occurred_through_at, window_viewpoints, post_analysis_refs, evidence_refs)` is append-only. One completed range may create at most one segment per affected source/date; later ranges append a new segment and cannot mutate prior segment text or references. The existing/additive daily-presentation version records a deterministic ordered snapshot of these segment identities, not a new LLM rewrite of their prose.
- X claims use the existing logical continuous `capture_range` shape and set `task_type: "x_sync"`. The task snapshot additionally preserves `scheduled_window_key`, the fixed `end_at`, `overlap_start_at` and the current checkpoint from which its continuous range began. The source snapshot includes only `source_type`, resolved account identity, display name and parameter version, never a URL or local profile reference.

- [ ] **Step 1: Write failing pgTAP and contract tests.**

  Cover acceptance/rejection of `x`/`x_sync`, rejection of a Discord source with `x_sync`, one source-to-profile mapping, pending/resolved/ambiguous constraints, every permitted post type, context-link consistency, unique `(source_id, external_message_id)`, a one-year raw retention expiry, user RLS denial, and range-completion rejection when a task lacks its matching X post facts. Add immutable per-post-analysis and per-window-segment constraints, quote-comment versus quoted-post viewpoint separation, and rejection of an update that would overwrite an accepted analysis or segment.

- [ ] **Step 2: Run the focused failures.**

  Run: `supabase test db` and `cd apps/control-plane && npm test -- --run src/lib/contracts.test.ts src/lib/tasks/state-machine.test.ts`.

  Expected before implementation: source/task type checks reject X and TypeScript contracts expose only `discord` / `discord_sync`.

- [ ] **Step 3: Implement the minimum additive migration and typed contract changes.**

  Alter only constraints and add X-specific tables/RLS/policies; do not rewrite existing Discord rows or replace current V1.1 range functions. Extend persistence validation so an X row carries exactly one permitted post type, an HTTPS X post URL, zero or one matching context relation, attachment metadata without body extraction, and no `local_raw_ref` in reader-facing data. Add append-only per-post analysis and per-window viewpoint-segment facts, each linked to its input Canonical/context identities and range task. Define rollback as disabling X sources and stopping uncompleted `x_sync` tasks while retaining completed X facts, analysis/segment versions and task events; do not drop tables or delete Discord/X history as a rollback shortcut.

- [ ] **Step 4: Verify and commit.**

  Run: `supabase test db`; `cd apps/control-plane && npm test -- --run src/lib/contracts.test.ts src/lib/tasks/state-machine.test.ts`; `git diff --check`.

  Commit: `feat(v2): add X source and post contracts`.

## 3. Task 2 — Owner-only X 配置与受限 Active Adapter 验证

**Files:**

- Modify: `workers/v0/src/invest_hub_worker/config.py`, `workers/v0/src/invest_hub_worker/cli.py`
- Create: `workers/v0/src/invest_hub_worker/connectors/x_active_adapter.py`
- Modify: `workers/v0/src/invest_hub_worker/connectors/base.py`, `workers/v0/src/invest_hub_worker/connectors/__init__.py`
- Modify: `workers/v0/src/invest_hub_worker/canonical.py`
- Create: `workers/v0/tests/fixtures/x_public_timeline_page.json`
- Create: `workers/v0/tests/test_x_active_adapter.py`, `workers/v0/tests/test_x_canonical.py`
- Modify: `workers/v0/tests/test_config.py`

**Interfaces:**

- `LocalWorkerConfig` gains `source_type: Literal["discord", "x"]` and an owner-only `source_url`; its redacted representation exposes only source ID, type, parameter version and configuration hash.
- `XActiveAdapter.fetch_page(source, cursor, *, end_at)` returns `RawPage` with a fresh response match, opaque cursor, X page telemetry and a local-only raw ref. It raises only classified `opencli_missing`, `opencli_stale`, `opencli_contract`, `unauthorized`, `timeout` or `preflight` failures.
- `CanonicalMessage.metadata["x"]` contains `post_type`, `post_url`, target post IDs, `context_status` and attachment metadata; the canonicalizer rejects an X page missing its stable post ID, stable author ID, timezone-aware timestamp, permitted type or valid link.

- [ ] **Step 1: Write public-fixture failing tests.**

  Build a fully artificial X timeline fixture with an original, quote, reply and no-comment repost. Assert that the adapter matches a fresh expected request, normalizes no account URL into logs, preserves an opaque next cursor, and that the canonicalizer keeps the quote/reply/repost relationships separate. Add failures for a stale response, no response, duplicate stable post ID, ordinary repost with a fabricated author comment, missing time and an external-article attachment treated as parsed text.

- [ ] **Step 2: Run the focused failures.**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_config.py workers/v0/tests/test_x_active_adapter.py workers/v0/tests/test_x_canonical.py -v`.

  Expected before implementation: the config parser rejects `source_type=x`, and no X adapter/canonical path exists.

- [ ] **Step 3: Implement the X-only local boundary.**

  Extend the config schema without weakening `0600` checks. Implement request matching and one bounded retry in `XActiveAdapter`; keep X URL, browser profile and raw payload reference local. Reuse `RawPage` only as a transport envelope, and add X metadata validation in `Canonicalizer` without changing Discord mapping semantics.

- [ ] **Step 4: Perform the real X Go/No-Go check only after explicit authorization.**

  With one user-authorized, owner-only X profile and one configured account, run the adapter’s non-persisting diagnostic path. Record only category coverage, page-boundary result, response freshness outcome and failure class in protected local evidence. If the adapter cannot obtain fresh, type-complete, time-bounded data, record `x_collection_unverified`; do not create a cloud task, apply a remote migration, deploy or introduce a fallback collector.

- [ ] **Step 5: Verify and commit.**

  Run the Step 2 command, `bash scripts/v0/redact-check.sh`, and `git diff --check`.

  Commit: `feat(v2): validate X active adapter boundary`.

## 4. Task 3 — X 范围任务、逐页持久化、恢复与调度

**Files:**

- Create: `supabase/migrations/013_v2_x_windowed_tasks.sql`, `supabase/tests/013_v2_x_windowed_tasks.sql`
- Modify: `apps/control-plane/src/lib/db/repositories/windowed-sync.ts`, `apps/control-plane/src/lib/db/repositories/tasks.ts`
- Modify: `apps/control-plane/src/app/api/worker/tasks/claim/route.ts`
- Modify: `apps/control-plane/src/app/api/worker/tasks/[taskId]/persist/route.ts`, `apps/control-plane/src/app/api/worker/tasks/[taskId]/capture-segments/route.ts`, `apps/control-plane/src/app/api/worker/tasks/[taskId]/range-complete/route.ts`
- Modify: `apps/control-plane/src/app/api/worker/schedule/tick/route.ts`
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`, `workers/v0/src/invest_hub_worker/worker.py`, `workers/v0/src/invest_hub_worker/runtime.py`, `workers/v0/src/invest_hub_worker/scheduler.py`
- Create/Modify: `workers/v0/tests/test_x_windowed_runtime.py`, `workers/v0/tests/test_scheduler.py`, matching route and repository tests

**Interfaces:**

- `create_windowed_x_sync_task(source_id, parameter_version, requested_by, trigger, end_at, scheduled_window_key)` creates or reuses only the oldest uncompleted `(start_at, end_at]` continuous range for that X source. Its `start_at` is the last successful checkpoint, never the previous scheduled trigger; its `overlap_start_at` is at most 30 minutes earlier but never before the Shanghai-day start containing `start_at`. The fixed cutoff key is one of `08:00`, `12:00`, `16:00`, `20:00` or next-day `00:00`; the last may execute at `00:05` without changing `end_at`.
- `create_bounded_x_history_task(source_id, parameter_version, requested_by, start_at, end_at)` creates one explicit, immutable history range. A historical result only advances continuous coverage when it is exactly contiguous with the current waterline; otherwise it remains an independently traceable backfill result.
- `XWindowedRuntime.execute(claim, on_capture_page, load_daily_fact_context)` persists each accepted page before advancing `resume_cursor`, reads the overlap window for idempotent recheck, excludes posts later than immutable `end_at`, and returns `range_completion` only after boundary proof for the logical continuous range. A newly observed stable ID inside the overlap is retained as a late-visible fact with audit linkage; a conflicting identity fails safely rather than overwriting an existing fact.
- `range-complete` verifies task/source type, active lease, stable receipts and X post context rows before atomically moving only that source’s `coverage_through_at`.

- [ ] **Step 1: Write failing range and recovery tests.**

  Cover two X sources with interleaved tasks; a first task that requires more than five pages; an interrupted sixth page; identical replay; a page with posts later than `end_at`; one source with `unauthorized`; late scheduled execution; manual-task reuse; an explicit bounded history range that is non-contiguous with continuous coverage; and a result that lacks an X post-context receipt. Add `08:00 → 12:00 → 16:00 → 20:00 → 00:00` logical cutoffs, actual `00:05` execution with fixed `00:00` end, a `12:00` failure recovered by the `16:00` task, 30-minute overlap replay with no duplicate Canonical posts, a late-visible overlap post, a new-source same-day initialization and cross-day recovery that updates the original post date. Assert no source waterline moves until its own completion, non-contiguous history does not falsely advance coverage, and no non-X task is routed to the X runtime.

- [ ] **Step 2: Run the focused failures.**

  Run: `supabase test db`; `cd apps/control-plane && npm test -- --run src/lib/db/repositories/windowed-sync.test.ts src/app/api/api.integration.test.ts`; `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_windowed_runtime.py workers/v0/tests/test_scheduler.py -v`.

  Expected before implementation: only Discord-specific task creation/runtime routing exists, and X claims cannot be completed.

- [ ] **Step 3: Implement additive X range semantics.**

  Add X-specific RPC wrappers and task snapshot data while reusing the existing range tables and receipt ordering. Make `Worker` dispatch on exact `task_type`; keep current Discord window behaviour on its existing branch. The X path must persist raw/Canonical/context facts, submit an idempotent capture segment, renew its lease, and only then advance local resume state. Scheduler discovery includes enabled, initialized X sources but never creates a task for disabled, unresolved or unconfigured sources.

- [ ] **Step 4: Verify and commit.**

  Run the Step 2 commands, `bash scripts/v1/run-v1-1-e2e.sh`, and `git diff --check`.

  Commit: `feat(v2): run X collection in recoverable windows`.

## 5. Task 4 — X 逐帖理解、窗口观点与追加式证据

**Files:**

- Create: `workers/v0/prompts/v2_x_chunk.md`, `workers/v0/prompts/v2_x_window.md`
- Modify: `workers/v0/src/invest_hub_worker/structured.py`, `workers/v0/src/invest_hub_worker/summaries.py`
- Modify: `workers/v0/src/invest_hub_worker/providers/base.py`, `workers/v0/src/invest_hub_worker/providers/codex_cli.py`, `workers/v0/src/invest_hub_worker/providers/mock.py`
- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Create/Modify: `workers/v0/tests/test_x_structured_output.py`, `workers/v0/tests/test_x_summaries.py`, `workers/v0/tests/test_provider_retry.py`

**Interfaces:**

- A `PostBundle` contains one configured-author post's stable identity, type, occurred time, text and X link, plus only its actually visible quote/reply context. A transport chunk contains 1–100 independent `PostBundle`s in chronological order; the `100` upper bound follows the current Codex CLI capacity candidate. An over-budget bundle stands alone and is classified rather than silently truncated. Chunk transport must never permit cross-post attribution.
- `parse_v2_x_chunk_output(value, allowed_post_ids, allowed_context_post_ids)` returns exactly one immutable analysis per input configured-author post: `post_id`, `blogger_viewpoint`, `arguments`, `uncertainties`, `evidence_post_ids`, `post_link`, and, only for visible quote context, a separately attributed `quoted_post_viewpoint`. Every evidence or context identity must belong to this bundle; a normal repost has no `blogger_viewpoint`.
- `parse_v2_x_window_output(value, allowed_analysis_ids)` returns `schema_version: "v2-x-window"`, `natural_date`, immutable `range_task_id`, `occurred_from_at`, `occurred_through_at`, `window_viewpoints`, `analysis_ids`, `evidence_post_ids` and `uncertainties`. It receives only this completed range's validated per-post analyses, never prior LLM prose.
- `build_v2_x_daily_viewpoint_timeline` appends immutable source/date window segments from confirmed range facts only, then deterministically creates a new daily-presentation version by ordering their identities and unchanged text. A later range adds a new segment; it cannot rewrite previous segments. `no_new_data` and incomplete ranges do not create a Provider call or a synthetic segment.

- [ ] **Step 1: Write strict-schema failures.**

  Reject unknown post IDs or context IDs, a reposted original claimed as the configured author’s statement, quote text merged into the author comment, a quoted-post viewpoint returned when quote context is unavailable, a reply whose unavailable parent is invented, cross-post evidence IDs, any media/OCR/external-body conclusion, missing uncertainty fields, out-of-range timestamps and a window output that cites an unpersisted analysis. Include Mock fixtures for no new posts, no attributable viewpoint, mixed post types, visible quotes, unavailable context, a later contrary post and an attempted overwrite of an earlier segment.

- [ ] **Step 2: Run the focused failures.**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_structured_output.py workers/v0/tests/test_x_summaries.py workers/v0/tests/test_provider_retry.py -v`.

  Expected before implementation: no `v2-x-*` schema exists and X posts can be interpreted only by Discord-oriented summaries.

- [ ] **Step 3: Implement strict per-post operations and append-only window segments.**

  Keep private prompts outside Git; repository templates describe only JSON shape and boundary rules. Add separate Mock/Codex operations so a provider failure remains classified. Use chunking solely as bounded transport: each post is analyzed independently, and a visible quote is separately attributed from the blogger's comment. After all per-post analyses for a complete range persist, generate one immutable window viewpoint segment from those analyses only. A same-day later range appends a segment for the post's Shanghai date; a cross-day recovery appends to the original date rather than the run date. Then deterministically build the new current daily presentation by appending the new segment to prior segment identities; do not provide prior segment prose to Codex CLI and do not overwrite it. A no-new-post range returns a safe status without inventing a segment or daily-presentation version.

- [ ] **Step 4: Verify and commit.**

  Run the Step 2 command and `git diff --check`.

  Commit: `feat(v2): add X post analyses and viewpoint timeline`.

## 6. Task 5 — X 管理入口与安全阅读体验

**Files:**

- Create: `apps/control-plane/src/lib/db/repositories/x-sources.ts`, `apps/control-plane/src/lib/db/repositories/x-reader.ts`
- Create: `apps/control-plane/src/app/api/admin/x/sources/route.ts`, `apps/control-plane/src/app/api/admin/x/sources/[sourceId]/coverage/route.ts`, `apps/control-plane/src/app/api/admin/x/manual-refresh/route.ts`, `apps/control-plane/src/app/api/admin/x/history/route.ts`
- Create: `apps/control-plane/src/app/api/reader/x/route.ts`, `apps/control-plane/src/app/x/page.tsx`
- Create: `apps/control-plane/src/components/admin/XSourceForm.tsx`, `apps/control-plane/src/components/admin/XHistoryBackfillForm.tsx`, `apps/control-plane/src/components/reader/XReader.tsx`, `apps/control-plane/src/components/reader/x-reader-presentation.ts`
- Modify: `apps/control-plane/src/app/admin/page.tsx`, `apps/control-plane/src/components/admin/AdminShell.tsx`, `apps/control-plane/src/components/reader/ReaderStatus.tsx`, `apps/control-plane/src/app/globals.css`
- Create/Modify: matching repository, route, component and responsive presentation tests

**Interfaces:**

- `createXSource({ displayName, requestedHandle, parameterVersion })` creates an enabled X source with `pending` identity until the local Worker verifies a unique account; the public response has no source URL.
- `readXDay({ sourceKey?, date? })` returns `XReaderDay[]` containing only display name, natural date, status, a default-open `current_daily_timeline` and collapsed historical daily-presentation versions. The current timeline contains chronological `window_segments`; each segment has its window viewpoints and notices, while its per-post analyses, quote relations and `PostLink[]` of `{ type, occurredAt, href }` are collapsed evidence details.
- `POST /api/admin/x/manual-refresh` accepts `{ source_id }`; server time sets `end_at`, reuses the existing active range and returns only a safe task state. Non-admin callers receive 403.
- `POST /api/admin/x/history` accepts `{ source_id, start_at, end_at }`, validates a finite Shanghai range on the server, rejects an active overlap and returns only a safe queued task state. It does not imply that continuous coverage advanced.

- [ ] **Step 1: Write failing repository/API/component tests.**

  Cover admin creation/edit/disable, an unresolved identity message, coverage initialization, manual task reuse, finite historical backfill creation and overlap rejection, 401/403 responses, date/source selection, current daily timeline default-open with chronological window segments, historical daily-presentation versions default-collapsed, per-post analyses/quote relations/post links default-collapsed, immutable earlier segment text after a later range, all six Reader states, and absent raw body/internal ID/worker/prompt/provider fields in API JSON and initial HTML. Add 1280px and 375px assertions for source/date selectors and no horizontal overflow.

- [ ] **Step 2: Run the focused failures.**

  Run: `cd apps/control-plane && npm test -- --run src/lib/db/repositories src/app/api src/components/admin src/components/reader src/app/x/page.test.tsx`.

  Expected before implementation: no X routes or reader DTO exist, and Discord Reader cannot expose X-specific post links safely.

- [ ] **Step 3: Implement safe queries and content-first UI.**

  Build new X-specific repositories rather than branching `readDiscordDay`. Filter queries by `source_type = 'x'`, only include the completed current daily timeline plus collapsed historical presentation versions, and derive `no_new_messages` only from a confirmed complete range. XReader must render title, Shanghai date and chronological window viewpoints, then fold each segment's post analyses, quote attribution and `在 X 中打开` links; it must never render canonical content or mutate/rephrase an earlier segment. Add admin navigation without exposing configuration to ordinary readers.

- [ ] **Step 4: Verify and commit.**

  Run the Step 2 command, `npm run lint`, `npm run build`, and `git diff --check`.

  Commit: `feat(v2): add safe X reader and admin controls`.

## 7. Task 6 — 跨层验收、真实授权、文档与发布门禁

**Files:**

- Create: `tests/e2e/v2/fixtures.py`, `tests/e2e/v2/test_x_collection_reader_flow.py`, `tests/e2e/v2/test_x_recovery_and_permissions.py`
- Create: `scripts/v2/run-v2-e2e.sh`
- Modify: `docs/project-status.md`, `docs/README.md`
- Create: `docs/engineering-journal/2026-07-22-v2-x-information-collection.md`, `docs/spikes/2026-07-22-v2-x-decision-report.md`

**Interfaces:**

- The public V2 fixture represents only artificial X posts and exposes source-isolated task creation, page-by-page receipts, strict daily presentation and a reader projection with no raw content.
- `scripts/v2/run-v2-e2e.sh` runs database, worker, control-plane and V2 fixture tests without reading a Chrome profile, real URL, credential or private prompt.

- [ ] **Step 1: Write deterministic cross-layer tests.**

  Cover at least two X sources; all four post types; quote/reply/repost attribution; range completion after more than five pages; interrupted resume; duplicate replay; delayed range upper-bound exclusion; source-isolated failure; independent per-post analysis; quote-comment versus quoted-post viewpoint separation; immutable window-segment append; no-new-data distinction; ordinary-user 403/RLS; safe reader JSON/HTML; and desktop/375px presentation. Add the five fixed daily cutoffs, `00:05` execution with `00:00` logical end, a failed middle window recovered by its successor, 30-minute overlap idempotency, same-day initialization, and cross-day recovery whose segment remains on the original Shanghai date. Use only artificial fixture text and links.

- [ ] **Step 2: Implement the E2E runner and document deterministic evidence.**

  Make the runner execute focused V2 tests plus existing Discord V1.1 regression. Engineering documentation records only commands, aggregate counts, classified failures and limitations; it must not claim X was verified from fixture success alone.

- [ ] **Step 3: Obtain a separate explicit authorization before real X acceptance.**

  Do not perform this step merely because the Plan is approved. Before the first real action, ask for approval naming the owner-only X profile, the number of configured test accounts, whether bounded history is allowed, and whether a production deployment is in scope. With approval, validate one normal range, one manual range, one failure/recovery case, each accepted post type that is actually visible, normal-user reading and 375px presentation. Record only de-identified counts/statuses in owner-only evidence and the engineering journal.

- [ ] **Step 4: Apply remote migration and deploy only with separate authorization.**

  Before any remote change, run `bash scripts/v0/redact-check.sh` and `git diff --check`, verify the active Vercel project binding, verify migration order against the target database, then request the exact deployment authorization. Prepare the additive rollback described in Task 1 before applying migrations: disable X sources, cancel only unfinished `x_sync` tasks, keep completed versions/events, and leave all Discord state untouched. A Ready deployment alone is not acceptance; complete the protected reader/API probes and real user review described in Step 3.

- [ ] **Step 5: Final verification and documentation commit.**

  Run:

  ```bash
  supabase test db
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s tests/e2e/v2 -p 'test_*.py' -v
  cd apps/control-plane && npm test && npm run lint && npm run build
  cd ../.. && bash scripts/v1/run-v1-1-e2e.sh && bash scripts/v2/run-v2-e2e.sh
  bash scripts/v0/redact-check.sh
  git diff --check
  git status --short
  ```

  Expected: every deterministic suite passes; any real-acceptance item not explicitly authorized remains recorded as pending, not passed. Update status, journal and decision report only with results actually observed. Commit: `test(v2): verify X collection and reader`.

## 8. 验收矩阵与实施自审

| Spec requirement | Tasks | Evidence |
| --- | --- | --- |
| X/Discord source and task isolation | 1, 3, 6 | pgTAP, task routing tests, two-source E2E |
| Four post types and correct attribution | 1, 2, 4, 6 | public adapter fixture, canonical/schema tests, real authorized samples |
| No fixed page-count success condition | 2, 3, 6 | 5+ page fixture, range receipt and recovery tests |
| Per-author checkpoint, bounded history and failure isolation | 1, 3, 5, 6 | RPC/RLS tests, interrupted-source and history fixtures |
| Fixed daily cutoffs, overlap recheck and cross-day recovery | 1, 3, 4, 6 | scheduler/range tests, idempotency fixtures, version-date assertions |
| Independent per-post analyses and append-only daily viewpoint segments | 1, 4, 5, 6 | strict schemas, immutability tests, chronological Reader assertions |
| Media/external-body non-inference | 2, 4, 5, 6 | fixture/schema/reader warnings |
| Content-first desktop and 375px reader | 5, 6 | DTO/DOM tests and authorized visual review |
| Admin-only configuration and task operations | 1, 5, 6 | route tests, RLS, ordinary-user checks |
| Secrets and real-content protection | 2, 5, 6 | redaction check, safe DTO tests, owner-only evidence audit |
| Real X validity, migration and deployment | 2, 6 | separate user authorization and de-identified evidence |

Plan self-review before implementation:

- The only future shared-contract modifications occur in Task 1 and are additive, type-checked and regression-tested against Discord.
- Every real X, remote database and deployment operation has a separate explicit authorization gate.
- The scheduler derives every continuous range from the last successful checkpoint, not the previous trigger; its five Shanghai logical cutoffs, `00:05` day-end execution, 30-minute overlap and cross-day recovery are fixture-tested before any real acceptance.
- Chunking is bounded transport only: each configured-author post receives an independent, immutable analysis; quote context is separately attributed; newer window segments append without supplying older LLM prose for revision, and daily-presentation versions are deterministic segment snapshots rather than model rewrites.
- No Task treats fixed page count, missing response or provider failure as a successful empty range.
- Every Reader task excludes raw post bodies and runtime diagnostics by DTO and DOM tests, not by visual convention alone.
- `docs/intake.md` is preserved as the factual input; the currently unstaged user change must never be staged incidentally.
