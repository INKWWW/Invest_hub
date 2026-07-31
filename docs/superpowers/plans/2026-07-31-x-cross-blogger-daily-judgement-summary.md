# X 跨博主当日判断总结 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Plan status:** **已批准（用户确认 2026-07-31）**。代码、迁移与本地确定性验收已按本计划启动；远端 migration、部署、Worker 重启、真实 X/Browser/OpenCLI/Codex 调用和生产验收仍须逐项明确授权。

**Spec:** [X 跨博主当日判断总结 Spec](../specs/2026-07-31-x-cross-blogger-daily-judgement-summary-design.md)（已批准）

**Goal:** 在不影响每来源 X 采集与 checkpoint 的前提下，为每个上海例行截止时刻生成一条可追溯、可修订的跨博主当日判断总结，并按“日期 → 判断总结 → 博主分块”安全展示。

> **Amendment（用户确认 2026-08-01）：** 尚无成功版本时，Provider 失败只重试独立 judgement run，首次成功写入 revision 1。已成功批次的新版本必须由管理员显式、可审计的 regeneration 动作创建；该 run 成功后才追加 revision 2 或更高版本。具体实现和 Task 5 closure 见 [2026-08-01 regeneration plan](2026-08-01-x-daily-judgement-regeneration.md)。

**Architecture:** 调度器在创建同一 `scheduled_window_key` 的 X 来源任务时，同时冻结一个 `x_collection_batches` 来源快照；每个来源仍独立完成现有 `x_sync` 范围。控制面只在批次结算后排入独立 `x_daily_judgement_runs` 工作，不让判断模型失败反向阻断范围完成或 coverage。X Worker 使用既有本地 Codex CLI Provider 对已持久化的窗口段和逐帖分析做严格结构化归纳；Reader 仅消费安全投影、展示最新批次和每位博主的最新窗口。

**Tech Stack:** 现有 Supabase/Postgres/RLS/pgTAP、Next.js App Router + TypeScript、Python 3.11+ Worker、Codex CLI/Mock Provider、Vitest、Python `unittest`；不新增第三方依赖。

## Global Constraints

- 例行批次以 `Asia/Shanghai` 的既有 `08:00 / 12:00 / 16:00 / 20:00 / 次日 00:00` 逻辑截止时刻和精确 `scheduled_window_key` 标识；手动和历史 X 任务不进入跨博主例行批次。
- 所有跨博主判断只引用已完成批次中已持久化的 `x_daily_viewpoint_segments`、`x_post_analyses` 及其明确来源；不得输入原始 X 正文、范围外记录、旧判断文本、未解析媒体或外部文章正文。
- 批次来源快照、判断版本和证据引用均追加式保存；不得覆盖既有 X 单博主段、分析、任务、coverage 或 checkpoint。
- `complete`、`partial`、`no_new_information`、`judgement_pending` 与 `judgement_failed` 必须严格区分；来源失败和判断失败绝不显示为“无新增”。
- 每来源 `x_sync` 的完成、失败隔离、重试和 checkpoint 语义不因本功能改变；判断生成失败只重试独立判断工作。
- 真实 Provider 仍为本机 Codex CLI；仓库不传入固定 `--model`，但持久化安全的 Provider、`model_reported`、Prompt/Schema 版本和输入身份。Mock 仅用于确定性测试；不实现 ChatGPT API、GLM 或自动 fallback。
- `/x` 保留博主/日期筛选控件、默认值和 URL 参数。跨博主判断只在“全部博主”视图展示；单博主筛选显示范围说明，不能裁剪或重写跨博主结论。
- 普通 Reader/API 不得返回原始正文、内部 ID、任务 ID、Provider/Pompt 诊断、Cookie、浏览器 Profile、原始完整模型响应或本地 evidence 路径。
- 真实账户、X 正文、私有 Prompt、Cookie、Profile、完整模型响应和真实 fixture 不得进入 Git；生产 migration、部署和真实验收须在 Plan 完成后另获明确授权。

## 1. 目标文件与交付顺序

