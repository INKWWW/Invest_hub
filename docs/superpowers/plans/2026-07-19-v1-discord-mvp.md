# V1 Discord 正式可用 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Plan status:** 执行中（用户确认 Inline Execution，2026-07-19）；Task 1–3 已完成。

**Goal:** 在已验证的 V0 控制面与本地 Worker 边界上，交付可供管理员与受邀普通用户日常阅读的 Discord MVP。

**Architecture:** 保留 Next.js/Supabase 控制面与 Python Worker。V1 为来源绑定、规则快照、有限历史补采、批次/日累计摘要版本和普通用户阅读查询增加最小持久化模型；Worker 继续通过 OpenCLI Browser Bridge + Active Adapter 在本地采集，云端只接收允许持久化的事实、结构化结果、摘要与证据关系。摘要与 checkpoint 必须在同一持久化闭环内确认，任何失败都不能将未确认范围显示为成功。

**Tech Stack:** Next.js 16 + TypeScript、Supabase Auth/Postgres/RLS/pgTAP、Python 3.11+ 标准库 Worker、OpenCLI Browser Bridge + Active Adapter、Codex CLI/Mock Provider、Vitest、Python `unittest`。

## Global Constraints

- 只处理 Discord；不实现 X、跨频道聚合、媒体/OCR/外部文章解析、GLM 或自动 Provider fallback。
- Chrome Profile、Cookie、Token、真实 Discord URL、私有 Prompt、完整模型响应和本地 evidence 只留在 owner-only 本地目录，不进入 Git、Vercel、任务 payload、云端调试页或普通日志。
- 继续使用 Active Adapter；不新建第二套 Playwright/CDP 或直接 Discord REST API 采集器，也不自动化普通用户 Token。
- 每个来源独立 checkpoint、任务队列与失败状态。只有 raw、Canonical、结构化、批次/日摘要和证据全部持久化并获控制面确认后，才推进 checkpoint。
- 真实 Provider 初始参数固定为 `chunk_size=100`、最大并发 5、单请求 240 秒、最多 3 次尝试；Provider 失败只进入分类失败和局部重试，不切换 Provider。
- V1 常规同步每任务最多 5 页；管理员历史补采必须显式指定 `max_pages`（1–25）。每页仍有 90 秒 Browser Bridge 截止，超时或 stale/missing response 不是空数据成功。
- 定时窗口固定为 `08:00` 和 `20:50` Asia/Shanghai；补采依据最后安全 checkpoint，不依赖机器在窗口时刻在线。
- 每个任务按测试先行执行；只提交人工构造公开 fixture。每个任务完成后更新其勾选状态并做独立提交。

---

## File Structure

| 路径 | 责任 |
| --- | --- |
| `supabase/migrations/003_v1_discord_mvp.sql` | 来源授权、规则快照、任务范围、批次/日累计摘要版本、RLS 和原子持久化函数扩展。 |
| `supabase/tests/003_v1_discord_mvp.sql` | pgTAP：权限、规则快照、摘要/证据原子性、来源隔离与幂等。 |
| `supabase/migrations/004_v1_rule_tasks.sql` | 规则集版本与管理员驱动的原子规则替换、任务快照创建函数。 |
| `supabase/tests/004_v1_rule_tasks.sql` | pgTAP：规则优先级、版本递增、任务快照和函数权限。 |
| `contracts/v0/task-claim.schema.json` | 在既有 Worker 协议中加入不可变的 `rule_snapshot` 与有界 `collection_scope`。 |
| `contracts/v0/worker-persistence.schema.json` | 在既有持久化 payload 中加入批次摘要及其证据范围。 |
| `apps/control-plane/src/lib/db/repositories/{sources,rules,summaries,tasks}.ts` | 管理来源/规则、生成任务快照和安全阅读模型查询。 |
| `apps/control-plane/src/app/api/{admin,reader,worker}/...` | 管理员配置、普通用户只读阅读 API、Worker 定时窗口 API。 |
| `apps/control-plane/src/app/discord/page.tsx` 与 `src/components/reader/*` | 正式 Discord 阅读页，桌面/手机均可使用。 |
| `workers/v0/src/invest_hub_worker/{config,scheduler,summaries,runtime}.py` | 多来源 owner-only 配置、定时补采、摘要构建和带规则/范围的运行时。 |
| `workers/v0/src/invest_hub_worker/connectors/discord_active_adapter.py` | 遵守任务页上限的有限分页；保留 freshness 与错误分类。 |
| `workers/v0/tests/test_{config,scheduler,summaries,discord_active_adapter,authorized_runtime}.py` | Worker 的多来源、有限分页、规则归因、摘要与恢复测试。 |
| `apps/control-plane/src/app/{api,discord}/**/*.test.ts*`、`tests/e2e/v1/*` | API/UI、权限、数据查询和端到端验收。 |
| `scripts/v1/run-e2e.sh` | 明确区分 deterministic 与显式授权的 real-discord 验收入口。 |
| `docs/engineering-journal/2026-07-19-v1.md`、`docs/spikes/2026-07-19-v1-decision-report.md` | 只记录脱敏证据、结论、限制和 V2/V3 门禁。 |

