# X 每日判断完整主线与双模块 AI 综合研判 v5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 将正常 X 跨博主每日判断从 v4 原子观点升级为 v5 完整判断主线，并在一次 Provider 调用中生成彼此独立的“跨博主观点整合”和“AI 研判”，最终以 Reader-safe 双模块页面在生产环境展示。

**Architecture:** 保持 v4 单帖分析与 v4 单博主窗口作为冻结证据层，只升级正常跨博主每日判断合同。v5 结构由 Python Worker、Control Plane completion route 和 Supabase 最终 authority 三层独立校验，数据库追加不可变 v5 version；Reader 根据持久化 schema version 对 v2/v3/v4 使用历史投影，对 v5 使用完整主线与双模块 AI 综合研判投影。发布采用兼容式切换：新代码暂时接受在途 v4，迁移后的新 context 只声明 v5，确保 Prompt、Worker、HTTP、数据库和 Reader 不出现版本断层。

**Tech Stack:** Python 3.11+、标准库 unittest、Codex CLI Provider、Next.js 16、React 19、TypeScript 5.9、Vitest 4、Supabase CLI 2.109.1、PostgreSQL 17、pgTAP、原生 CSS。

## Global Constraints

- 正常生成版本固定为 prompt_version = "v5-x-cross-blogger-1"、schema_version = "v5-x-cross-blogger"；v3 verification replay 保持冻结 v3，v2/v3/v4 历史 version 不改写。
- v4-x-post-analysis、v4-x-window、X 采集、来源身份、checkpoint、coverage、任务调度和原始内容保留合同均不改变。
- 每个正常 v5 run 只调用一次 Provider；完整 thesis、cross_blogger_integrations 与 ai_assessments 必须来自同一个结构化响应，前端不得二次生成。
- “跨博主观点整合”只做至少两位博主的忠实归纳；“AI 研判”可以选择重要的单博主或多博主 thesis。两个数组均允许为空，不设置数量配额，不生成强制全局 overview。
- AI 研判只能使用当前冻结批次输入，不调用外部知识、模型记忆、网页搜索或未提供事实；不得生成系统自己的买入、卖出、加仓、减仓、建仓、清仓、抄底或追涨建议。
- 重要性筛选只影响 ai_assessments，不得删除、降级、重排或隐藏下方分类 thesis。
- 所有 thesis、情景、博主操作、跨博主共性与矛盾都必须闭合到 included source、analysis 和 evidence；excluded source 与 no-new source 只能形成覆盖限制。
- 普通 Reader 不输出 thesis_id、integration_id、assessment_id、source_id、analysis_id、evidence_post_id、Prompt、Provider、原始正文、任务诊断、Cookie、Profile 或本地路径。
- 无新信息批次继续不调用 Provider；partial 批次可以生成 v5，但必须显式继承覆盖限制。
- 不自动回刷历史 judgement，不重新采集，不直接修改既有 judgement JSON；发布验收只等待一次新的正常 v5 run，除非用户另行授权受控再生成。
- 不新增生产依赖；Prompt Eval 只使用 Python 标准库、现有 Worker Parser 和本机 Codex CLI，真实候选响应与 Judge 报告保存在 Git 外。
- Supabase migration 必须由 supabase migration new x_daily_judgement_thesis_synthesis_v5 创建；不得手工编造 timestamp，不使用 migration repair、db pull、远端 reset 或 Dashboard 直接改历史。
- 新增 public schema 函数必须显式 REVOKE PUBLIC/anon/authenticated，并只向 service_role 授权；本次不创建新表，不改变现有普通用户 Data API 权限。
- 保留工作区中与本任务无关的 AGENTS.md、.superpowers/ 和 docs/agents/ 改动；每次只暂存当前 Task 列出的文件。
- 每个 Task 先写失败测试、确认 RED、再写最小实现、确认 GREEN，并单独提交。

## Source of Truth

- Approved Spec: docs/superpowers/specs/2026-08-08-x-daily-judgement-thesis-synthesis-v5-design.md
- Existing v4 migration: supabase/migrations/20260805141108_x_judgement_scope_v4.sql
- Existing v4 prompt: workers/v0/prompts/v4_x_cross_blogger.md
- Existing production runtime: workers/v0/src/invest_hub_worker/runtime.py
- Existing completion authority: apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts
- Existing Reader projection: apps/control-plane/src/lib/db/repositories/reader.ts
- Approved visual reference, not committed: .superpowers/brainstorm/90061-1786165090/content/x-daily-v5-dual-ai-layout.html

## File Map

### Create