| Task | 交付边界 | 主要文件 |
| --- | --- | --- |
| 1 | 批次、来源快照、判断运行/版本和 RLS 的数据库事实 | 新 migration、pgTAP、生成的 DB 类型 |
| 2 | 批次结算、独立判断运行的控制面 claim/context/complete 协议 | tasks repository、Worker API、契约和 Vitest |
| 3 | Codex CLI 的跨博主 schema、Mock 与独立 Worker 执行循环 | Python runtime/structured/protocol/CLI、unittest、公开 Prompt 形状 |
| 4 | 按日期的安全 Reader 投影和博主分块 UI | reader repository、`/api/reader/x`、`XReader`、组件/路由测试 |
| 5 | 跨层回归、脱敏、文档和受控生产验收准备 | E2E、运行脚本、工程记录、状态文档 |

每个 Task 都先引入可观察的失败测试，再写最小实现，再运行聚焦验证并独立提交。仅 Task 5 的“真实生产验收”步骤需要在全部本地验证通过后再次请求用户授权。

### Task 1: 批次、来源快照与判断版本的数据库契约

**Files:**

- Create: `supabase/migrations/20260801090000_x_cross_blogger_daily_judgements.sql`
- Create: `supabase/tests/024_v2_x_cross_blogger_daily_judgements.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`
- Modify: `supabase/tests/023_v2_x_terminal_failure_scheduler.sql`

**Interfaces:**

- `x_collection_batches(id, scheduled_window_key, natural_date, cutoff_at, settlement_deadline_at, status, created_at)` is immutable apart from its lifecycle status. It is unique on `scheduled_window_key`; it only represents scheduled X windows.
- `x_collection_batch_sources(batch_id, source_id, source_display_name, x_sync_task_id, settlement_status, exclusion_code, settled_at)` freezes one enabled/resolved source per batch and maps it to one source task. `settlement_status` is `pending | included | no_new_information | excluded`.
- `sync_tasks.collection_batch_id` is nullable. It is non-null only for scheduled `x_sync` tasks and must reference a batch whose exact window key matches `capture_range.scheduled_window_key`; manual/history and all Discord tasks require null.
- `x_daily_judgement_runs(id, batch_id, status, attempt, lease_owner, lease_expires_at, available_at, failure_class, created_at, updated_at)` owns independent work. Its statuses are `queued | leased | running | succeeded | retryable_failed | failed`; one active run per batch is enforced.
- `x_daily_judgement_versions(id, batch_id, revision, coverage_status, input_snapshot, output, provider, model_reported, prompt_version, schema_version, created_at)` is append-only and unique on `(batch_id, revision)`. `coverage_status` is `complete | partial | no_new_information`; `input_snapshot` contains only source/segment/analysis/post identities and safe source names.

- [ ] **Step 1: Write failing pgTAP coverage.**

  Add tests that create two enabled resolved X sources and one scheduled cutoff. Assert one batch and two immutable source snapshots are produced; the same scheduler invocation reuses them; a newly enabled source does not join the old snapshot; and a manual/history task cannot receive `collection_batch_id`. Add assertions that a source task can be marked `included`, `no_new_information`, or `excluded`, that an excluded source yields `partial`, and that a fully no-new batch yields `no_new_information` without a judgement run.

  Add rejection tests for a batch/source mismatch, duplicate snapshot source, mutable snapshot display name, a non-X task linked to a batch, a second active judgement run, a version with non-sequential revision, an output evidence ID absent from its input snapshot, direct `UPDATE`/`DELETE` of a judgement version, and authenticated non-admin `SELECT` of all four new tables.

  ```sql
  select throws_ok(
    $$ insert into public.x_daily_judgement_versions
       (batch_id, revision, coverage_status, input_snapshot, output, provider, prompt_version, schema_version)
       values ('00000000-0000-0000-0000-000000024001', 1, 'complete',
         '{"sources":[]}'::jsonb, '{"stock_viewpoints":[]}'::jsonb,
         'codex_cli', 'v2-x-cross-blogger-1', 'v2-x-cross-blogger') $$,
    '22023', 'invalid_x_daily_judgement_evidence',
    'a judgement may not cite evidence outside its frozen input snapshot'
  );
  ```