## Task 1: 扩展数据库模型与原子持久化边界

**Files:**

- Create: `supabase/migrations/003_v1_discord_mvp.sql`
- Create: `supabase/tests/003_v1_discord_mvp.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`
- Modify: `apps/control-plane/src/lib/contracts.ts`
- Test: `apps/control-plane/src/lib/contracts.test.ts`

**Interfaces:**

- `sources.authorized_worker_id uuid nullable`：未绑定时任何已注册 Worker 可领取；绑定后只允许该 Worker 领取。
- `source_author_rules(id, author_id, scope, source_id, policy, enabled, version, created_by)`：`scope in ('global','source')`，全局规则的 `source_id is null`，来源规则必须有 `source_id`；`policy in ('target','exclude')`。
- `sync_tasks.rule_snapshot jsonb` 和 `sync_tasks.collection_scope jsonb`：创建任务时固化，分别为 `{"version": integer, "target_author_ids": string[]}` 与 `{"mode":"incremental"|"history", "max_pages":1..25}`。
- `summary_batches(task_id, natural_date, source_id, input_message_ids, structured_run_ids, output, coverage, created_at)`：`unique(task_id,natural_date)`。
- `daily_summaries(source_id, natural_date, version, is_current, batch_ids, output, coverage, created_at)`：`unique(source_id,natural_date,version)`，同一来源/日期最多一条 `is_current=true`。

- [x] **Step 1: 写 pgTAP 失败断言与契约测试**

  在 `003_v1_discord_mvp.sql` 的对应测试中写入：未授权 Worker 无法领取绑定来源；创建任务后再修改规则不会改变其 `rule_snapshot`；伪造不存在 Structured Run、跨来源消息 ID 或未匹配日期的 batch summary 被拒绝；相同任务/日期重复 persist 不生成第二个 batch 或 daily version；普通用户不能读取规则、任务、Worker、raw local ref 或管理诊断。

  在 `contracts.test.ts` 添加最小合法 claim 和 persistence 样例；断言 `collection_scope.max_pages=0`、未知 scope、重复 `target_author_ids`、空 `input_message_ids` 和跨字段缺失均被拒绝。

- [x] **Step 2: 运行失败测试**

  Run: `supabase test db supabase/tests/003_v1_discord_mvp.sql`

  Expected: FAIL，因为迁移、摘要表和 V1 字段尚不存在。

  Run: `cd apps/control-plane && npm test -- --run src/lib/contracts.test.ts`

  Expected: FAIL，因为现有 JSON Schema 不接受新的规则快照、任务范围与 batch summaries。

- [x] **Step 3: 实现迁移和校验函数**

  在 `003_v1_discord_mvp.sql` 中：

  1. 对 `sources`、`sync_tasks` 添加上述列和 JSON shape check；创建规则、batch、daily 表及 `(source_id,natural_date,is_current)` 的 partial unique index。
  2. 将 `claim_next_task` 的来源筛选收紧为 `s.authorized_worker_id is null or s.authorized_worker_id = p_worker_id`，并将 `rule_snapshot` 和 `collection_scope` 原样放入 claim。
  3. 扩展 `persist_worker_execution`：先验证 batch 的输入 Canonical ID、Structured Run ID 与其来源/任务、UTC `natural_date`；同一事务写入 `summary_batches`，把旧 current daily 标为 false，再写入递增 `version` 的 current daily。任何校验失败回滚 raw、Canonical、Structured、summary 和 receipt。
  4. 为 `summary_batches`、`daily_summaries` 启用 RLS。普通 `authenticated` 只可 select 安全阅读列所依赖的内容；规则、任务、Worker、checkpoint 和 local raw refs 仍只限管理员/服务角色。
  5. 更新 `Database` 的行、Insert、Update 和 Function 类型；`parseContract` 继续加载 `contracts/v0`，但对扩展字段进行严格验证。

- [x] **Step 4: 验证数据库和契约**

  Run: `supabase db reset && supabase test db`

  Expected: 001–003 的所有 pgTAP 断言通过，且新策略证明普通用户无法读取管理数据。

  Run: `cd apps/control-plane && npm test -- --run src/lib/contracts.test.ts src/lib/deployment-contract.test.ts`

  Expected: PASS；部署包仍包含所需 V0 契约，扩展 payload 没有放宽未知字段。