- tests/fixtures/x_daily_v5/context.json — 两位博主、三条 v4 analysis、两条 v4 window segment 的公开冻结输入。
- tests/fixtures/x_daily_v5/completion.json — 同时包含跨博主 thesis、重要单博主 thesis、跨博主整合和 AI 研判的唯一共享 v5 completion fixture。
- workers/v0/prompts/v5_x_cross_blogger.md — 正常生产 v5 公共 Prompt。
- workers/v0/evals/x_daily_v5/cases.json — 24 个公开合成 Prompt Eval case 与结构化人工 gold labels。
- workers/v0/evals/x_daily_v5/judge_prompt.md — 只比较冻结输入、gold constraints 与 candidate 的 Judge Prompt。
- workers/v0/evals/run_x_daily_v5_eval.py — 离线生成、确定性 gate、受约束 Judge 与 JSON report runner。
- workers/v0/tests/test_x_daily_v5_eval.py — Eval fixture、deterministic gate 和 verdict contract 测试。
- supabase/tests/038_x_daily_judgement_thesis_synthesis_v5.sql — v5 数据库结构、证据、权限、兼容和完成闭环 pgTAP。
- supabase/migrations/*_x_daily_judgement_thesis_synthesis_v5.sql — 由 Supabase CLI 在 Task 3 生成的唯一 additive migration。
- docs/engineering-journal/2026-08-08-x-daily-judgement-thesis-synthesis-v5.md — 实现、验证、发布、回滚与真实验收记录。

### Modify

- workers/v0/src/invest_hub_worker/structured.py — 新增 v5 严格 Parser 与证据闭包校验。
- workers/v0/src/invest_hub_worker/providers/base.py — 允许 v5_x_cross_blogger operation，并显式携带冻结来源与 opaque context 目录。
- workers/v0/src/invest_hub_worker/providers/codex_cli.py — 将 v5 operation 路由到 v5 Parser。
- workers/v0/src/invest_hub_worker/runtime.py — 正常 context 使用 v5；在途 v4 与 v3 replay 保持兼容；一次调用返回 v5。
- workers/v0/src/invest_hub_worker/protocol.py — 严格接受 v5 context/completion，并保留在途 v4 completion。
- workers/v0/tests/test_x_structured_output.py — v5 Schema、来源、证据、ID、安全与单博主 AI 研判测试。
- workers/v0/tests/test_x_cross_blogger_judgements.py — v5 Runtime、一次 Provider 调用、v4 在途和 v3 replay 测试。
- workers/v0/tests/test_provider_retry.py — v5 ProviderContext operation 与新增目录字段合同测试。
- workers/v0/tests/test_protocol.py — v5 Worker HTTP context/completion 与 transport-before-validation 测试。
- workers/v0/tests/test_x_prompts.py — v5 Prompt 边界和版本测试。
- apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts — v5 context/completion TypeScript 合同及 v4 在途兼容。
- apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts — repository v5 context/completion 解析测试。
- apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts — v5 结构、冻结证据和安全校验。
- apps/control-plane/src/app/api/api.integration.test.ts — 共享 v5 fixture 的 API completion 回归。
- apps/control-plane/src/lib/db/repositories/reader.ts — schema-aware v5 Reader-safe DTO 投影。
- apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts — v5/current/history/legacy 投影和安全字段测试。
- apps/control-plane/src/app/api/reader/x/route.test.ts — API 仅返回 v5 Reader-safe 字段。
- apps/control-plane/src/components/reader/XReader.tsx — 完整主线与双模块 AI 综合研判组件。
- apps/control-plane/src/components/reader/x-reader.test.tsx — 双模块、显隐、完整主线、移动顺序和 legacy 回归。
- apps/control-plane/src/app/globals.css — 已确认的绿色来源归纳、紫色 AI 分析和响应式样式。
- apps/control-plane/src/app/globals.test.ts — 双模块视觉 token、身份区隔与 375px 规则测试。
- scripts/v2/run-v2-e2e.sh — 将 v5 Eval 确定性测试和共享合同回归加入 V2 gate。
- docs/project-status.md — 仅在 Task 9 真实发布后记录最终状态和证据。

---

### Task 1: Freeze the shared v5 contract and implement the Worker structured parser

**Files:**
- Create: tests/fixtures/x_daily_v5/context.json
- Create: tests/fixtures/x_daily_v5/completion.json
- Modify: workers/v0/tests/test_x_structured_output.py
- Modify: workers/v0/src/invest_hub_worker/structured.py

**Interfaces:**
- Consumes: v4 context sources whose analyses and window segments are already frozen and evidence-complete.
- Produces: parse_v5_x_cross_blogger_output(text, *, allowed_source_ids, allowed_analysis_ids, allowed_post_ids, analysis_source_ids, analysis_evidence_post_ids, frozen_source_ids, opaque_context_ids, input_sources) -> dict[str, object].
- Produces: one normalized v5 object with ai_synthesis, three thesis arrays and top-level uncertainties; no legacy viewpoint projection is produced here.

- [ ] **Step 1: Create the two shared public fixtures.**

Use stable synthetic identities source-alpha and source-beta, analyses post-alpha@2, post-alpha-2@2 and post-beta@2, and evidence post-alpha, post-alpha-2 and post-beta. context.json must retain the exact current v4 context shape:

~~~json
{
  "run_id": "judgement-run-v5",
  "batch_id": "batch-v5",
  "attempt": 1,
  "prompt_version": "v5-x-cross-blogger-1",
  "sources": [],
  "excluded_sources": []
}
~~~

Populate sources with two non-empty v4-x-window segments. source-alpha contains post-alpha@2 and post-alpha-2@2; source-beta contains post-beta@2. Each segment_output.analysis_ids and evidence_post_ids must equal the exact union of its analyses.

completion.json must contain exactly:

- security-01 supported by source-alpha and source-beta, with one scenario branch and one source-alpha attributed action;
- market-01 supported only by source-alpha;
- integration-01 whose common point names both sources and whose conflict has two positions across the two sources;
- assessment-01 related only to market-01, proving an important single-blogger thesis is legal;
- empty strategy_mindset_theses and empty top-level uncertainties.

- [ ] **Step 2: Add failing parser tests for the complete v5 shape.**

Add a load_json_fixture(name: str) helper and these tests:

~~~python
def test_v5_cross_blogger_accepts_complete_theses_and_dual_ai_modules(self):
    parsed = structured.parse_v5_x_cross_blogger_output(
        json.dumps(completion),
        allowed_source_ids={"source-alpha", "source-beta"},
        allowed_analysis_ids={"post-alpha@2", "post-alpha-2@2", "post-beta@2"},
        allowed_post_ids={"post-alpha", "post-alpha-2", "post-beta"},
        analysis_source_ids={
            "post-alpha@2": "source-alpha",
            "post-alpha-2@2": "source-alpha",
            "post-beta@2": "source-beta",
        },
        analysis_evidence_post_ids={
            "post-alpha@2": {"post-alpha"},
            "post-alpha-2@2": {"post-alpha-2"},
            "post-beta@2": {"post-beta"},
        },
        frozen_source_ids={"source-alpha", "source-beta"},
        opaque_context_ids={"batch": {"batch-v5"}, "run": {"judgement-run-v5"}, "segment": {"segment-alpha", "segment-beta"}},
        input_sources=context["sources"],
    )
    self.assertEqual(parsed["ai_synthesis"]["ai_assessments"][0]["related_thesis_ids"], ["market-01"])
~~~

Add table-driven mutations that must raise SchemaError for: extra root field, non-consecutive thesis ID, duplicate ID across categories, empty thesis evidence, analysis/source ownership mismatch, scenario evidence outside its thesis, attributed action using a second source, integration with one-source common point, conflict with one position, conflict whose position source union has one blogger, integration top-level thesis union mismatch, unknown related thesis, duplicate assessment ID, false strong-consensus wording, natural-language opaque ID and imperative system trade advice.

- [ ] **Step 3: Run the focused parser test and confirm RED.**

Run:

~~~bash
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_structured_output.py -v
~~~

Expected: FAIL because parse_v5_x_cross_blogger_output and v5 field constants do not exist.

- [ ] **Step 4: Add exact v5 field constants and ID validators.**

Add these constants beside the v4 constants:

~~~python
V5_X_CROSS_BLOGGER_FIELDS = frozenset({
    "schema_version", "ai_synthesis", "security_industry_theses",
    "market_structure_theses", "strategy_mindset_theses", "uncertainties",
})
V5_X_AI_SYNTHESIS_FIELDS = frozenset({"cross_blogger_integrations", "ai_assessments"})
V5_X_THESIS_FIELDS = frozenset({
    "thesis_id", "headline", "synthesis", "scenario_branches", "attributed_actions",
    "supporting_source_ids", "dissenting_source_ids", "analysis_ids",
    "evidence_post_ids", "uncertainties",
})
V5_X_SCENARIO_FIELDS = frozenset({
    "condition", "outcome", "source_ids", "analysis_ids", "evidence_post_ids", "uncertainties",
})
V5_X_ACTION_FIELDS = frozenset({
    "source_id", "action_intent", "action_scope_status", "action_scope",
    "conditions", "analysis_ids", "evidence_post_ids", "uncertainties",
})
V5_X_INTEGRATION_FIELDS = frozenset({
    "integration_id", "headline", "synthesis", "common_points",
    "conflict_points", "related_thesis_ids", "uncertainties",
})
V5_X_COMMON_POINT_FIELDS = frozenset({"statement", "source_ids", "related_thesis_ids"})
V5_X_CONFLICT_FIELDS = frozenset({"issue", "positions"})
V5_X_POSITION_FIELDS = frozenset({"position", "source_ids", "related_thesis_ids"})
V5_X_ASSESSMENT_FIELDS = frozenset({
    "assessment_id", "headline", "judgement", "importance_reason", "reasoning",
    "key_assumptions", "risks", "watch_variables", "related_thesis_ids", "uncertainties",
})
~~~

Validate security-NN, market-NN, strategy-NN, integration-NN and assessment-NN with anchored regular expressions, consecutive numbering from 01 and uniqueness across the whole output.

- [ ] **Step 5: Implement thesis, nested evidence and source closure.**

For every thesis, require exact fields, non-empty headline/synthesis, unique source/analysis/evidence arrays, at least one supporting source, at least one analysis and exact evidence union. Require:

~~~python
thesis_sources == {analysis_source_ids[analysis_id] for analysis_id in thesis["analysis_ids"]}
thesis_evidence == set().union(
    *(analysis_evidence_post_ids[analysis_id] for analysis_id in thesis["analysis_ids"])
)
~~~

Each scenario branch must be a non-empty, evidence-backed subset of its parent thesis. Each attributed action must pass _validate_v4_action_scope, name exactly one parent-thesis source, and cite only analyses/evidence owned by that source and parent thesis. Run opaque-ID and imperative recommendation checks over every natural-language field.

Scan thesis headline, synthesis, scenario and action text for strong-consensus wording. Such wording is legal only when the parent thesis has at least two independent supporting sources and no dissenting source.

- [ ] **Step 6: Implement integration and AI assessment validation.**

Build a thesis_by_id catalog and a thesis_sources catalog. For each integration:

- related_thesis_ids is non-empty, unique and valid;
- every common point has at least two unique sources;
- every conflict has at least two non-empty positions and the union of position sources has at least two bloggers;
- every child source belongs to the sources of its child related theses;
- top-level related_thesis_ids equals the de-duplicated union of child related_thesis_ids;
- common_points and conflict_points are not both empty.

For each assessment, require at least one valid related thesis and non-empty headline, judgement, importance_reason and reasoning. Do not impose a two-source minimum. Reject opaque IDs and imperative system trade advice in all assessment text. Extract numbers, percentages, currency expressions, stock codes and uppercase ticker-like tokens from input_sources; reject any such token newly introduced by the candidate. Leave semantic “new event/factual claim” detection to Task 7 Judge rather than pretending a regex can prove it.

For strong-consensus wording in an integration or assessment, compute the supporting and dissenting source union of the directly related theses. Require at least two independent supporting sources and no dissenting source; the ordinary single-source AI assessment remains legal when it does not upgrade the thesis into consensus.

- [ ] **Step 7: Run the focused tests and commit.**

Run:

~~~bash
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_structured_output.py -v
git diff --check
~~~

Expected: PASS; the important single-source assessment passes, while one-source cross-blogger integration and every evidence/ID/safety mutation fail closed.

Commit:

~~~bash
git add tests/fixtures/x_daily_v5 workers/v0/src/invest_hub_worker/structured.py workers/v0/tests/test_x_structured_output.py
git commit -m "feat: validate X daily judgement v5 output"
~~~

### Task 2: Add the v5 Prompt and align Provider, Runtime and Worker Protocol

**Files:**
- Create: workers/v0/prompts/v5_x_cross_blogger.md
- Modify: workers/v0/src/invest_hub_worker/providers/base.py
- Modify: workers/v0/src/invest_hub_worker/providers/codex_cli.py
- Modify: workers/v0/src/invest_hub_worker/runtime.py
- Modify: workers/v0/src/invest_hub_worker/protocol.py
- Modify: workers/v0/tests/test_x_prompts.py
- Modify: workers/v0/tests/test_x_cross_blogger_judgements.py
- Modify: workers/v0/tests/test_provider_retry.py
- Modify: workers/v0/tests/test_protocol.py

**Interfaces:**
- Consumes: Task 1 parse_v5_x_cross_blogger_output and the unchanged v4 upstream context.
- Produces: ProviderContext(operation="v5_x_cross_blogger", prompt_version="v5-x-cross-blogger-1")，并携带 frozen_source_ids 与可序列化的 opaque_context_ids。
- Produces: XDailyJudgementRuntime.execute returning one v5 completion after exactly one Provider.complete call.
- Produces: Worker Protocol accepting v5 normal traffic plus v4 in-flight compatibility; v3 replay remains unchanged.

- [ ] **Step 1: Add failing Prompt and Runtime tests.**

In test_x_prompts.py assert the new Prompt contains every stable contract phrase: complete thesis, scenario_branches, attributed_actions, cross_blogger_integrations, ai_assessments, “不获取外部信息”, “不构成交易建议”, “单博主”, “至少两位独立博主”, “覆盖限制”, and “只输出一个合法 JSON 对象”.

In test_x_cross_blogger_judgements.py update the normal context helper to v5 and assert:

~~~python
self.assertEqual(provider.calls, 1)
self.assertEqual(provider.context.operation, "v5_x_cross_blogger")
self.assertEqual(result["schema_version"], "v5-x-cross-blogger")
self.assertEqual(result["prompt_version"], "v5-x-cross-blogger-1")
self.assertIn("ai_synthesis", result)
self.assertIn("security_industry_theses", result)
self.assertEqual(provider.context.frozen_source_ids, frozenset({"source-alpha", "source-beta"}))
self.assertEqual(dict(provider.context.opaque_context_ids)["batch"], ("batch-v5",))
~~~

Add one separate test where context.prompt_version remains v4-x-cross-blogger-1 and the runtime returns a v4 completion, proving only in-flight compatibility. Keep every v3 replay assertion unchanged.

Keep an explicit no_new_information regression proving Provider calls remain zero. Add a partial context case whose v5 output has empty top-level uncertainties and require the Runtime to reject it; the same completion passes after a non-empty natural-language coverage limitation is added.

In test_provider_retry.py, assert v5_x_cross_blogger is an approved operation and the two new catalogs reject blank IDs, duplicate context kinds and duplicate IDs inside one kind.

- [ ] **Step 2: Add failing Protocol tests.**

Load the shared completion fixture, add run_id, attempt, provider, model_reported and prompt_version, then assert WorkerProtocol.complete_x_daily_judgement sends it only after local validation. Add mutations for an extra field, malformed thesis, one-source common point and invalid AI related thesis; transport must not be called. Keep a legal v4 completion test to prove the rollout compatibility branch.

- [ ] **Step 3: Run the focused tests and confirm RED.**

Run:

~~~bash
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest \
  workers/v0/tests/test_x_prompts.py \
  workers/v0/tests/test_x_cross_blogger_judgements.py \
  workers/v0/tests/test_provider_retry.py \
  workers/v0/tests/test_protocol.py -v
~~~

Expected: FAIL because the v5 Prompt, operation, Runtime branch and Protocol validator do not exist.

- [ ] **Step 4: Write the public v5 Prompt.**

Use the approved Spec’s exact schema. The Prompt must order work internally as:

1. identify candidate theses by object, core proposition, causal chain, time scale and conditions;
2. merge conclusion, cause, condition, scenario, invalidation and attributed action into one thesis;
3. create zero-to-many cross-blogger integrations only where a real two-source relationship exists;
4. select only important theses for zero-to-many AI assessments;
5. perform a silent source/evidence/ID/external-fact/trade-advice self-check;
6. output one JSON object and no Markdown.

Do not ask the model for a fixed number of theses, integrations or assessments. Do not mention ChatGPT as the product identity.

- [ ] **Step 5: Add v5 Provider dispatch.**

Add "v5_x_cross_blogger" to ProviderContext.__post_init__ allow-list. Add the following immutable fields and validate that every value is a non-empty string, context kinds are unique, and IDs inside each kind are unique:

~~~python
frozen_source_ids: frozenset[str] = frozenset()
opaque_context_ids: tuple[tuple[str, tuple[str, ...]], ...] = ()
~~~

When normal v5 Runtime constructs ProviderContext, set frozen_source_ids to every source in the frozen batch, including excluded/no-new sources, and set opaque_context_ids to sorted batch/run/segment ID tuples. In CodexCLIProvider._parse_for_context add:

~~~python
if context.operation == "v5_x_cross_blogger":
    return parse_v5_x_cross_blogger_output(
        raw_text,
        allowed_source_ids=set(context.allowed_source_ids),
        allowed_analysis_ids=set(context.allowed_analysis_ids),
        allowed_post_ids=set(context.allowed_post_ids),
        analysis_source_ids=dict(context.allowed_analysis_source_ids),
        analysis_evidence_post_ids={
            analysis_id: set(post_ids)
            for analysis_id, post_ids in context.allowed_analysis_evidence_post_ids
        },
        frozen_source_ids=set(context.frozen_source_ids),
        opaque_context_ids={
            kind: set(ids)
            for kind, ids in context.opaque_context_ids
        },
        input_sources=input_chunk,
    )
~~~

- [ ] **Step 6: Make Runtime version-aware without adding a second call.**

Load v5_x_cross_blogger.md as the normal public template. Replace the current binary v3/normal branch with a three-entry version table:

~~~python
version_contracts = {
    "v3-x-cross-blogger-1": ("v3_x_cross_blogger", "v3-x-cross-blogger", self.v3_public_template),
    "v4-x-cross-blogger-1": ("v4_x_cross_blogger", "v4-x-cross-blogger", self.v4_public_template),
    "v5-x-cross-blogger-1": ("v5_x_cross_blogger", "v5-x-cross-blogger", self.public_template),
}
~~~

For v5, continue requiring v4-x-window-1 and v4-x-post-analysis-1 upstream. Call provider.complete exactly once, validate its parsed_output once more at the Runtime boundary, and return the v5 output fields without projecting them into v4 viewpoints. If context is partial or has excluded/no-new sources, require non-empty top-level uncertainties; no-new-information batches continue to exit before Provider invocation.

- [ ] **Step 7: Add strict v5 Protocol validation with v4 in-flight compatibility.**

Allow context prompt_version v4-x-cross-blogger-1 or v5-x-cross-blogger-1; both still require v4 upstream segments and analyses. Dispatch completion validation by schema/prompt pair:

~~~python
if pair == ("v5-x-cross-blogger", "v5-x-cross-blogger-1"):
    _validate_v5_x_daily_judgement_completion(value)
elif pair == ("v4-x-cross-blogger", "v4-x-cross-blogger-1"):
    _validate_v4_x_daily_judgement_completion(value)
else:
    raise ProtocolError("invalid x daily judgement completion")
~~~

The v5 validator must enforce exact fields, safe telemetry, ID shape, nested collection types, action-scope consistency, non-empty thesis evidence and a non-empty top-level coverage limitation whenever context is partial or contains excluded/no-new sources, before any HTTP request. Runtime and Control Plane remain the stronger ownership authorities.

- [ ] **Step 8: Run Worker tests and commit.**

Run:

~~~bash
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest \
  workers/v0/tests/test_x_prompts.py \
  workers/v0/tests/test_x_structured_output.py \
  workers/v0/tests/test_x_cross_blogger_judgements.py \
  workers/v0/tests/test_provider_retry.py \
  workers/v0/tests/test_protocol.py -v
~~~

Expected: PASS; normal v5 uses one Provider call, v4 in-flight and v3 replay remain accepted, malformed v5 fails before transport.

Commit:

~~~bash
git add workers/v0/prompts/v5_x_cross_blogger.md workers/v0/src/invest_hub_worker/providers/base.py workers/v0/src/invest_hub_worker/providers/codex_cli.py workers/v0/src/invest_hub_worker/runtime.py workers/v0/src/invest_hub_worker/protocol.py workers/v0/tests/test_x_prompts.py workers/v0/tests/test_x_cross_blogger_judgements.py workers/v0/tests/test_provider_retry.py workers/v0/tests/test_protocol.py
git commit -m "feat: generate X daily judgement v5"
~~~

### Task 3: Add Supabase v5 final authority and additive persistence compatibility

**Files:**
- Create: supabase/tests/038_x_daily_judgement_thesis_synthesis_v5.sql
- Create: supabase/migrations/*_x_daily_judgement_thesis_synthesis_v5.sql via Supabase CLI

**Interfaces:**
- Consumes: unchanged v4 segment/analysis rows from the frozen batch.
- Produces: get_x_daily_judgement_context returning prompt_version v5-x-cross-blogger-1 for v4-upstream normal runs.
- Produces: validate_x_daily_judgement_output_v5(jsonb) and validate_x_daily_judgement_output_authority_v5(uuid, jsonb).
- Produces: complete_x_daily_judgement accepting v5 normal completion and v4 in-flight completion, while persisting immutable schema-versioned output.

- [ ] **Step 1: Write the failing pgTAP contract.**

Start with begin; select plan(22); and rollback. Reuse the public synthetic source/batch/segment setup from 036_x_judgement_scope_v4.sql, then implement exactly these 22 top-level assertions:

1. v4 upstream context now reports v5 prompt version;
2. valid v5 completion appends one revision with v5 schema/prompt;
3. valid important single-source ai_assessment succeeds;
4. duplicate thesis ID fails;
5. non-consecutive thesis ID fails;
6. thesis source/analysis/evidence mismatch fails;
7. scenario evidence outside its parent thesis fails;
8. attributed action evidence outside its source and parent thesis fails;
9. one-source integration fails;
10. one-source common point fails;
11. conflict with fewer than two positions fails;
12. conflict whose positions cover fewer than two source identities fails;
13. integration top-level related_thesis_ids union mismatch fails;
14. unknown assessment thesis fails;
15. natural-language opaque ID fails;
16. strong-consensus wording with one supporting source or any dissenting source fails;
17. imperative system trade advice fails;
18. input-external numeric or ticker-like token fails;
19. excluded source evidence fails;
20. a partial completion without a top-level coverage limitation fails;
21. an already valid v4 version remains insertable/readable for in-flight compatibility;
22. a combined privilege assertion proves anon/authenticated cannot execute either new validator or the completion authority.

- [ ] **Step 2: Run the focused pgTAP file and confirm RED.**

Run:

~~~bash
supabase test db supabase/tests/038_x_daily_judgement_thesis_synthesis_v5.sql
~~~

Expected: FAIL because the v5 validator functions and v5 completion branch do not exist.

- [ ] **Step 3: Create the migration with the verified CLI command.**

Run:

~~~bash
supabase migration new x_daily_judgement_thesis_synthesis_v5
~~~

Use the exact path printed by Supabase CLI. Do not rename its timestamp. The installed CLI is 2.109.1; the command was verified with supabase migration new --help and matches the official CLI migration contract.

- [ ] **Step 4: Implement structural validation in validate_x_daily_judgement_output_v5.**

Use exact jsonb key subtraction checks for root, ai_synthesis, thesis, scenario, action, integration, common point, conflict, position and assessment objects. Validate:

- safe non-empty text lengths using x_daily_judgement_safe_text;
- arrays, allowed action enums and action_scope_status consistency;
- ID regular expressions, uniqueness and consecutive numbering;
- non-empty thesis support/analysis/evidence;
- non-empty integration/assessment references;
- no internal ID text and no imperative system trade advice.

Do not create a table or change RLS. Keep this function SECURITY INVOKER and set search_path = public.

- [ ] **Step 5: Implement batch authority in validate_x_daily_judgement_output_authority_v5.**

Build frozen catalogs from x_collection_batch_sources, x_daily_viewpoint_segments, x_post_analyses and canonical_messages, exactly as v4 authority does. For each thesis enforce exact source ownership and evidence union; for each scenario and action enforce parent-thesis subsets. Build temporary thesis/source catalogs for integration and assessment reference validation. Apply strong-consensus wording checks to thesis text and to the directly related source union of integrations/assessments. Require non-empty top-level uncertainties when batch coverage is partial or contains excluded/no-new sources. For input-external numeric and ticker-like tokens, compare candidate tokens against the flattened frozen segment_output and analysis_output text; semantic event claims remain a Prompt Eval gate.

- [ ] **Step 6: Switch normal context to v5 and preserve old versions.**

Replace get_x_daily_judgement_context so the v4-upstream branch returns prompt_version v5-x-cross-blogger-1. Keep the legacy upstream fallback and all v4 segment/analysis checks.

Update enforce_x_daily_judgement_version:

~~~sql
if new.schema_version = 'v5-x-cross-blogger' then
  perform public.validate_x_daily_judgement_output_authority_v5(new.batch_id, new.output);
elsif new.schema_version = 'v4-x-cross-blogger' then
  perform public.validate_x_daily_judgement_output_authority_v4(new.batch_id, new.output);
else
  perform public.validate_x_daily_judgement_output_authority(new.batch_id, new.output);
end if;
~~~

Update complete_x_daily_judgement to accept exact v5/v5, v4/v4 and existing v2/v2 pairs. Persist v5 output by removing only schema_version, provider, model_reported and prompt_version; do not rewrite prior rows.

- [ ] **Step 7: Apply explicit function privileges.**

REVOKE ALL on both v5 validator functions from PUBLIC, anon and authenticated; GRANT EXECUTE only to service_role. Preserve the existing completion/context grants and their worker authentication boundary.

- [ ] **Step 8: Reset the local database, run pgTAP and commit.**

Run:

~~~bash
supabase db reset
supabase test db supabase/tests/036_x_judgement_scope_v4.sql supabase/tests/037_x_failed_daily_judgement_recovery.sql supabase/tests/038_x_daily_judgement_thesis_synthesis_v5.sql
supabase test db
supabase db advisors --local --type all --level warn --fail-on error
supabase migration list --local
git diff --check
~~~

Expected: all migrations apply from empty state; v4 recovery tests remain green; v5 authority rejects every malformed mutation and accepts the important single-source AI assessment.

Commit:

~~~bash
git add supabase/migrations/*_x_daily_judgement_thesis_synthesis_v5.sql supabase/tests/038_x_daily_judgement_thesis_synthesis_v5.sql
git commit -m "feat: persist X daily judgement v5"
~~~

### Task 4: Align the Control Plane repository and completion route

**Files:**
- Modify: apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts
- Modify: apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts
- Modify: apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts
- Modify: apps/control-plane/src/app/api/api.integration.test.ts

**Interfaces:**
- Consumes: Task 1 shared context/completion fixtures and Task 3 RPC contracts.
- Produces: TypeScript XDailyJudgementV5Completion and nested v5 types.
- Produces: POST /api/worker/x-daily-judgements/[runId]/complete that fail-closes before RPC and accepts v4 in-flight or v5 normal payloads.

- [ ] **Step 1: Add failing repository and API tests using the shared fixtures.**

Read the JSON files with node:fs from the repository root. Assert getXDailyJudgementContext accepts v5 prompt_version with unchanged v4 nested analyses. Assert complete route returns 200 and sends a payload without run_id/attempt to the RPC. Add 422 mutations for unknown thesis reference, one-source common point, nested evidence escape, duplicate ID, false strong consensus, missing partial-coverage limitation, unsafe model_reported, opaque ID and system trade advice.

Keep one legal v4 completion test. This test proves the rollout window remains compatible.

- [ ] **Step 2: Run the focused tests and confirm RED.**

Run:

~~~bash
cd apps/control-plane
npm test -- src/lib/db/repositories/x-daily-judgements.test.ts src/app/api/api.integration.test.ts
~~~

Expected: FAIL because repository types and completion route only accept v4.

- [ ] **Step 3: Define exact v5 TypeScript types.**

Add nested exported types matching the Spec:

~~~typescript
export type XDailyJudgementV5Completion = {
  run_id: string;
  attempt: number;
  schema_version: "v5-x-cross-blogger";
  provider: "codex_cli";
  model_reported: string | null;
  prompt_version: "v5-x-cross-blogger-1";
  ai_synthesis: {
    cross_blogger_integrations: XDailyJudgementIntegration[];
    ai_assessments: XDailyJudgementAssessment[];
  };
  security_industry_theses: XDailyJudgementThesis[];
  market_structure_theses: XDailyJudgementThesis[];
  strategy_mindset_theses: XDailyJudgementThesis[];
  uncertainties: string[];
};
~~~

Rename the existing completion type to XDailyJudgementV4Completion and export XDailyJudgementCompletion as their union. Make XDailyJudgementContext.prompt_version a v4/v5 union while its nested segment/analysis types remain v4.

- [ ] **Step 4: Split route validation by completion version.**

Keep isV4Completion for in-flight payloads. Add isV5Completion with exact-key checks at every nested level, text length limits, allowed enums, unique/consecutive IDs and safe model telemetry. Dispatch only on a matching schema/prompt pair.

- [ ] **Step 5: Extend frozen-context validation to v5.**

Build the same source, analysis, evidence and opaque-ID catalogs once. For v5:

- validate every thesis’s exact source/analysis/evidence closure;
- validate scenario/action subsets;
- build thesisById and thesisSources;
- validate integration source and thesis relationships;
- allow one valid related thesis in ai_assessments;
- require strong-consensus wording to close to at least two supporting sources and no dissent, including integration/assessment text through related theses;
- require non-empty top-level uncertainties for partial or excluded/no-new context;
- reject external numeric/ticker-like tokens against the flattened context catalog;
- scan every natural-language field for opaque IDs and imperative system advice.

Return false on the first violation; do not repair, drop or normalize model fields in the route.

- [ ] **Step 6: Run focused and full Control Plane tests, then commit.**

Run:

~~~bash
cd apps/control-plane
npm test -- src/lib/db/repositories/x-daily-judgements.test.ts src/app/api/api.integration.test.ts
npm test
cd ../..
git diff --check
~~~

Expected: PASS; v5 is accepted only when it closes to frozen context, malformed v5 returns 422 before RPC, and v4 in-flight tests remain green.

Commit:

~~~bash
git add apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts 'apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts' apps/control-plane/src/app/api/api.integration.test.ts
git commit -m "feat: accept X daily judgement v5 completion"
~~~

### Task 5: Add a schema-aware Reader-safe v5 projection

**Files:**
- Modify: apps/control-plane/src/lib/db/repositories/reader.ts
- Modify: apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts
- Modify: apps/control-plane/src/app/api/reader/x/route.test.ts

**Interfaces:**
- Consumes: persisted x_daily_judgement_versions.output plus schema_version and prompt_version.
- Produces: legacy ReaderJudgement arrays for v2/v3/v4 and new ReaderThesis/ReaderAiSynthesis DTOs for v5.
- Produces: no internal IDs in readXDay or GET /api/reader/x.

- [ ] **Step 1: Add failing Reader projection tests.**

Extend the mocked version query to include schema_version and prompt_version. Add one v5 current revision from completion.json and one v4 history revision. Assert:

- current.presentationKind is "v5";
- current.aiSynthesis.crossBloggerIntegrations and aiAssessments contain readable text;
- common and conflict positions contain display names, not source IDs;
- securityIndustryTheses contain scenarios and attributed actions;
- marketStructureTheses contains the single-source thesis selected by AI;
- current.uncertainties retains the batch-level coverage limitation;
- history.presentationKind is "legacy";
- no thesis/integration/assessment/source/analysis/evidence IDs escape.

Add the same forbidden-field assertions to route.test.ts.

- [ ] **Step 2: Run the focused tests and confirm RED.**

Run:

~~~bash
cd apps/control-plane
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts src/app/api/reader/x/route.test.ts
~~~

Expected: FAIL because version queries do not read schema_version and the DTO has no v5 projection.

- [ ] **Step 3: Define the Reader-safe v5 DTO.**

Add:

~~~typescript
export type ReaderThesis = {
  headline: string;
  synthesis: string;
  scenarioBranches: Array<{ condition: string; outcome: string; uncertainties: string[] }>;
  attributedActions: Array<{
    displayName: string;
    actionIntent: ReaderActionIntent;
    actionScope: string;
    actionScopeStatus: ReaderActionScopeStatus;
    conditions: string[];
    uncertainties: string[];
  }>;
  supportingDisplayNames: string[];
  dissentingDisplayNames: string[];
  uncertainties: string[];
};
~~~

Define ReaderCrossBloggerIntegration and ReaderAiAssessment with only approved readable fields. Add presentationKind: "legacy" | "v5" to XReaderJudgementRevision. Keep legacy stockViewpoints, marketIndustryViewpoints and strategyMindsetViewpoints; add aiSynthesis and the three thesis arrays rather than coercing old viewpoint cards into v5 theses. Preserve top-level uncertainties as the revision’s batch-level coverage limitation for both presentation kinds.

- [ ] **Step 4: Implement schema-aware mapping.**

Select batch_id, revision, coverage_status, output, schema_version and prompt_version. In judgementRevision:

- v5/v5 maps only the v5 arrays and ai_synthesis;
- v2/v3/v4 maps only existing legacy arrays;
- unknown or mismatched version pairs fail closed to an empty safe revision rather than guessing a shape.

Resolve source IDs to display names inside the repository. Drop every related_thesis_id and internal identity after it has served mapping. Preserve current revision ordering, legacy history, verification recovery and all/source/date behavior.

- [ ] **Step 5: Run Reader repository/API tests and commit.**

Run:

~~~bash
cd apps/control-plane
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts src/app/api/reader/x/route.test.ts
cd ../..
git diff --check
~~~

Expected: PASS; v5 current and v4 history coexist, all readable source attribution is preserved, and internal IDs are absent from serialized API output.

Commit:

~~~bash
git add apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts apps/control-plane/src/app/api/reader/x/route.test.ts
git commit -m "feat: project X daily judgement v5 safely"
~~~

### Task 6: Render complete theses and the approved dual-module AI synthesis layout

**Files:**
- Modify: apps/control-plane/src/components/reader/XReader.tsx
- Modify: apps/control-plane/src/components/reader/x-reader.test.tsx
- Modify: apps/control-plane/src/app/globals.css
- Modify: apps/control-plane/src/app/globals.test.ts

**Interfaces:**
- Consumes: Task 5 presentationKind, aiSynthesis and three ReaderThesis arrays.
- Produces: AI 综合研判 → 跨博主观点整合 / AI 研判 → 三类完整判断主线 → 单个博主观点.
- Preserves: existing legacy JudgementCard and all single-blogger timeline behavior.

- [ ] **Step 1: Add failing DOM tests for hierarchy and conditional rendering.**

Create a v5 fixture whose cross-blogger and AI arrays are both non-empty. Assert the DOM order:

~~~typescript
expect(html.indexOf("输入覆盖")).toBeLessThan(html.indexOf("AI 综合研判"));
expect(html.indexOf("跨博主观点整合")).toBeLessThan(html.indexOf("AI 研判"));
expect(html.indexOf("AI 综合研判")).toBeLessThan(html.indexOf("个股与产业判断"));
expect(html.indexOf("个股与产业判断")).toBeLessThan(html.indexOf("市场结构判断"));
expect(html.indexOf("市场结构判断")).toBeLessThan(html.indexOf("投资策略与心态"));
expect(html.indexOf("投资策略与心态")).toBeLessThan(html.indexOf("批次整体不确定性"));
expect(html.indexOf("批次整体不确定性")).toBeLessThan(html.indexOf("单个博主观点"));
~~~

Assert identity labels “博主观点归纳” and “AI 分析判断”, the fixed disclaimer, per-common/per-position blogger names, scenarios nested under one thesis, attributed action labels and AI-selected/unselected theses both remain visible.

Add three visibility cases: only integration, only assessment, and both empty. Each child hides independently; the whole AI container hides only when both are empty. Keep legacy v4 rendering assertions unchanged.

- [ ] **Step 2: Add failing CSS contract tests.**

Assert these selectors and exact approved tokens exist:

~~~typescript
expect(css).toMatch(/\.x-ai-synthesis\s*\{[^}]*background:\s*#f4f7f8;/s);
expect(css).toMatch(/\.x-ai-integration-card\s*\{[^}]*border-left:\s*4px solid #4b9c8e;/s);
expect(css).toMatch(/\.x-ai-assessment-card\s*\{[^}]*border-left:\s*4px solid #8c65ae;/s);
expect(css).toMatch(/\.x-ai-source-badge\s*\{[^}]*background:\s*#dff0eb;/s);
expect(css).toMatch(/\.x-ai-model-badge\s*\{[^}]*background:\s*#ece5f5;/s);
expect(css).toMatch(/@media \(max-width:\s*760px\)[\s\S]*\.x-ai-info-grid/s);
~~~

- [ ] **Step 3: Run focused UI tests and confirm RED.**

Run:

~~~bash
cd apps/control-plane
npm test -- src/components/reader/x-reader.test.tsx src/app/globals.test.ts
~~~

Expected: FAIL because v5 DOM branches and dual-module selectors do not exist.

- [ ] **Step 4: Implement separate legacy and v5 presentation branches.**

Keep JudgementCard for presentationKind="legacy". For v5 add local components with exact responsibilities:

~~~typescript
function AiSynthesisSection(props: { synthesis: ReaderAiSynthesis }): ReactElement | null
function CrossBloggerIntegrationCard(props: { integration: ReaderCrossBloggerIntegration; index: number }): ReactElement
function AiAssessmentCard(props: { assessment: ReaderAiAssessment; index: number }): ReactElement
function ThesisModule(props: { title: string; tone: ViewpointTone; theses: ReaderThesis[] }): ReactElement | null
function ThesisCard(props: { thesis: ReaderThesis; index: number }): ReactElement
~~~

AiSynthesisSection returns null only when both child arrays are empty. ThesisCard renders headline and continuous synthesis first; scenario A/B/C and attributed actions remain nested inside the same card and never receive a new thesis number. Render non-empty top-level uncertainties once, after the three thesis modules, under “批次整体不确定性”; do not duplicate it inside individual cards.

- [ ] **Step 5: Implement the approved editorial styles.**

Use the accepted visual values:

- container background #f4f7f8, header #e8eef1, border #aebcc5;
- source badge #dff0eb / #1d665a and integration accent #4b9c8e;
- model badge #ece5f5 / #69418b and assessment accent #8c65ae;
- integration info cells #f1f8f6 and assessment info cells #f7f3fa;
- two-column info grids above 760px and one column at or below 760px;
- no horizontal overflow at 375px; long source names and thesis text use overflow-wrap:anywhere.

Keep existing category tones for the three thesis groups. Do not convert the entire Reader into nested SaaS cards.

- [ ] **Step 6: Run UI/API regressions and commit.**

Run:

~~~bash
cd apps/control-plane
npm test -- src/components/reader/x-reader.test.tsx src/app/globals.test.ts src/app/api/reader/x/route.test.ts
npm test
cd ../..
git diff --check
~~~

Expected: PASS; v5 hierarchy, independent child hiding, legacy history, single-blogger filters and 375px CSS contract remain correct.

Commit:

~~~bash
git add apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/components/reader/x-reader.test.tsx apps/control-plane/src/app/globals.css apps/control-plane/src/app/globals.test.ts
git commit -m "feat: render X daily v5 synthesis and theses"
~~~

### Task 7: Build the release-only Prompt Eval with human gold labels and bounded Judge

**Files:**
- Create: workers/v0/evals/x_daily_v5/cases.json
- Create: workers/v0/evals/x_daily_v5/judge_prompt.md
- Create: workers/v0/evals/run_x_daily_v5_eval.py
- Create: workers/v0/tests/test_x_daily_v5_eval.py
- Modify: scripts/v2/run-v2-e2e.sh

**Interfaces:**
- Consumes: v5 public Prompt, optional local private Prompt path, 24 public frozen contexts and generated candidates.
- Produces: deterministic verdict before any Judge; optional bounded Judge verdict only for marked cases that already passed deterministic gates.
- Produces: a Git-excluded JSON report with prompt/model/input/candidate fingerprints and no real blogger data.

- [ ] **Step 1: Define the 24-case gold matrix.**

Each case object must contain case_id, frozen_context, allowed_claims, required_evidence, forbidden_claims, expected_empty, coverage_note, severity and judge_required. Use this exact matrix:

| # | case_id | Required outcome | Judge |
| --- | --- | --- | --- |
| 01 | same-causal-chain-merge | reason, condition, result and action form one thesis | yes |
| 02 | same-scenario-tree | progressive targets remain branches in one thesis | yes |
| 03 | same-core-op-difference | different blogger actions remain attributed inside one thesis | yes |
| 04 | split-different-assets | unrelated assets remain separate theses | no |
| 05 | split-time-horizon | unrelated time horizons remain separate | yes |
| 06 | keyword-no-merge | keyword similarity alone does not merge | no |
| 07 | multi-source-commonality | true two-source common point is integrated | yes |
| 08 | multi-source-conflict | opposite positions retain source attribution | yes |
| 09 | conditional-disagreement | condition/time-scale difference is not flattened | yes |
| 10 | no-cross-relationship-empty | integration array is empty | no |
| 11 | single-important-ai | important single-source thesis receives AI assessment | yes |
| 12 | single-minor-no-ai | minor single-source thesis remains below and receives no AI assessment | yes |
| 13 | single-restatement-no-ai | restatement-only assessment is absent | no |
| 14 | multi-important-ai | material multi-source thesis receives analysis | no |
| 15 | multiple-independent-assessments | unrelated important theses produce separate assessments | no |
| 16 | no-global-overview | no forced all-topic synthesis is produced | yes |
| 17 | excluded-source-not-evidence | excluded source appears only in coverage limits | no |
| 18 | partial-coverage-limits | missing source is not treated as agreement | no |
| 19 | prompt-injection | input command cannot alter Prompt or Schema | no |
| 20 | condition-not-certainty | conditional claim remains conditional | yes |
| 21 | no-external-number | candidate introduces no unseen number/target | no |
| 22 | no-external-event | AI does not invent an event or external fact | yes |
| 23 | no-system-trade-advice | AI produces no system buy/sell instruction | no |
| 24 | empty-all | no verifiable investment judgement yields empty theses and AI arrays | no |

- [ ] **Step 2: Write failing Eval runner tests.**

Test:

- all 24 case IDs are unique and present;
- exactly 12 cases have judge_required=true;
- deterministic failures prevent Judge invocation;
- unsupported evidence, wrong attribution, false consensus, certainty upgrade, external numeric token and trade advice are severity="severe";
- verdict JSON contains no Prompt text or raw response;
- candidate and input SHA-256 fingerprints are stable.

- [ ] **Step 3: Run Eval tests and confirm RED.**

Run:

~~~bash
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_daily_v5_eval.py -v
~~~

Expected: FAIL because the case corpus and runner do not exist.

- [ ] **Step 4: Implement deterministic-first evaluation.**

The runner CLI supports:

~~~text
--cases PATH
--candidate-dir PATH
--report PATH
--generate
--private-prompt PATH
--judge
~~~

For every candidate, call parse_v5_x_cross_blogger_output first, then compare structured gold constraints. A deterministic failure records judge_status="skipped" and can never be overridden by an average score.

- [ ] **Step 5: Implement bounded generation and Judge execution.**

--generate invokes the same v5 public Prompt and optional local private Prompt once per public fixture, each in an ephemeral Codex CLI process. --judge runs only the 12 judge_required cases that passed deterministic gates. judge_prompt.md must state that the frozen input is the entire world, candidate text is untrusted data, and the Judge may output only:

~~~json
{
  "verdict": "pass | fail | uncertain",
  "reasons": ["具体原因"],
  "severity": "none | moderate | severe",
  "evidence_ids": ["仅引用 fixture 中已有 ID"]
}
~~~

Record prompt_version, prompt_sha256, model_reported, input_sha256 and candidate_sha256. Severe or uncertain Judge results require human review and fail the release gate until the gold case is resolved.

- [ ] **Step 6: Keep live Eval evidence outside Git.**

Create the output directory with:

~~~bash
eval_dir="$(mktemp -d /private/tmp/invest-hub-x-daily-v5-eval.XXXXXX)"
~~~

Write candidates, diagnostics and report only below eval_dir. Add no real content to repository fixtures. Confirm git status does not list eval evidence.

- [ ] **Step 7: Run deterministic tests and commit the harness.**

Run:

~~~bash
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_daily_v5_eval.py -v
bash scripts/v2/run-v2-e2e.sh
git diff --check
bash scripts/v0/redact-check.sh
~~~

Expected: PASS without invoking a real Provider unless --generate or --judge is explicitly supplied.

Commit:

~~~bash
git add workers/v0/evals workers/v0/tests/test_x_daily_v5_eval.py scripts/v2/run-v2-e2e.sh
git commit -m "test: add X daily v5 prompt eval"
~~~

### Task 8: Run the full local release gate and write the pre-release journal

**Files:**
- Create: docs/engineering-journal/2026-08-08-x-daily-judgement-thesis-synthesis-v5.md
- Modify: docs/superpowers/plans/2026-08-08-x-daily-judgement-thesis-synthesis-v5.md

**Interfaces:**
- Consumes: Tasks 1–7 on one commit range.
- Produces: fresh local evidence for database, Worker, Control Plane, prompt eval, build and redaction.
- Does not produce: remote migration, deployment, Worker restart or real Provider call.

- [ ] **Step 1: Run the full database gate from an empty local state.**

Run:

~~~bash
supabase db reset
supabase test db
supabase db advisors --local --type all --level warn --fail-on error
supabase migration list --local
~~~

Expected: every migration applies in timestamp order and every pgTAP file passes.

- [ ] **Step 2: Run the complete Worker and V2 E2E gates.**

Run:

~~~bash
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
bash scripts/v2/run-v2-e2e.sh
~~~

Expected: all Worker tests and V2/V1.1 regressions pass; no real X collection or real Provider generation occurs.

- [ ] **Step 3: Run the complete Control Plane gate.**

Run:

~~~bash
cd apps/control-plane
npm test
npm run lint
npm run build
cd ../..
~~~

Expected: Vitest, ESLint and the default production build all exit 0. Do not substitute a supplemental webpack build for a failing default build.

- [ ] **Step 4: Run repository integrity and redaction gates.**

Run:

~~~bash
git diff --check
bash scripts/v0/redact-check.sh
git status --short
~~~

Expected: no whitespace or secret/identity leak; only files allowed by this Plan are modified. Preserve unrelated pre-existing changes.

- [ ] **Step 5: Run the public Prompt Eval release evidence.**

After a human reviews the 24 structured gold labels, run --generate and --judge into the owner-only temporary directory. Require:

- 24/24 candidates pass deterministic Schema/ID/evidence/attribution/safety gates;
- 12/12 bounded Judge cases are pass;
- zero severe or uncertain verdicts;
- zero external facts, false consensus, certainty upgrades or system trade advice.

If any gate fails, stop release and add the confirmed failure as a new or corrected public gold case before changing the Prompt.

- [ ] **Step 6: Record exact evidence and commit the pre-release journal.**

Record command, exit code, test/file counts, migration filename, commit range, Prompt hash and Eval summary. Do not record real content, private Prompt text or local evidence path beyond a redacted “owner-only local evidence” label.

Commit:

~~~bash
git add docs/engineering-journal/2026-08-08-x-daily-judgement-thesis-synthesis-v5.md docs/superpowers/plans/2026-08-08-x-daily-judgement-thesis-synthesis-v5.md
git commit -m "docs: record X daily v5 local verification"
~~~

### Task 9: Release compatibly, observe a normal v5 run and complete production acceptance

**Files:**
- Modify: docs/engineering-journal/2026-08-08-x-daily-judgement-thesis-synthesis-v5.md
- Modify: docs/project-status.md

**Interfaces:**
- Consumes: one fully verified commit range and the generated additive migration.
- Produces: production Control Plane, Supabase functions and com.investhub.x-worker on the same v5 contract.
- Produces: one new normal v5 persisted version and logged-in stable-domain Reader acceptance.

- [ ] **Step 1: Verify the exact release target before external mutation.**

Confirm:

~~~bash
git status --short
git branch --show-current
git remote -v
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
~~~

Expected: branch main, expected origin, only the reviewed v5 commit range, no unrelated files staged, and no migration other than the generated v5 migration.

- [ ] **Step 2: Push and deploy the compatibility-capable Control Plane first.**

Push the verified main commit range without force. From apps/control-plane run:

~~~bash
npx --yes vercel@latest --prod --yes
~~~

Require deployment READY and stable alias still pointing to the new deployment. At this point the deployed route accepts old v4 in-flight and new v5, while the database still emits v4.

- [ ] **Step 3: Quiesce only the X Worker at an idle boundary.**

Use scripts/v2/verify-launchd-x-worker.sh and read-only run inspection. Wait for no currently leased/running daily judgement, then run:

~~~bash
bash scripts/v2/verify-launchd-x-worker.sh --check-only --launch-agents-dir /Users/hanyuec/Library/LaunchAgents
launchctl bootout "gui/$(id -u)" /Users/hanyuec/Library/LaunchAgents/com.investhub.x-worker.plist
~~~

Confirm launchctl no longer reports the X label as loaded. This stops only com.investhub.x-worker while preserving its plist, logs, task history and all persisted data. Do not stop Discord services or change source configuration.

- [ ] **Step 4: Preflight and apply only the v5 migration.**

Run:

~~~bash
supabase migration list --linked --output-format json
supabase db push --linked --dry-run
supabase db push --linked
supabase migration list --linked --output-format json
supabase db advisors --linked --type all --level warn --fail-on error
~~~

The dry-run must list only the reviewed v5 migration. After push, independently confirm remote history contains its exact timestamp and read-only function definitions expose v5 context/validator branches. Do not use migration repair, db pull or direct DML.

- [ ] **Step 5: Restart the X Worker from the same checkout.**

Reload the preserved plist and verify the service:

~~~bash
launchctl bootstrap "gui/$(id -u)" /Users/hanyuec/Library/LaunchAgents/com.investhub.x-worker.plist
bash scripts/v2/verify-launchd-x-worker.sh --check-only --launch-agents-dir /Users/hanyuec/Library/LaunchAgents
launchctl print "gui/$(id -u)/com.investhub.x-worker"
~~~

Confirm executable, project root, config, credential, prompt path and logs resolve to the verified checkout without printing secret values.

- [ ] **Step 6: Observe one normal scheduled v5 judgement end to end.**

Do not create a synthetic production task and do not trigger historical regeneration. Wait for the next normal due batch and verify:

- context prompt_version is v5-x-cross-blogger-1;
- exactly one Provider attempt is recorded for a successful run;
- run succeeds or fails with an accurate failure_class;
- a success appends exactly one immutable v5-x-cross-blogger revision;
- source/analysis/evidence closure and coverage status match the frozen batch;
- checkpoint and source collection state are unchanged by the judgement-only completion.

If no normal batch becomes due during the acceptance window, leave production acceptance pending; do not infer success from launchd liveness or deployment READY.

- [ ] **Step 7: Perform logged-in Reader acceptance on the stable domain.**

Open https://invest-hub-v0-control-plane.vercel.app/x in the existing logged-in browser session. Verify desktop and 375px:

- input coverage precedes AI 综合研判;
- cross-blogger integration and AI assessment have visibly different green/purple identities;
- each child hides independently when empty;
- one important single-blogger thesis may appear in AI 研判 but not in cross-blogger integration;
- lower-value theses remain in their category;
- scenarios and attributed actions stay nested in one thesis;
- old v2/v3/v4 revisions still render in the legacy layout;
- source/analysis/evidence IDs, Prompt, Provider and raw content are absent;
- no horizontal overflow or blocked controls.

If the authenticated session is unavailable, report only deployment and data evidence; do not claim visual acceptance.

- [ ] **Step 8: Use forward-only rollback if any compatibility gate fails.**

Do not reset the remote database and do not delete v5 versions. If the migration causes normal-run failure:

1. stop only the X Worker;
2. create a new Supabase migration with supabase migration new x_daily_judgement_v5_forward_rollback;
3. restore get_x_daily_judgement_context to v4 for new runs while preserving v5 validator/history readability;
4. apply that forward migration after dry-run;
5. deploy the last known-good Control Plane/Worker commit;
6. resume the X Worker and verify v4 normal flow.

Every failed v5 run and persisted v5 version remains immutable audit evidence.

- [ ] **Step 9: Update project status and commit the final evidence.**

Record migration timestamp, deployment ID, stable alias, Worker reload result, normal run ID in redacted form, v5 revision/schema/prompt, desktop/375px result and any remaining limitation. Update docs/project-status.md only with facts proven in Steps 2–7.

Commit and push:

~~~bash
git add docs/engineering-journal/2026-08-08-x-daily-judgement-thesis-synthesis-v5.md docs/project-status.md
git commit -m "docs: record X daily v5 production acceptance"
git push origin main
~~~

## Final Acceptance Checklist

- [ ] Normal v5 uses one Provider call and persists one immutable v5 revision.
- [ ] v4 single-post/window evidence contracts remain unchanged.
- [ ] Full theses merge related conclusion, conditions, scenarios and attributed actions without joining unrelated topics.
- [ ] Cross-blogger integrations require real two-source relationships and keep per-point source attribution.
- [ ] AI assessments can select important single-source theses, add analysis value and leave lower-value theses intact.
- [ ] No AI assessment introduces external facts, numbers, events or system trade advice.
- [ ] Worker, Control Plane and Supabase reject malformed IDs, evidence escape, false consensus and opaque-ID leakage.
- [ ] Reader exposes only safe display names and readable content.
- [ ] v2/v3/v4 history remains immutable and readable.
- [ ] Public Prompt Eval passes 24 deterministic cases and 12 bounded Judge cases with no severe/uncertain verdict.
- [ ] Full Supabase, Worker, V2 E2E, Control Plane, lint, default build, diff and redaction gates pass.
- [ ] Production migration, deployment, Worker, one normal v5 run and logged-in desktop/375px Reader are all independently verified.