- [ ] **Step 2: Run focused tests and confirm the new facts do not exist.**

  Run: `supabase test db`

  Expected: `024_v2_x_cross_blogger_daily_judgements.sql` fails because the batch tables/functions are absent, while all existing V2 X tests continue to pass.

- [ ] **Step 3: Implement the additive migration.**

  Add the four tables, constraints, append-only triggers and service-role-only RPCs:

  ```sql
  create function public.ensure_due_x_collection_batches(p_worker_id uuid, p_now timestamptz)
  returns jsonb;

  create function public.settle_x_collection_batch(p_batch_id uuid, p_now timestamptz)
  returns jsonb;

  create function public.claim_next_x_daily_judgement(p_worker_id uuid, p_now timestamptz)
  returns jsonb;

  create function public.complete_x_daily_judgement(
    p_run_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb
  ) returns jsonb;
  ```

  `ensure_due_x_collection_batches` must call the existing X due-window creation path inside the same transaction, freeze sources before task creation, link every created/reused scheduled X task to the matching batch, and leave manual/history tasks unlinked. `settle_x_collection_batch` must inspect each frozen task only: successful task with segments becomes `included`, successful task with `no_new_data=true` becomes `no_new_information`, and terminal/deadline failures become `excluded` with a safe classification. It inserts a queued run only when at least one source is included; otherwise it records `no_new_information` directly. Do not modify `complete_windowed_capture_range_v2_x_core` except to call settlement after its own successful atomic range/segment/coverage work has committed.

- [ ] **Step 4: Regenerate DB types and prove database behavior.**

  Regenerate `apps/control-plane/src/lib/db/types.ts` using the repository’s existing Supabase type-generation command, then run:

  ```bash
  supabase db reset
  supabase test db
  git diff --check
  ```

  Expected: the new test passes, all existing pgTAP tests stay green, and generated `Database` types include the four new tables.

- [ ] **Step 5: Commit the database boundary.**

  ```bash
  git add supabase/migrations/20260801090000_x_cross_blogger_daily_judgements.sql supabase/tests/024_v2_x_cross_blogger_daily_judgements.sql supabase/tests/023_v2_x_terminal_failure_scheduler.sql apps/control-plane/src/lib/db/types.ts
  git commit -m "feat(v2): persist X daily judgement batches"
  ```

### Task 2: 控制面判断协议与独立工作租约

**Files:**

- Create: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts`
- Create: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts`
- Create: `apps/control-plane/src/app/api/worker/x-daily-judgements/claim/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/context/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/failure/route.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/tasks.ts`
- Modify: `apps/control-plane/src/app/api/worker/schedule/tick/route.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

```ts
export type XDailyJudgementClaim = {
  run_id: string; attempt: number; lease_expires_at: string;
  batch: { id: string; natural_date: string; cutoff_at: string; coverage_status: "complete" | "partial" };
};