- [x] **Step 5: Commit**

  ```bash
  git add supabase/migrations/003_v1_discord_mvp.sql supabase/tests/003_v1_discord_mvp.sql contracts/v0 apps/control-plane/src/lib/db/types.ts apps/control-plane/src/lib/contracts.ts apps/control-plane/src/lib/contracts.test.ts
  git commit -m "feat(v1): add discord summary and rule persistence"
  ```

## Task 2: 实现来源授权、规则快照与有界任务创建

**Files:**

- Create: `apps/control-plane/src/lib/db/repositories/rules.ts`
- Create: `supabase/migrations/004_v1_rule_tasks.sql`
- Create: `supabase/tests/004_v1_rule_tasks.sql`
- Modify: `apps/control-plane/src/lib/db/repositories/sources.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/tasks.ts`
- Create: `apps/control-plane/src/app/api/admin/rules/route.ts`
- Modify: `apps/control-plane/src/app/api/admin/sources/route.ts`
- Modify: `apps/control-plane/src/app/api/admin/tasks/route.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`
- Test: `apps/control-plane/src/lib/db/repositories/rules.test.ts`
- Test: `apps/control-plane/src/lib/db/repositories/sources.test.ts`

**Interfaces:**

- `replaceSourceRules(input: { sourceId: string; globalTargetAuthorIds: string[]; sourceTargetAuthorIds: string[]; sourceExcludedAuthorIds: string[]; actorId: string }): Promise<{ version: number; targetAuthorIds: string[] }>`：来源排除优先于全局/来源 target，返回已去重且排序的有效 target 集合。
- `createDiscordSyncTask(input: { sourceId: string; parameterVersion: string; requestedBy: string; scope: { mode: "incremental" | "history"; maxPages: number } })`：在单事务内读取当前规则、写 `rule_snapshot` 和 `collection_scope` 后入队。
- `PATCH /api/admin/sources`：只接受 `source_id`、`enabled`、`authorized_worker_id|null`；不得接受 URL、Profile、Cookie 或 Prompt。

- [x] **Step 1: 写失败测试**

  为 `rules.test.ts` 写入全局 target、来源 target 和来源 exclude 的组合，断言 exclude 胜出、输入去重/排序且 version 递增。为 API 集成测试加入：普通用户对 rules、source binding 和 history task 返回 403；`max_pages` 不在 1–25 返回 422；任务记录的快照不随随后规则更新改变。

- [x] **Step 2: 运行失败测试**

  Run: `cd apps/control-plane && npm test -- --run src/lib/db/repositories/rules.test.ts src/app/api/api.integration.test.ts`

  Expected: FAIL，因为 repository、规则路由和有界 scope 验证尚未存在。

- [x] **Step 3: 实现最小管理接口**

  1. `rules.ts` 只用 service-role repository 写入规则，读取时永不返回 `created_by` 之外的认证信息；写入后计算并返回快照。
  2. `sources.ts` 扩展 list/upsert/update，返回授权 Worker 的显示安全字段；拒绝不存在或 revoked Worker 的 binding。
  3. `tasks.ts` 在创建任务时调用 rules snapshot 函数，把 `scope`、`rule_snapshot` 与来源 parameter version 一起写入，默认增量 scope 为 `{mode:'incremental',maxPages:5}`。
  4. 管理 API 只在 `requireRole('admin')` 成功后调用上述 repository。history 请求必须显式传 `{mode:'history',max_pages}`；不得有“无限历史”开关。

- [x] **Step 4: 验证 API 行为**

  Run: `cd apps/control-plane && npm test -- --run src/lib/db/repositories/rules.test.ts src/app/api/api.integration.test.ts`

  Expected: PASS；所有管理变更由管理员执行，任务带有不可变的规则/范围快照。

- [x] **Step 5: Commit**

  ```bash
  git add apps/control-plane/src/lib/db/repositories/rules.ts apps/control-plane/src/lib/db/repositories/sources.ts apps/control-plane/src/lib/db/repositories/tasks.ts apps/control-plane/src/app/api/admin apps/control-plane/src/app/api/api.integration.test.ts apps/control-plane/src/lib/db/repositories/rules.test.ts
  git commit -m "feat(v1): add source rules and bounded task scopes"
  ```

## Task 3: 让 Worker 支持多来源、规则归因与有限分页

**Files:**

- Modify: `workers/v0/src/invest_hub_worker/config.py`
- Create: `workers/v0/src/invest_hub_worker/scheduler.py`
- Modify: `workers/v0/src/invest_hub_worker/cli.py`
- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Modify: `workers/v0/src/invest_hub_worker/connectors/discord_active_adapter.py`
- Modify: `workers/v0/tests/test_config.py`
- Create: `workers/v0/tests/test_scheduler.py`
- Modify: `workers/v0/tests/test_discord_active_adapter.py`
- Modify: `workers/v0/tests/test_authorized_runtime.py`

**Interfaces:**

- `LocalWorkerConfigSet.load(path: Path) -> LocalWorkerConfigSet`：owner-only 文件，含一个 `control_plane_url` 与 `sources: tuple[LocalSourceConfig,...]`；每个 source 含 `source_id`、`channel_url`、`profile_ref`、`opencli_contract_version`、`parameter_version`，source ID 必须唯一。
- `TaskScope.from_claim(claim: Mapping[str, Any]) -> TaskScope`：只接受 `incremental|history` 和 `1 <= max_pages <= 25`。
- `DiscordActiveAdapter.collect(source, checkpoint, *, max_pages: int) -> Iterable[RawPage]`：最多请求 `max_pages` 个通过 freshness 验证的页面；任一错误立即抛出原有分类。
- `should_enqueue(now_utc: datetime, last_seen_window: str | None) -> str | None`：返回一次性的 `YYYY-MM-DDT08:00+08:00` 或 `...20:50+08:00` 窗口 key，不重复触发。

- [x] **Step 1: 写失败测试**

  `test_config.py` 添加两个不同 source 的合法 owner-only config、重复 source ID、宽权限和遗留单来源配置迁移失败样例。`test_discord_active_adapter.py` 添加三页 fresh response：`max_pages=2` 只请求两页并保留第二页 cursor；`max_pages=1` 复现 V0 单页边界；第二页 stale 时仍抛 `opencli_stale`，不返回部分成功。

  `test_authorized_runtime.py` 断言 claim 的 `rule_snapshot.target_author_ids` 被传给 `ProviderContext.target_author_ids`，而规则快照与 scope 缺失会作为 `preflight` 失败。`test_scheduler.py` 断言两个窗口各触发一次、离线跨过窗口后不会伪造空成功而是创建一次补采 tick。

- [x] **Step 2: 运行失败测试**

  Run: `PYTHONPATH=workers/v0/src python3.11 -m unittest workers/v0/tests/test_config.py workers/v0/tests/test_scheduler.py workers/v0/tests/test_discord_active_adapter.py workers/v0/tests/test_authorized_runtime.py -v`

  Expected: FAIL，因为当前 Worker 只接受一个来源且 Adapter 无 `max_pages`。

- [x] **Step 3: 实现多来源运行与有限分页**

  1. 用 `LocalWorkerConfigSet` 替换运行器入口的单来源选择逻辑，但保留 `LocalWorkerConfig.redacted()` 只输出 source ID 和版本，不输出 URL/Profile。
  2. `Worker.run_once()` 在 claim 后按 `source_id` 查找本地 source；未授权 source、版本不符或 scope 非法时调用既有 failure route，`safe_checkpoint` 不变。
  3. Adapter 以 `for page_index in range(max_pages)` 驱动分页。每页保留现有 90 秒 deadline、request URL 匹配、freshness 与 cursor 验证；达到上限后返回最后已验证页面，不再请求下一页。
  4. 在 runtime 构造 `ProviderContext` 时传入冻结的 target author ID 集合；不从云端读取真实 URL、Profile 或 Prompt。

- [x] **Step 4: 验证 Worker 回归**

  Run: `PYTHONPATH=workers/v0/src:spikes python3.11 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v`

  Expected: PASS；单来源 V0 回归继续通过，多来源选择、scope 上限、规则归因和 stale 失败新增通过。

- [x] **Step 5: Commit**

  ```bash
  git add workers/v0/src/invest_hub_worker workers/v0/tests
  git commit -m "feat(v1): support bounded multi-source discord collection"
  ```

## Task 4: 构建批次/日累计摘要并纳入 checkpoint 闭环

**Files:**