export type XDailyJudgementContext = {
  run_id: string; attempt: number; prompt_version: "v2-x-cross-blogger-1";
  sources: Array<{
    source_id: string; display_name: string;
    window_segments: Array<{ id: string; occurred_from_at: string; occurred_through_at: string; viewpoints: string[]; uncertainties: string[]; analyses: Array<{ post_id: string; blogger_viewpoint: string | null; arguments: string[]; quoted_post_viewpoint: string | null; uncertainties: string[]; evidence_post_ids: string[] }> }>;
  }>;
  excluded_sources: Array<{ source_id: string; display_name: string; reason: string }>;
};
```

- [ ] **Step 1: Write failing repository and route tests.**

  Mock the new RPCs. Cover a worker claim that returns only safe run/batch identity, context that contains exactly frozen included sources and their persisted segment/analysis projections, no raw `canonical_messages.content`, and a completion request with a valid version. Assert a second worker cannot claim the leased run, a stale attempt gets `409`, non-worker callers get `401`, an empty request body is rejected where required, and a malformed or out-of-batch source/analysis/evidence reference returns `422` before the completion RPC.

  ```ts
  expect(await response.json()).toEqual({
    error: "invalid_x_daily_judgement_completion",
  });
  expect(repository.completeXDailyJudgement).not.toHaveBeenCalled();
  ```

- [ ] **Step 2: Run focused failures.**

  Run: `cd apps/control-plane && npm test -- --run src/lib/db/repositories/x-daily-judgements.test.ts src/app/api/api.integration.test.ts`

  Expected: FAIL because the repository and `/api/worker/x-daily-judgements/*` routes do not exist.

- [ ] **Step 3: Implement safe repository wrappers and Worker-only routes.**

  `scheduleDueSourceTasks` must invoke batch creation/settlement after its existing Discord/X enqueue outcomes, but preserve the current rule that one source-family scheduler failure does not prevent the other from scheduling. The claim route authenticates the existing enrolled Worker, calls `claimNextXDailyJudgement`, and returns `204` when none is ready. The context route verifies the run lease owner and attempt before reading the reader-unsafe but non-raw model input. The complete route validates the exact JSON shape below, then calls the atomic completion RPC; it must never accept local evidence paths or raw output.

  ```ts
  type Completion = {
    run_id: string; attempt: number; schema_version: "v2-x-cross-blogger";
    provider: "codex_cli"; model_reported: string | null;
    prompt_version: "v2-x-cross-blogger-1";
    stock_viewpoints: JudgementItem[];
    market_industry_viewpoints: JudgementItem[];
    uncertainties: string[];
  };
  type JudgementItem = {
    statement: string; supporting_source_ids: string[]; dissenting_source_ids: string[];
    analysis_ids: string[]; evidence_post_ids: string[]; uncertainties: string[];
  };
  ```

  Failure reporting accepts only `timeout | provider_failure | empty_response | invalid_json | schema_error | persistence_failure`, increments retry state without mutating the batch or source task, and becomes terminal only after the existing bounded retry policy is exhausted.

- [ ] **Step 4: Run focused control-plane verification.**

  Run:

  ```bash
  cd apps/control-plane && npm test -- --run src/lib/db/repositories/x-daily-judgements.test.ts src/app/api/api.integration.test.ts
  npm run lint
  ```

  Expected: all new claim/context/complete/failure cases pass; no existing schedule tick behavior regresses.

- [ ] **Step 5: Commit the protocol boundary.**

  ```bash
  git add apps/control-plane/src/lib/db/repositories/tasks.ts apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts apps/control-plane/src/app/api/worker/schedule/tick/route.ts apps/control-plane/src/app/api/worker/x-daily-judgements apps/control-plane/src/app/api/api.integration.test.ts
  git commit -m "feat(v2): add X daily judgement worker protocol"
  ```

### Task 3: 跨博主判断 Schema、Provider 与本机 Worker 执行

**Files:**

- Create: `workers/v0/prompts/v2_x_cross_blogger.md`
- Create: `workers/v0/tests/test_x_cross_blogger_judgements.py`
- Modify: `workers/v0/src/invest_hub_worker/structured.py`
- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`
- Modify: `workers/v0/src/invest_hub_worker/cli.py`
- Modify: `workers/v0/src/invest_hub_worker/worker.py`
- Modify: `workers/v0/tests/test_protocol.py`
- Modify: `workers/v0/tests/test_worker_recovery.py`
- Modify: `workers/v0/tests/test_cli.py`

**Interfaces:**

```python
def parse_v2_x_cross_blogger_output(
    text: str,
    *, allowed_source_ids: set[str], allowed_analysis_ids: set[str], allowed_post_ids: set[str],
) -> dict[str, object]: ...

class XDailyJudgementRuntime:
    def execute(self, claim: dict[str, object], context: dict[str, object]) -> dict[str, object]: ...
```

The Prompt must request one JSON object with `schema_version`, `stock_viewpoints`, `market_industry_viewpoints`, and `uncertainties`. Each item follows the TypeScript `JudgementItem` shape in Task 2. The runtime uses the existing Codex CLI Provider, passes only Task 2’s context, and returns the validated completion payload plus safe Provider telemetry.

- [ ] **Step 1: Write strict-schema and Worker-loop failures.**

  Create public artificial fixtures covering agreement by two distinct bloggers, disagreement by a third blogger, one source with no new information, one excluded source, and no input viewpoints. Reject a model result that adds a third theme, names a source not in the claim, cites an unknown analysis/post, uses a source twice as both supporting and dissenting, duplicates an evidence ID, has an empty evidence list, turns an excluded source into support, or returns an imperative system investment recommendation.

  Add Worker tests proving: after an X range task completes, a subsequent `run-scheduled` loop claims and completes one ready judgement; a Codex failure reports only the judgement run as retryable; failure does not call a source-task failure endpoint or alter source coverage; and no ready judgement returns `no_task` without invoking Codex CLI.

  ```python
  with self.assertRaisesRegex(SchemaError, "unknown evidence post"):
      parse_v2_x_cross_blogger_output(
          json.dumps(invalid_output),
          allowed_source_ids={"source-a", "source-b"},
          allowed_analysis_ids={"analysis-a"},
          allowed_post_ids={"post-a"},
      )
  ```

- [ ] **Step 2: Run focused failures.**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_cross_blogger_judgements.py workers/v0/tests/test_protocol.py workers/v0/tests/test_worker_recovery.py workers/v0/tests/test_cli.py -v`

  Expected: FAIL because cross-blogger parsing, protocol methods and scheduled-runner handling are absent.

- [ ] **Step 3: Implement the minimal local-only judgement runtime.**

  Add `WorkerProtocol.claim_x_daily_judgement`, `get_x_daily_judgement_context`, `complete_x_daily_judgement`, and `fail_x_daily_judgement`, each validates only the Task 2 safe shapes and calls the new Worker endpoints. `XDailyJudgementRuntime` reads the public JSON-boundary Prompt plus the local private supplement, invokes `CodexCLIProvider`, parses/validates the response, and never writes model input/output to the cloud beyond the validated completion fields. Raw model response and diagnostics remain in the existing owner-only evidence directory.

  Extend `run-scheduled` so its existing schedule tick and source-task loop remain unchanged; after no X source task remains claimable, it repeatedly claims at most one ready judgement run per invocation. It must heartbeat as the existing X-capable Worker, use a bounded lease, and report the five permitted judgement failure classes through the independent endpoint. Do not add a new browser operation, OpenCLI call, source-specific runtime or dependency.

- [ ] **Step 4: Run focused and X regression verification.**

  Run:

  ```bash
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_cross_blogger_judgements.py workers/v0/tests/test_x_structured_output.py workers/v0/tests/test_x_summaries.py workers/v0/tests/test_x_windowed_runtime.py workers/v0/tests/test_protocol.py workers/v0/tests/test_worker_recovery.py workers/v0/tests/test_cli.py -v
  ```

  Expected: new judgement paths pass; existing per-post/window X behavior and source failure isolation remain unchanged.

- [ ] **Step 5: Commit the Worker boundary.**

  ```bash
  git add workers/v0/prompts/v2_x_cross_blogger.md workers/v0/src/invest_hub_worker/structured.py workers/v0/src/invest_hub_worker/runtime.py workers/v0/src/invest_hub_worker/protocol.py workers/v0/src/invest_hub_worker/cli.py workers/v0/src/invest_hub_worker/worker.py workers/v0/tests/test_x_cross_blogger_judgements.py workers/v0/tests/test_protocol.py workers/v0/tests/test_worker_recovery.py workers/v0/tests/test_cli.py
  git commit -m "feat(v2): generate X cross-blogger judgements"
  ```

### Task 4: 日期优先的安全 Reader 与博主分块

**Files:**

- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Modify: `apps/control-plane/src/app/api/reader/x/route.ts`
- Modify: `apps/control-plane/src/app/x/page.tsx`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx`
- Modify: `apps/control-plane/src/app/x/page.test.tsx`
- Modify: `apps/control-plane/src/app/globals.css`

**Interfaces:**

```ts
export type XReaderDate = {
  naturalDate: string;
  judgement: {
    visible: boolean;
    batches: Array<{
      cutoffAt: string; coverageStatus: "complete" | "partial" | "no_new_information";
      status: "succeeded" | "judgement_pending" | "judgement_failed";
      revision: number; stockViewpoints: ReaderJudgement[];
      marketIndustryViewpoints: ReaderJudgement[]; uncertainties: string[];
      excludedSourceCount: number;
    }>;
  };
  bloggers: XReaderBlogger[];
};
```

`ReaderJudgement` contains only `statement`, visible supporting/dissenting display names, and `uncertainties`; it intentionally omits internal evidence identities. `XReaderBlogger` retains the existing safe source/date/status/segment data, but segments are ordered newest-first within its date block.

- [ ] **Step 1: Write failing Reader tests.**

  Add repository tests for two dates/two bloggers/three batch cutoffs. Assert dates are descending; the `20:00` judgement precedes `16:00`; its latest revision is returned; `partial` exposes a count rather than an excluded source identifier; `no_new_information`, pending and failed states are distinguishable; and neither API JSON nor rendered HTML contains `analysis_ids`, `evidence_post_ids`, task IDs, raw post text, provider telemetry or local path fragments.

  Add component tests verifying the exact visual order `日期 → 当日判断总结 → 单个博主观点`; the newest judgement is expanded and older ones are collapsed; blogger blocks are one-column stable sections rather than a multi-column grid; within each block its newest successful segment appears before earlier collapsed segments; and the existing date/source selectors still set the same URL values. With a specific `source` query, assert the cross-blogger section renders only the range explanation and never a narrowed judgement item.

  ```tsx
  expect(screen.getByRole("heading", { name: "当日判断总结" })).toBeBefore(
    screen.getByRole("heading", { name: "单个博主观点" }),
  );
  expect(screen.getByText("跨博主当日判断总结仅在全部博主视图展示。")).toBeVisible();
  ```

- [ ] **Step 2: Run focused failures.**

  Run: `cd apps/control-plane && npm test -- --run src/components/reader/x-reader.test.tsx src/app/x/page.test.tsx src/lib/db/repositories/reader-source-navigation.test.ts src/app/api/api.integration.test.ts`

  Expected: FAIL because `readXDay` returns source-first cards and no judgement projection exists.

- [ ] **Step 3: Implement the safe date projection and content-first rendering.**

  Replace the X-only `readXDay` return type with `XReaderDate[]`, grouping existing `x_daily_viewpoint_segments` under each date and joining the current judgement version by batch cutoff. Query only safe display fields and map internal evidence IDs to display names server-side; do not send evidence identities to the component. Source filtering continues to filter blogger blocks and dates. For `source=all`, include judgement batches; for a specific source, set `judgement.visible=false` and return the fixed explanation copy.

  Update `XReader` to render a date card first, then the judgement list, then blogger blocks. Use `<details open>` for the newest completed judgement/segment and closed `<details>` for older history; a pending/failed judgement uses `ReaderStatus`-style explicit text and has no fabricated topic body. Preserve current empty state, auth gate, filter option construction, accessible labels and 375px single-column layout. Remove only the X reader’s current `groupedBySource` / two-column card projection; do not alter Discord Reader behavior.

- [ ] **Step 4: Run frontend verification.**

  Run:

  ```bash
  cd apps/control-plane && npm test -- --run src/components/reader/x-reader.test.tsx src/app/x/page.test.tsx src/lib/db/repositories/reader-source-navigation.test.ts src/app/api/api.integration.test.ts
  npm run lint
  npm run build
  ```

  Expected: Reader tests, lint and production build pass without raw-content/API leakage.

- [ ] **Step 5: Commit Reader changes.**

  ```bash
  git add apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts apps/control-plane/src/app/api/reader/x/route.ts apps/control-plane/src/app/x/page.tsx apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/components/reader/x-reader.test.tsx apps/control-plane/src/app/x/page.test.tsx apps/control-plane/src/app/globals.css
  git commit -m "feat(v2): display X daily judgements by date"
  ```

### Task 5: 跨层验收、回滚准备与受控生产门禁

**Files:**

- Create: `tests/e2e/v2/test_x_cross_blogger_daily_judgements.py`
- Modify: `scripts/v2/run-v2-e2e.sh`
- Create: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`
- Modify: `docs/project-status.md`

**Interfaces:**

- The public E2E fixture contains only synthetic source names, posts and model outputs. It drives two sources through one `complete` batch, a `partial` batch and a `no_new_information` batch, then reads the same safe `/api/reader/x` projection used by the page.
- Rollback is additive: disable new judgement scheduling/claiming and Reader projection first, retain immutable batches/runs/versions, and never delete/alter existing X source tasks, coverage, segments, analyses or checkpoint state.

- [ ] **Step 1: Write failing cross-layer cases.**

  Cover two sources agreeing on a stock, a third dissenting, a source failure that yields a partial judgement but advances only healthy-source coverage, a source with no new data, a Provider retry that later produces revision 1, an explicit administrator regeneration that later produces revision 2, duplicate schedule ticks, stale completion rejection, date ordering, single-source filter explanation, ordinary-user safe JSON, and a 375px Reader layout assertion. Ensure fixture output includes a forbidden raw-content sentinel and assert it is absent from JSON/HTML.

- [ ] **Step 2: Run the new E2E test before its implementation is complete.**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest tests/e2e/v2/test_x_cross_blogger_daily_judgements.py -v`

  Expected: FAIL until Tasks 1–4 deliver the batch, Worker and Reader contracts.

- [ ] **Step 3: Implement the fixture runner and complete deterministic verification.**

  Extend `scripts/v2/run-v2-e2e.sh` to run the new test without reading a browser profile or local private Prompt. Then run:

  ```bash
  supabase db reset
  supabase test db
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s tests/e2e/v2 -p 'test_*.py' -v
  cd apps/control-plane && npm test && npm run lint && npm run build
  cd ../.. && bash scripts/v2/run-v2-e2e.sh && bash scripts/v0/redact-check.sh
  git diff --check
  git status --short
  ```

  Expected: every deterministic suite passes. Record actual command outcomes and aggregate counts only; do not claim any real X or Provider result from fixtures.

- [ ] **Step 4: Prepare the authorized production checklist without executing it.**

  The engineering journal must list: target Supabase project/ref, exact additive migration filename, rollback switch, X Worker service name, one normal batch, one partial batch, one no-new batch, a judgement retry/revision observation, an authenticated `/x` desktop/375px check and a redacted database-read verification. Do not apply migration, restart Worker, invoke real X, call Codex CLI against real content or deploy until the user explicitly authorizes those exact actions.

- [ ] **Step 5: Commit deterministic evidence and request production authorization separately.**

  ```bash
  git add tests/e2e/v2/test_x_cross_blogger_daily_judgements.py scripts/v2/run-v2-e2e.sh docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md docs/project-status.md
  git commit -m "test(v2): verify X daily judgement summaries"
  ```

  After the commit, present deterministic outcomes and ask separately for authorization before any remote migration, deployment, Worker restart or real-content model invocation.

## Plan self-review

Spec coverage is complete: Tasks 1–2 establish one frozen batch per cutoff, settlement states, independent retries and immutable versions; Task 3 validates the exact two-theme Codex output without source/checkpoint coupling; Task 4 implements the confirmed date-first/summary-first/blogger-block UX and filter semantics; Task 5 covers failure isolation, revision history, safe projection, responsive reading, redaction and the separate real-production gate. Names introduced in each task are defined before later use. The plan contains no placeholder work and adds no new dependency or alternate collector/provider.