- Create: `workers/v0/src/invest_hub_worker/summaries.py`
- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`
- Modify: `contracts/v0/worker-persistence.schema.json`
- Modify: `apps/control-plane/src/app/api/worker/tasks/[taskId]/persist/route.ts`
- Modify: `apps/control-plane/src/app/api/worker/tasks/[taskId]/result/route.ts`
- Create: `workers/v0/tests/test_summaries.py`
- Modify: `workers/v0/tests/test_authorized_runtime.py`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

- `build_batch_summaries(messages: Sequence[CanonicalMessage], runs: Sequence[StructuredRunPayload]) -> list[BatchSummaryPayload]`：按 `occurred_at` 的 UTC natural day 分组；每个 payload 含非空 `input_message_ids`、对应 `structured_run_keys`、`output`、`coverage` 和 `natural_date`。
- `build_daily_summary(existing: Sequence[BatchSummaryPayload], incoming: BatchSummaryPayload) -> DailySummaryPayload`：按日、来源、证据 ID 去重，输出仅由 batch outputs 与 coverage 构成，不读取 raw local ref。
- Worker persistence payload 新增 `batch_summaries`，result 新增 `summary_batch_ids` 与 `daily_summary_ids`；控制面只在 returned receipt 的摘要 ID 与 result 一致时接受成功。

- [ ] **Step 1: 写失败测试**

  `test_summaries.py` 覆盖同一天两个 chunk、跨天消息、重复 Canonical ID、target/topic/channel 三种 author scope、unparsed media warning 和没有有效消息的拒绝。API 集成测试断言：持久化返回的 summary IDs 不匹配 result、batch 引用别的 task 的 run、daily output 引用不存在 message 时均返回 422/不推进 checkpoint。

- [ ] **Step 2: 运行失败测试**

  Run: `PYTHONPATH=workers/v0/src python3.11 -m unittest workers/v0/tests/test_summaries.py workers/v0/tests/test_authorized_runtime.py -v`

  Expected: FAIL，因为摘要构建器和 persistence 字段尚不存在。

- [ ] **Step 3: 实现摘要构建与持久化顺序**

  1. `summaries.py` 只把已通过 `validate_structured_output` 的 topics、warnings、media 标记和证据 ID 组成摘要；不得重新解释原始文本或解析媒体。
  2. runtime 先完成每 chunk 的结构化验证，再生成按自然日 batch summaries；将 batch payload 与结构化运行一起交给 persistence。
  3. persist route 对扩展 schema 做严格校验，并把数据库返回的 batch/daily IDs 放入 receipt；result route 比对这些 IDs 后才调用 `accept_task_result`。
  4. 保持所有摘要版本 append-only。重复 persist 返回同一 receipt，不能生成新的 daily version；新的成功任务才生成递增版本并替换 current 指针。

- [ ] **Step 4: 验证摘要与 checkpoint**

  Run: `PYTHONPATH=workers/v0/src python3.11 -m unittest workers/v0/tests/test_summaries.py workers/v0/tests/test_authorized_runtime.py workers/v0/tests/test_checkpoint_order.py -v`

  Expected: PASS；摘要证据错误或 receipt 不一致都会保留旧 checkpoint。

  Run: `cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts`

  Expected: PASS；Worker API 拒绝非法摘要 payload 并接受完整原子闭环。

- [ ] **Step 5: Commit**

  ```bash
  git add workers/v0/src/invest_hub_worker/summaries.py workers/v0/src/invest_hub_worker/runtime.py workers/v0/src/invest_hub_worker/protocol.py workers/v0/tests contracts/v0/worker-persistence.schema.json apps/control-plane/src/app/api/worker apps/control-plane/src/app/api/api.integration.test.ts
  git commit -m "feat(v1): persist evidence-backed discord summaries"
  ```

## Task 5: 交付管理员多来源配置与任务控制页面

**Files:**

- Modify: `apps/control-plane/src/app/admin/sources/page.tsx`
- Modify: `apps/control-plane/src/components/admin/SourceCreateForm.tsx`
- Create: `apps/control-plane/src/components/admin/SourceRuleForm.tsx`
- Modify: `apps/control-plane/src/app/admin/tasks/page.tsx`
- Modify: `apps/control-plane/src/components/admin/TaskCreateForm.tsx`
- Modify: `apps/control-plane/src/app/admin/admin-ui.test.tsx`
- Create: `apps/control-plane/src/components/admin/source-rule-form.test.tsx`

**Interfaces:**

- `SourceRuleForm` 仅提交 author ID、global/source scope 和 `target|exclude` policy；不提交 Discord URL、Profile、Cookie、Prompt 或正文。
- `TaskCreateForm` 的增量任务隐藏上限并提交默认 5；历史任务必须显式选择 1–25 页，提交前显示“有界补采”提示。
- 来源表展示 enable 状态、授权 Worker、当前规则版本和安全 checkpoint 的安全摘要，不展示任务原始 payload。

- [ ] **Step 1: 写组件失败测试**

  为 SourceRuleForm 断言空 author ID、target/exclude 冲突和非管理员 API 错误会在页面显示可理解错误；断言 DOM 中没有 `channel_url`、`profile_ref`、`cookie` 或 `prompt` 输入。为 TaskCreateForm 断言 history 未选页数不能提交、`26` 被拒绝、增量提交固定为 `max_pages:5`。

- [ ] **Step 2: 运行失败测试**

  Run: `cd apps/control-plane && npm test -- --run src/components/admin/source-rule-form.test.tsx src/app/admin/admin-ui.test.tsx`

  Expected: FAIL，因为规则编辑器、worker binding 和 history scope UI 尚不存在。

- [ ] **Step 3: 实现最小管理体验**

  1. 来源页从安全 repository 读取 workers、规则摘要和 checkpoint 摘要；允许管理员启停、绑定已激活 Worker。
  2. 规则表单将 global target、source target、source exclude 分开显示，并在提交成功后刷新版本号；不渲染任何私密配置字段。
  3. 任务页将手动增量和有界 history 明确分开。history 只创建一项带 scope 的任务，失败后使用现有 retry 流程，不新建隐式无限任务。

- [ ] **Step 4: 验证 UI 与构建**

  Run: `cd apps/control-plane && npm test -- --run src/components/admin/source-rule-form.test.tsx src/app/admin/admin-ui.test.tsx && npm run lint && npm run build`

  Expected: PASS；页面可构建，管理员操作不要求或泄露本地浏览器信息。

- [ ] **Step 5: Commit**

  ```bash
  git add apps/control-plane/src/app/admin apps/control-plane/src/components/admin
  git commit -m "feat(v1): manage discord sources rules and bounded backfill"
  ```

## Task 6: 交付普通用户 Discord 阅读页与只读查询边界

**Files:**

- Create: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Create: `apps/control-plane/src/app/api/reader/discord/route.ts`
- Create: `apps/control-plane/src/app/discord/page.tsx`
- Create: `apps/control-plane/src/components/reader/DiscordReader.tsx`
- Create: `apps/control-plane/src/components/reader/ReaderStatus.tsx`
- Create: `apps/control-plane/src/components/reader/discord-reader.test.tsx`
- Modify: `apps/control-plane/src/app/page.tsx`
- Modify: `apps/control-plane/src/app/layout.tsx`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

- `readDiscordDay(input: { sourceKey?: string; date?: string }): Promise<ReaderDay>`：只返回 source display name、natural date、current daily summary、batch summaries、safe Canonical message fields (`external_message_id`, `occurred_at`, `author_display`, `content`, media flag, unresolved flag)、结构化证据 IDs 和过期状态；永不返回 `local_raw_ref`、task events、checkpoint、Worker/Prompt/Provider secret。
- `GET /api/reader/discord?source=<source_key>&date=<YYYY-MM-DD>`：任何已认证角色可调用；未认证 401；无数据返回 `{status:'no_data',days:[]}`，而非 404。
- `DiscordReader`：桌面为频道侧栏+内容区；窄屏为日期/频道顶部选择与单列内容；显示 `processing`、`partial_failure`、`retryable_failed`、`failed`、`succeeded` 和 evidence expired。

- [ ] **Step 1: 写失败测试**

  为 reader repository 使用两个来源、两天、两版 daily summary、一个过期 raw reference 和一个失败任务 fixture。断言默认只返回 current version，历史版本按需展开，来源/日期过滤不可跨源混合。API 集成测试断言普通用户读取 summary 成功但请求 `/api/admin/*` 仍为 403，响应 JSON 不含 `local_raw_ref`、`device_secret_hash`、`prompt_text`、`task_events`。

  组件测试断言普通用户在 375px 和 1280px viewport 都能选择频道/日期、展开 batch 和证据；ReaderStatus 不会把失败显示成 `no_new_data`。

- [ ] **Step 2: 运行失败测试**

  Run: `cd apps/control-plane && npm test -- --run src/components/reader/discord-reader.test.tsx src/app/api/api.integration.test.ts`

  Expected: FAIL，因为 reader repository、API 和 `/discord` 页面尚不存在。

- [ ] **Step 3: 实现只读数据形状和页面**

  1. reader repository 通过服务端受控查询读取已经生成的 summary/batch/evidence，不暴露管理表、local refs 或完整运行诊断；查询在 source/date 无效时返回安全空集合。
  2. reader route 先调用 `getCurrentUser()`，再序列化显式 allowlist DTO；不接受任意表名、task ID 或 raw ref 参数。
  3. `/discord` 要求登录，未登录重定向 `/login?next=%2Fdiscord`；首页将登录用户导向 `/discord`，管理员保留 `/admin` 导航。
  4. 组件按照“日累计 → 批次 → 原始证据/历史版本”的顺序渲染，状态和 Provider 版本置于次级区域；过期证据只显示过期标识，不形成失效链接。

- [ ] **Step 4: 验证阅读体验与权限**

  Run: `cd apps/control-plane && npm test -- --run src/components/reader/discord-reader.test.tsx src/app/api/api.integration.test.ts && npm run lint && npm run build`

  Expected: PASS；普通用户可以读取共享内容但无法获得管理或本地敏感数据。

- [ ] **Step 5: Commit**

  ```bash
  git add apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/app/api/reader apps/control-plane/src/app/discord apps/control-plane/src/components/reader apps/control-plane/src/app/page.tsx apps/control-plane/src/app/layout.tsx apps/control-plane/src/app/api/api.integration.test.ts
  git commit -m "feat(v1): add responsive discord reader"
  ```

## Task 7: 增加定时补采、V1 E2E 与真实网页门禁

**Files:**

- Create: `apps/control-plane/src/app/api/worker/schedule/tick/route.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/tasks.ts`
- Modify: `workers/v0/src/invest_hub_worker/cli.py`
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`
- Modify: `workers/v0/src/invest_hub_worker/worker.py`
- Create: `tests/e2e/v1/fixtures.py`
- Create: `tests/e2e/v1/test_multi_source_reader_flow.py`
- Create: `tests/e2e/v1/test_schedule_and_recovery.py`
- Create: `scripts/v1/run-e2e.sh`
- Test: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

- `POST /api/worker/schedule/tick` 只接受已认证 Worker，body 为 `{window_key}`；数据库对 `(source_id, window_key)` 保持唯一，重复 tick 返回已有任务而非新任务。
- `WorkerProtocol.schedule_tick(window_key: str) -> dict[str, Any]`：只在 `should_enqueue` 返回新窗口后调用。
- `scripts/v1/run-e2e.sh --mode deterministic|real-discord`：real 模式必须同时检查 `V1_REAL_DISCORD_ACK=authorized`、owner-only 多来源 config、私有 Prompt、OpenCLI contract、protected evidence 目录和一次性 Worker 凭据；缺项即失败且不创建成功结果。

- [ ] **Step 1: 写失败测试**

  API 集成测试覆盖重复 window tick 的幂等返回、未认证/错误 Worker 401、绑定 Worker 只产生其来源任务。`test_schedule_and_recovery.py` 构造两个来源：来源 A 的 Provider 失败保持 checkpoint，来源 B 成功推进并生成 reader summary；Worker 离线跨窗口后只创建每个遗漏窗口一次补采任务。

  `test_multi_source_reader_flow.py` 用公开 fixture 验证完整路径：管理员配置两个来源/规则 → Worker 领取不同来源任务 → raw/Canonical/Structured/summary receipt → 日累计版本 → 普通用户阅读 → 权限拒绝 → 失败来源局部重试。

- [ ] **Step 2: 运行失败测试**

  Run: `PYTHONPATH=workers/v0/src:. python3.11 -m unittest discover -s tests/e2e/v1 -p 'test_*.py' -v`

  Expected: FAIL，因为 schedule tick、V1 fixture 和多来源端到端路径尚不存在。

- [ ] **Step 3: 实现最小调度闭环**

  1. tasks repository 以数据库唯一键处理 window-key 幂等，而非用内存时间戳；它仅为启用且授权给当前 Worker 的来源创建默认 `max_pages:5` 增量任务。
  2. Worker CLI 在启动和每分钟循环中调用 scheduler；离线恢复将尚未观察到的 08:00/20:50 window 逐一 tick，最多补最近 48 小时的 4 个窗口，超出范围记录脱敏 warning 并等待管理员显式 history task。
  3. `run-e2e.sh` 的 deterministic 模式只使用公开 fixture/Mock；real 模式不能从环境或 stdout 回显私密路径和值，并将完整输出写入 owner-only evidence 日志。

- [ ] **Step 4: 验证全链路**

  Run: `PYTHONPATH=workers/v0/src:. python3.11 -m unittest discover -s tests/e2e/v1 -p 'test_*.py' -v`

  Expected: PASS；多来源成功/失败隔离、定时幂等、离线补采、摘要版本和普通用户阅读全部可复现。

  Run: `cd apps/control-plane && npm run lint && npm test && npm run build && cd ../.. && PYTHONPATH=workers/v0/src python3.11 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v && supabase test db`

  Expected: PASS；V0 回归与 V1 新增测试共同通过。

- [ ] **Step 5: Commit**

  ```bash
  git add apps/control-plane/src/app/api/worker/schedule apps/control-plane/src/lib/db/repositories/tasks.ts workers/v0/src/invest_hub_worker tests/e2e/v1 scripts/v1 apps/control-plane/src/app/api/api.integration.test.ts
  git commit -m "test(v1): verify multi-source scheduling and reader recovery"
  ```

## Task 8: 隔离部署、真实验收与阶段收口

**Files:**

- Create: `docs/engineering-journal/2026-07-19-v1.md`
- Create: `docs/spikes/2026-07-19-v1-decision-report.md`
- Modify: `docs/project-status.md`
- Modify: `README.md`
- Modify: `docs/README.md`

**Interfaces:**

- 只部署到专用 V1 Supabase/Vercel 环境；真实来源、真实正文、Cookie、Profile、邀请码、Prompt 和完整响应不进入云端日志或 Git。
- V1 Final Report 对 Spec 的 12 项验收逐项写 `pass`、`conditional` 或 `fail`，每项只引用脱敏 evidence key、命令、计数和限制。

- [ ] **Step 1: 运行部署前验证**

  Run: `supabase db reset && supabase test db`

  Run: `cd apps/control-plane && npm ci && npm run lint && npm test && npm run build`

  Run: `PYTHONPATH=workers/v0/src:. python3.11 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v && PYTHONPATH=workers/v0/src:. python3.11 -m unittest discover -s tests/e2e/v1 -p 'test_*.py' -v`

  Expected: 所有确定性验证通过；任一失败停止部署。

- [ ] **Step 2: 部署隔离 V1 环境并执行合成远程验收**

  Run: `supabase db push --db-url "$V1_SUPABASE_DB_URL"`

  Run: `cd apps/control-plane && vercel build && vercel deploy --prebuilt`

  Run: `V1_CONTROL_PLANE_URL="$V1_DEPLOYED_URL" PYTHONPATH=workers/v0/src:. python3.11 -m unittest discover -s tests/e2e/v1 -p 'test_*.py' -v`

  Expected: 两来源 Worker/summary/reader/role/recovery 合成路径通过；部署日志不含敏感资料。

- [ ] **Step 3: 在显式授权后执行真实 Discord 验收**

  Run: `V1_REAL_DISCORD_ACK=authorized bash scripts/v1/run-e2e.sh --mode real-discord`

  Expected: 至少两个用户已授权来源各完成一次增量同步；随后一来源执行有限 history task，普通用户在正式网页读取日累计、批次与原始证据；人为制造或保留一个来源失败，确认另一来源继续运行且失败来源 checkpoint 不前移。真实 evidence 仅保存于受保护本地目录。

- [ ] **Step 4: 运行收口安全检查并写报告**

  Run: `bash scripts/v0/redact-check.sh && git diff --check`

  Expected: `redaction_check: pass` 且无空白/冲突 diff。工程日志记录实际测试计数、真实运行状态、失败分类和恢复动作；Final Report 记录各验收项结论，不写正文、URL、Profile、Cookie、Token、Prompt 或完整响应。

- [ ] **Step 5: 更新状态、审阅并提交**

  将 V1 Final Report、工程日志、README、docs README 和 `project-status.md` 更新为实际结果。只有 Task 8 的真实验收与 Spec 12 项门槛均通过时，才能标记 V1 为“Discord 正式可用 MVP”；否则保留条件/失败结论和下一项补证据门槛。

  ```bash
  git add docs/engineering-journal/2026-07-19-v1.md docs/spikes/2026-07-19-v1-decision-report.md docs/project-status.md README.md docs/README.md
  git commit -m "docs(v1): record discord mvp validation"
  ```

## Plan Self-Review

- Spec coverage: Task 1–2 覆盖多来源、规则和权限数据；Task 3–4 覆盖有界采集、规则归因、批次/日累计摘要、证据和 checkpoint；Task 5–6 覆盖管理员与普通用户正式网页；Task 7–8 覆盖定时补采、离线恢复、真实验证、脱敏与阶段结论。
- Dependency order: 数据模型和任务快照先于 Worker/摘要持久化；摘要持久化先于阅读页；确定性 E2E 先于远程与真实验证。每个任务都有独立测试和提交点。
- Non-goal check: 未添加 X、媒体解析、普通用户 Token、自动 fallback、第二采集框架或无限历史任务。
- Placeholder scan: 本 Plan 未使用未决占位文本或“以后实现”等表述；范围上限、接口、文件和命令均已明确。
- Type consistency: `rule_snapshot`、`collection_scope`、`BatchSummaryPayload` 和 receipt summary IDs 从数据库、契约、Worker 到控制面使用相同含义；实施时若改变任一字段，必须同时更新同一 Task 中的 schema、DTO、测试和 SQL 函数。
