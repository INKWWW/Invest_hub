# Spike-02 免费 LLM 容量与质量验证 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立一个仅使用 Python 标准库的本地 Spike-02 harness，测量 GLM 在小批次、约 500 条和 1000 条以上 Discord fixture 上的容量、结构化输出稳定性、质量和局部恢复能力。

**Architecture:** Spike-02 独立创建 `spikes/spike_02/`，不修改 Spike-01 的实现。Fixture loader、确定性 chunker、Provider contract、JSON/Schema validator、重试 runner、质量评估器和本地 evidence store 分开负责；Mock Provider 用于确定性失败注入，GLM Provider 只通过本地环境配置进行真实 HTTP 请求。

**Tech Stack:** Python 3.11+ 标准库；`unittest`；`urllib.request`；JSON/JSONL 本地 evidence；不安装生产依赖，不使用 Codex CLI，不创建云端资源。

## Global Constraints

- 当前仍处于 Discovery；实现前必须先批准本计划，Spike-02 结果不批准 V0/V1 生产架构。
- GLM 是本 Spike 唯一真实 Provider；Mock 只负责确定性契约和失败恢复；Codex CLI 不执行。
- 真实 fixture、API key、完整响应、Prompt 正文和历史数据只能写入本地受保护目录，不进入 Git。
- 公开 fixture 必须人工构造；1000 条以上的公开规模数据只用于容量测试，不用于质量结论。
- 确定性去重、排序、作者标记、回复关系、Ticker/价格/URL 提取和输入范围记录由程序完成。
- 重试只作用于失败 chunk；默认最多三次尝试，有界退避；已完成 chunk 不重复调用。
- 输出质量必须可回指 fixture 消息 ID；严重错误归因和未解析媒体臆测为阻断级错误。
- 继续沿用 intake 初始门槛：首次请求成功率 >=90%、重试后最终成功率 >=99%、JSON 可解析率 >=98%、核心事实有据率 >=95%、严重错误归因 0、媒体臆测 0。
- 每个任务完成后运行该任务的测试并单独提交，提交信息使用 `spike: ...` 或 `docs: ...` 前缀。

---

## File Map

创建以下 Spike-02 文件：

- `spikes/spike_02/__init__.py`：包标记，不包含运行逻辑。
- `spikes/spike_02/model.py`：fixture、chunk、Provider response、结构化输出和报告数据模型。
- `spikes/spike_02/fixtures.py`：公开 fixture 读取、校验和规模 fixture 生成。
- `spikes/spike_02/chunking.py`：连续输入块构造和回复上下文保留。
- `spikes/spike_02/schema.py`：严格 JSON 解析、最小 Schema 校验和有限程序修复。
- `spikes/spike_02/providers.py`：Provider Protocol、Mock Provider、GLM HTTP Provider。
- `spikes/spike_02/evidence.py`：安全请求遥测、结构化结果、原始响应和指标的本地持久化。
- `spikes/spike_02/runner.py`：单 chunk 重试、截断拆分、批次运行和汇总指标。
- `spikes/spike_02/evaluation.py`：人工标注对照、质量评分和初始门槛判定。
- `spikes/spike_02/cli.py`：Mock/GLM 运行入口和参数校验。
- `spikes/spike_02/README.md`：本地运行、环境变量和安全边界。
- `spikes/spike_02/fixtures/public_small.json`：人工构造、带质量标注的小型 fixture。
- `spikes/spike_02/tests/`：每个边界的确定性单元测试。

修改以下文件：

- `.gitignore`：忽略 Spike-02 私有输入、证据和真实运行报告。

在真实 GLM 运行完成后创建：

- `docs/spikes/2026-07-15-spike-02-decision-report.md`：只记录脱敏指标、质量结论、限制和下一阶段建议。

---

## Task 1: 建立数据模型与公开 Fixture

**Files:**

- Create: `spikes/spike_02/__init__.py`
- Create: `spikes/spike_02/model.py`
- Create: `spikes/spike_02/fixtures.py`
- Create: `spikes/spike_02/fixtures/public_small.json`
- Create: `spikes/spike_02/tests/__init__.py`
- Create: `spikes/spike_02/tests/test_fixtures.py`

**Interfaces:**

- Produces `FixtureCase`, `FixtureMessage`, `ExpectedClaim`, `Scale`, `ProviderName` and `load_fixture(path)`。
- Later tasks consume `FixtureCase.messages` 的稳定顺序、`FixtureCase.claims` 的质量标注以及 `FixtureMessage.parent_id`。

- [ ] **Step 1: 写失败测试，锁定 fixture 结构和安全校验**

在 `test_fixtures.py` 中覆盖：

```python
def test_load_fixture_preserves_order_and_claim_sources():
    case = load_fixture(Path("spikes/spike_02/fixtures/public_small.json"))
    self.assertEqual(case.scale, "small")
    self.assertEqual([m.message_id for m in case.messages], [
        "public-001", "public-002", "public-003", "public-004",
    ])
    self.assertIn("public-001", case.claims[0].source_message_ids)

def test_duplicate_message_ids_are_rejected():
    path = write_fixture_with_duplicate_id()
    with self.assertRaisesRegex(FixtureError, "duplicate message_id"):
        load_fixture(path)

def test_claim_source_must_reference_fixture_message():
    path = write_fixture_with_unknown_claim_source()
    with self.assertRaisesRegex(FixtureError, "unknown source_message_id"):
        load_fixture(path)
```

运行：

```bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_fixtures -v
```

预期：初次运行因模块和 fixture 尚不存在而失败。

- [ ] **Step 2: 实现最小模型**

`model.py` 使用冻结 dataclass，字段固定如下：

```python
from dataclasses import dataclass
from typing import Literal

Scale = Literal["small", "medium", "large"]
ProviderName = Literal["mock", "glm"]
MessageKind = Literal["text", "unparsed_media"]

@dataclass(frozen=True)
class FixtureMessage:
    message_id: str
    author_id: str
    author_scope: Literal["target", "other"]
    published_at: str
    content: str
    kind: MessageKind
    parent_id: str | None

@dataclass(frozen=True)
class ExpectedClaim:
    claim_id: str
    category: Literal["fact", "target_viewpoint", "ticker", "operation_tendency", "context"]
    required_terms: tuple[str, ...]
    source_message_ids: tuple[str, ...]
    target_author_id: str | None
    forbidden_terms: tuple[str, ...]

@dataclass(frozen=True)
class FixtureCase:
    case_id: str
    scale: Scale
    messages: tuple[FixtureMessage, ...]
    claims: tuple[ExpectedClaim, ...]

@dataclass(frozen=True)
class Chunk:
    chunk_id: str
    case_id: str
    index: int
    primary_message_ids: tuple[str, ...]
    context_message_ids: tuple[str, ...]
    prompt_text: str
    input_chars: int

@dataclass(frozen=True)
class LLMRequest:
    run_id: str
    chunk: Chunk
    attempt: int
    prompt_version: str

@dataclass(frozen=True)
class ProviderResponse:
    status: str
    content: str | None
    latency_ms: int
    input_tokens: int | None
    output_tokens: int | None
    finish_reason: str | None
    error_code: str | None

@dataclass(frozen=True)
class StructuredTopic:
    title: str
    summary: str
    source_message_ids: tuple[str, ...]
    author_scope: str
    author_id: str | None
    tickers: tuple[str, ...]
    operation_tendency: str | None
    uncertainty: str | None

@dataclass(frozen=True)
class StructuredOutput:
    topics: tuple[StructuredTopic, ...]
    media_unparsed: bool
    warnings: tuple[str, ...]

@dataclass(frozen=True)
class ChunkResult:
    chunk_id: str
    status: str
    attempts: int
    output: StructuredOutput | None
    error_code: str | None

@dataclass(frozen=True)
class QualityReport:
    covered_claims: int
    grounded_claims: int
    attributed_claims: int
    required_claims: int
    severe_attribution_errors: int
    media_hallucinations: int

@dataclass(frozen=True)
class RunReport:
    run_id: str
    provider: ProviderName
    case_id: str
    chunk_size: int
    request_count: int
    retry_count: int
    first_success_rate: float
    final_success_rate: float
    json_parse_rate: float
    p50_latency_ms: int
    p95_latency_ms: int
    primary_message_ids: tuple[str, ...]
    results: tuple[ChunkResult, ...]
```

- [ ] **Step 3: 实现 fixture loader 和公开小 fixture**

`public_small.json` 至少包含 12 条不重复的人工消息，覆盖：多话题、指定用户短句、回复链、中英文、Ticker、价格和 `unparsed_media`。标注至少 5 条 `ExpectedClaim`，其中包含一个禁止归因和一个媒体禁止臆测。

`load_fixture(path)` 必须：

1. 解析 JSON 对象；
2. 校验 `case_id`、`scale`、消息字段和 claim 字段；
3. 保持 JSON 中的消息顺序；
4. 拒绝重复消息 ID；
5. 拒绝不存在的 `parent_id`；
6. 拒绝 claim 引用不存在的消息 ID；
7. 拒绝空内容但允许 `unparsed_media` 使用明确的媒体占位文本。

运行同一测试，预期全部 PASS。

- [ ] **Step 4: 提交独立变更**

```bash
git add spikes/spike_02
git commit -m "spike: add Spike-02 fixture models"
```

## Task 2: 实现确定性 Chunker 与结构化输出 Schema

**Files:**

- Create: `spikes/spike_02/chunking.py`
- Create: `spikes/spike_02/schema.py`
- Create: `spikes/spike_02/tests/test_chunking.py`
- Create: `spikes/spike_02/tests/test_schema.py`

**Interfaces:**

- Consumes: Task 1 的 `FixtureCase`。
- Produces: `build_chunks(case, max_primary_messages, context_limit=2)`、`parse_structured_output(text)`、`validate_structured_output(output, input_message_ids, target_author_ids)`。

- [ ] **Step 1: 写 chunk 和 Schema 失败测试**

测试必须锁定：

```python
def test_chunks_preserve_primary_order_without_loss():
    chunks = build_chunks(case, max_primary_messages=3)
    primary_ids = tuple(
        message_id
        for chunk in chunks
        for message_id in chunk.primary_message_ids
    )
    self.assertEqual(primary_ids, tuple(m.message_id for m in case.messages))

def test_reply_parent_outside_chunk_is_context_only():
    chunks = build_chunks(case_with_long_reply_chain(), max_primary_messages=2)
    self.assertIn("public-001", chunks[1].context_message_ids)
    self.assertNotIn("public-001", chunks[1].primary_message_ids)

def test_schema_rejects_unknown_source_message_id():
    with self.assertRaisesRegex(SchemaError, "source_message_ids"):
        validate_structured_output(
            parse_structured_output(valid_json_with_source("missing")),
            {"public-001"},
            {"target-user"},
        )

def test_program_repair_only_removes_json_fence():
    output = parse_structured_output("```json\n{}\n```")
    self.assertEqual(output.topics, ())
```

运行两个测试模块，预期初次失败。

- [ ] **Step 2: 实现 chunker**

`build_chunks` 按发布时间和 fixture 顺序切分；每个 chunk 的 primary 消息数量不超过 `max_primary_messages`。对每条 primary 消息：

- 如果 `parent_id` 在当前 chunk 外，加入 `context_message_ids`；
- 额外保留最多 `context_limit` 条前序消息作为上下文；
- context 消息不得从 primary 序列中删除，也不得改变 primary 的顺序；
- `prompt_text` 只包含 message ID、作者 scope、时间、正文和回复关系，不包含任何 API 凭据；
- `chunk_id` 使用 `f"{case.case_id}-{index:04d}"`，保证同一输入和 chunk size 下稳定。

提供 `split_chunk(chunk)`：对超过一条 primary 消息的 chunk 按中点拆分，子 chunk 的 primary ID 不重叠且合并后等于父 chunk。

- [ ] **Step 3: 实现严格 JSON 解析和最小 Schema**

LLM JSON 顶层契约固定为：

```json
{
  "topics": [
    {
      "title": "string",
      "summary": "string",
      "source_message_ids": ["message-id"],
      "author_scope": "target|channel",
      "author_id": "string|null",
      "tickers": ["ABC"],
      "operation_tendency": "string|null",
      "uncertainty": "string|null"
    }
  ],
  "media_unparsed": false,
  "warnings": ["string"]
}
```

`parse_structured_output` 先使用 `json.loads`；只允许去除一层 ` ```json ... ``` ` 包裹，不做任意文本截取或猜测性修复。`validate_structured_output` 校验：

- 顶层字段和类型；
- 每个 topic 必填字段；
- source ID 属于当前 primary/context 输入；
- `author_scope=target` 时 `author_id` 非空且属于 target author 集合；
- `media_unparsed` 为布尔值；
- 不允许空 source ID。

解析失败、Schema 失败和非法引用必须分别抛出带稳定 error code 的 `SchemaError`。

- [ ] **Step 4: 运行测试并提交**

```bash
PYTHONPATH=spikes python3 -m unittest \
  spikes.spike_02.tests.test_chunking \
  spikes.spike_02.tests.test_schema -v
```

预期：全部 PASS。

```bash
git add spikes/spike_02/chunking.py spikes/spike_02/schema.py spikes/spike_02/tests
git commit -m "spike: add Spike-02 chunk and schema boundaries"
```

## Task 3: 实现 Mock 与 GLM Provider Contract

**Files:**

- Create: `spikes/spike_02/providers.py`
- Create: `spikes/spike_02/tests/test_providers.py`

**Interfaces:**

- Consumes: Task 1 的 `LLMRequest`、`ProviderResponse`。
- Produces: `LLMProvider` Protocol、`MockProvider`、`GLMProvider` 和 `ProviderError`。

- [ ] **Step 1: 写 Provider 失败测试**

覆盖以下确定性行为：

```python
def test_mock_returns_scripted_json_and_counts_calls():
    provider = MockProvider({"case-0000": [MockOutcome.success(valid_json)]})
    response = provider.complete(request_for("case-0000"))
    self.assertEqual(response.status, "success")
    self.assertEqual(provider.call_count, 1)

def test_mock_can_inject_timeout_then_success():
    provider = MockProvider({
        "case-0000": [
            MockOutcome.failure("timeout"),
            MockOutcome.success(valid_json),
        ]
    })
    self.assertEqual(provider.complete(request_for("case-0000")).status, "timeout")
    self.assertEqual(provider.complete(request_for("case-0000")).status, "success")

def test_glm_maps_http_429_to_rate_limited_without_leaking_key():
    provider = GLMProvider(endpoint="https://glm.example.test", api_key="secret", model="glm-test", opener=raising_429_opener)
    response = provider.complete(request_for("case-0000"))
    self.assertEqual(response.status, "rate_limited")
    self.assertNotIn("secret", str(response))
```

- [ ] **Step 2: 实现 Mock Provider**

`MockOutcome` 只支持 `success(content)`, `failure(status, error_code=None)` 和 `truncated(content)`。`MockProvider` 按 `chunk_id` 保存有序 outcome；超出脚本长度时返回 `provider_script_exhausted`，不隐式生成成功结果。每次调用记录 `call_count` 和 request ID，但不记录 prompt 正文。

- [ ] **Step 3: 实现 GLM HTTP Provider**

`GLMProvider(endpoint, api_key, model, opener=urlopen)` 使用 `urllib.request.Request` 发送 JSON POST。请求体使用以下稳定的 Spike 契约：

```python
{
    "model": self.model,
    "messages": [{"role": "user", "content": request.chunk.prompt_text}],
    "temperature": 0,
    "response_format": {"type": "json_object"},
}
```

认证只从运行时 `api_key` 传入 `Authorization: Bearer ...`，不得写入模型、日志或 evidence。响应读取 `choices[0].message.content`，使用 `usage.prompt_tokens` 和 `usage.completion_tokens`（不存在则为 `None`）；`finish_reason=length` 映射为 `truncated`。

错误映射固定为：

- `HTTP 408/429`、`URLError`、socket timeout：`timeout` 或 `rate_limited`，可重试；
- `HTTP 500/502/503/504`：`provider_unavailable`，可重试；
- 其他 `HTTP 4xx`：`provider_rejected`，不可重试；
- 响应 JSON 缺少 content：`invalid_provider_response`，可记录但不可伪造成功。

请求 timeout 从 `GLMProvider(timeout_seconds=30)` 传入，不在代码中无限等待。原始响应只返回给 runner 的本地 evidence 层，不写入安全遥测。

- [ ] **Step 4: 运行测试并提交**

```bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_providers -v
```

预期：全部 PASS，且测试只使用 fake opener，不访问网络。

```bash
git add spikes/spike_02/providers.py spikes/spike_02/tests/test_providers.py
git commit -m "spike: add Mock and GLM provider contracts"
```

## Task 4: 实现 Evidence Store 与有界 Runner

**Files:**

- Create: `spikes/spike_02/evidence.py`
- Create: `spikes/spike_02/runner.py`
- Create: `spikes/spike_02/tests/test_runner.py`
- Create: `spikes/spike_02/tests/test_evidence.py`

**Interfaces:**

- Consumes: Task 1 的 models、Task 2 的 chunk/schema、Task 3 的 Provider Protocol。
- Produces: `EvidenceStore`, `RunConfig`, `run_case(case, provider, config, evidence) -> RunReport`。

- [ ] **Step 1: 写失败测试，锁定局部恢复和安全 evidence**

覆盖：

```python
def test_failed_chunk_retries_without_recalling_completed_chunk():
    provider = scripted_timeout_then_success_provider()
    report = run_case(case, provider, RunConfig(max_primary_messages=3, max_attempts=3), evidence)
    self.assertEqual(report.final_success_rate, 1.0)
    self.assertEqual(provider.calls_for("case-0000"), 2)
    self.assertEqual(provider.calls_for("case-0001"), 1)

def test_truncated_chunk_splits_and_preserves_primary_ids():
    provider = scripted_truncated_then_success_children_provider()
    report = run_case(case, provider, RunConfig(max_primary_messages=4), evidence)
    self.assertEqual(report.final_success_rate, 1.0)
    self.assertEqual(set(report.primary_message_ids), {m.message_id for m in case.messages})

def test_safe_request_record_contains_metadata_but_not_prompt_or_key():
    evidence.persist_request(request, response)
    payload = json.loads((root / "requests.jsonl").read_text().splitlines()[0])
    self.assertNotIn("prompt_text", payload)
    self.assertNotIn("api_key", payload)
    self.assertEqual(payload["chunk_id"], request.chunk.chunk_id)
```

- [ ] **Step 2: 实现 EvidenceStore**

目录结构固定为：

```text
<evidence-root>/
├── requests.jsonl
├── results.jsonl
├── metrics.json
└── raw_responses/<request-id>.json
```

`persist_request` 只写 run ID、provider、case ID、chunk ID、attempt、status、latency、token usage 和 error code。`persist_result` 写经过 Schema 校验的结构化结果；`persist_raw_response` 只写 evidence root 下的原始响应。所有写入使用 UTF-8、`ensure_ascii=False`、flush 和 fsync，失败抛出 `EvidenceError`。

- [ ] **Step 3: 实现 runner**

`RunConfig` 固定字段：

```python
@dataclass(frozen=True)
class RunConfig:
    max_primary_messages: int
    context_limit: int = 2
    max_attempts: int = 3
    prompt_version: str = "spike-02-v1"
    retry_delays_seconds: tuple[float, ...] = (1.0, 2.0)
```

`run_case` 流程：

1. 用 `build_chunks` 生成稳定 chunk；
2. 对每个 chunk 从 attempt 1 开始请求；
3. 成功后严格解析并校验 JSON，写 request/result evidence；
4. timeout、rate limit、provider unavailable、invalid JSON 和 Schema error 只重试当前 chunk；
5. 重试前调用可注入 `sleep`，单元测试传入空函数，真实运行使用 `retry_delays_seconds`；
6. truncated 且 primary 消息多于一条时调用 `split_chunk`，将子 chunk 作为新的局部工作项；
7. 已完成 chunk 不重复调用；
8. 汇总首次成功率、最终成功率、JSON 解析率、请求次数、重试次数、P50/P95 latency 和所有 `ChunkResult`。

P95 使用排序后 `ceil(0.95 * n) - 1` 的索引，空 latency 集合返回 0。质量错误只记录，不由 runner 自动伪造修复成功。

- [ ] **Step 4: 运行测试并提交**

```bash
PYTHONPATH=spikes python3 -m unittest \
  spikes.spike_02.tests.test_runner \
  spikes.spike_02.tests.test_evidence -v
```

预期：全部 PASS，并确认没有真实网络请求。

```bash
git add spikes/spike_02/evidence.py spikes/spike_02/runner.py spikes/spike_02/tests
git commit -m "spike: add bounded LLM runner and evidence"
```

## Task 5: 实现质量评估与门槛判定

**Files:**

- Create: `spikes/spike_02/evaluation.py`
- Create: `spikes/spike_02/tests/test_evaluation.py`

**Interfaces:**

- Consumes: `FixtureCase`, `StructuredOutput`, runner results。
- Produces: `evaluate_output(case, output) -> QualityReport`、`evaluate_review_sheet(path) -> QualityReport`、`classify_run(reports, quality, has_real_glm_evidence, constrained) -> Literal["pass", "conditional_pass", "fail", "unverified"]`。

- [ ] **Step 1: 写失败测试**

覆盖：

```python
def test_claim_is_grounded_only_when_source_ids_and_terms_match():
    report = evaluate_output(case, output_with_claim("观点 ABC", ["public-001"]))
    self.assertEqual(report.grounded_claims, 1)

def test_wrong_target_author_is_severe_attribution_error():
    report = evaluate_output(case, output_attributed_to_wrong_author())
    self.assertEqual(report.severe_attribution_errors, 1)

def test_media_hallucination_is_blocking():
    report = evaluate_output(case_with_unparsed_media, output_with_media_details())
    self.assertEqual(report.media_hallucinations, 1)

def test_threshold_classifier_returns_conditional_pass_for_capacity_limit():
    decision = classify_run(
        (report_with_valid_quality_but_large_chunk_failure,),
        quality_pass,
        has_real_glm_evidence=True,
        constrained=True,
    )
    self.assertEqual(decision, "conditional_pass")
```

- [ ] **Step 2: 实现可自动校验的质量部分**

`evaluate_output` 不做开放式语义判断，只做可审计检查：

- claim 的 required terms 是否出现在 topic title/summary/fields；
- source IDs 是否覆盖该 claim 的标注来源；
- target claim 的 `author_scope` 和 `author_id` 是否正确；
- forbidden terms 是否出现在媒体未解析内容的结论中；
- 不允许将普通用户 source ID 标记为 target author。

人工质量表使用 JSONL，每行字段为：`case_id`、`claim_id`、`covered`、`grounded`、`correct_attribution`、`media_hallucination`、`note`。`evaluate_review_sheet` 只接受 `true/false` 布尔值，拒绝缺少 claim 的记录。

- [ ] **Step 3: 实现初始门槛和结论分类**

使用常量：

```python
INITIAL_THRESHOLDS = {
    "first_success_rate": 0.90,
    "final_success_rate": 0.99,
    "json_parse_rate": 0.98,
    "grounded_rate": 0.95,
    "severe_attribution_errors": 0,
    "media_hallucinations": 0,
}
```

分类规则：

1. `has_real_glm_evidence=False` 时返回 `unverified`；
2. 有任一阻断级错误或任一规模最终成功率低于门槛时返回 `fail`；
3. 质量门槛满足但 `constrained=True` 时返回 `conditional_pass`；
4. `reports` 覆盖三档规模、所有门槛满足且没有约束时返回 `pass`。

- [ ] **Step 4: 运行测试并提交**

```bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_evaluation -v
```

预期：全部 PASS。

```bash
git add spikes/spike_02/evaluation.py spikes/spike_02/tests/test_evaluation.py
git commit -m "spike: add LLM quality evaluation gates"
```

## Task 6: 增加 CLI、规模输入和安全运行说明

**Files:**

- Modify: `.gitignore`
- Modify: `spikes/spike_02/fixtures.py`
- Create: `spikes/spike_02/cli.py`
- Create: `spikes/spike_02/README.md`
- Create: `spikes/spike_02/tests/test_cli.py`

**Interfaces:**

- Consumes: Tasks 1–5 的 loader、Provider、runner 和 evaluator。
- Produces: `python3 -m spike_02.cli mock ...`、`python3 -m spike_02.cli glm ...` 和 `python3 -m spike_02.cli evaluate ...` 三条本地命令。

- [ ] **Step 1: 写 CLI 失败测试**

```python
def test_mock_cli_requires_fixture_and_evidence_dir():
    self.assertEqual(main(["mock"]), 2)

def test_glm_cli_requires_runtime_environment(monkeypatch):
    clear_env("SPIKE02_GLM_API_KEY", "SPIKE02_GLM_ENDPOINT", "SPIKE02_GLM_MODEL")
    self.assertEqual(main(["glm", "--fixture", fixture_path, "--evidence-dir", evidence_dir]), 2)

def test_mock_cli_runs_without_network():
    code = main(["mock", "--fixture", fixture_path, "--evidence-dir", evidence_dir, "--chunk-size", "3"])
    self.assertEqual(code, 0)
```

- [ ] **Step 2: 实现公开规模 fixture 生成**

在 `fixtures.py` 增加 `build_synthetic_scale_case(case_id, count)`：

- `count` 必须是 500 或 1000 以上；
- 每条消息使用唯一 ID、递增时间和可变的公开主题词；
- 每 10 条消息至少包含一个回复关系；
- 每 25 条消息轮换语言、Ticker 和内容类型；
- 生成结果标记为 `claims=()`，只能用于容量指标，不得进入质量评分。

这条路径不复制同一 message ID，也不将合成规模数据当作真实质量证据。

- [ ] **Step 3: 实现 CLI 和环境变量校验**

CLI 子命令参数固定：

```text
mock|glm
--fixture PATH
--evidence-dir PATH
--chunk-size INT
--max-attempts INT (default 3)
--prompt-version TEXT (default spike-02-v1)
```

`evaluate` 子命令参数固定为 `--evidence-dir PATH` 和 `--review-file PATH`，读取已保存的运行结果与人工复核表，输出质量指标和结论。

GLM 运行还需要：

```text
SPIKE02_GLM_API_KEY
SPIKE02_GLM_ENDPOINT
SPIKE02_GLM_MODEL
```

CLI 不接受 key 作为命令行参数；缺少环境变量时返回 2 并说明缺少变量名，不打印变量值。Mock 命令必须完全离线。运行结果写入 evidence root，不写仓库目录下未忽略的文件。

- [ ] **Step 4: 更新安全规则和 README**

在 `.gitignore` 追加：

```gitignore
/spikes/spike_02/private/
/spikes/spike_02/evidence/
/docs/spikes/2026-07-15-spike-02-real.md
```

README 必须包含：Python 版本、Mock 测试命令、GLM 环境变量、三档规模运行命令、证据目录结构、禁止提交真实 fixture/key/响应，以及 Codex CLI 不属于本 Spike。

- [ ] **Step 5: 运行测试并提交**

```bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_cli -v
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
```

预期：Spike-02 全部确定性测试 PASS，Mock 路径不产生网络请求。

```bash
git add .gitignore spikes/spike_02
git commit -m "spike: add Spike-02 local run commands"
```

## Task 7: 执行三档运行并形成决策报告

**Files:**

- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/`
- Create after runs: `docs/spikes/2026-07-15-spike-02-decision-report.md`
- Modify after confirmed result: `docs/project-status.md`
- Test: `spikes/spike_02/tests/` full suite

**Interfaces:**

- Consumes: completed Spike-02 harness, approved fixture set and locally configured GLM credentials。
- Produces: three-scale evidence, quality review sheet and one of `pass`, `conditional_pass`, `fail`, `unverified`。

- [ ] **Step 1: 运行 Mock 确定性全套**

```bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
PYTHONPATH=spikes python3 -m spike_02.cli mock \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/mock-small \
  --chunk-size 3
```

预期：所有测试 PASS；Mock evidence 包含请求、结果和 metrics，但不包含任何真实 secret。

- [ ] **Step 2: 运行 GLM 小批次、约 500 条和 1000 条以上**

先从小批次开始，确认 endpoint、model、JSON contract 和 evidence 路径正常，再运行规模输入：

```bash
export SPIKE02_GLM_API_KEY='从本地密钥管理器读取'
export SPIKE02_GLM_ENDPOINT='从当前 GLM 账户配置读取'
export SPIKE02_GLM_MODEL='从当前 GLM 账户配置读取'

PYTHONPATH=spikes python3 -m spike_02.cli glm \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/glm-small \
  --chunk-size 3
```

随后使用 `build_synthetic_scale_case` 生成约 500 条和 1000 条以上输入，并分别用至少两个候选 chunk size 运行。每个规模记录请求数、重试数、P50/P95、token 或替代用量、截断和最终失败块。GLM 运行失败时保留 evidence，不切换 Codex CLI。

- [ ] **Step 3: 完成质量人工复核**

只对带 claims 的小批次和脱敏真实 fixture 进行人工复核；规模 fixture 不得用于质量结论。将每条 claim 的 `covered`、`grounded`、`correct_attribution`、`media_hallucination` 和说明写入本地 `review.jsonl`，再运行：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli evaluate \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/glm-small \
  --review-file /private/tmp/invest-hub-spike-02-evidence/review.jsonl
```

预期：生成质量报告和四类结论之一；无法人工复核时结论必须是 `unverified`。

- [ ] **Step 4: 写脱敏 decision report**

报告必须包含：运行日期、fixture 类型和规模、GLM 配置的非敏感标识、候选 chunk size、请求/重试/失败、P50/P95、JSON/Schema、质量门槛、严重错误、限制、未验证项和最终结论。不得写入 API key、完整 prompt、真实正文、私有 URL 或完整原始响应。

- [ ] **Step 5: 只在证据完成后更新项目状态**

如果 decision report 已形成，更新 `docs/project-status.md` 的 Spike-02 状态和下一 gate；不能把 `pass` 写成 V0/V1 生产批准，也不能在没有真实 GLM 证据时写“通过”。

- [ ] **Step 6: 最终验证和提交**

```bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
git diff --check
git status --short
```

预期：测试全部 PASS；真实证据只在 `/private/tmp/invest-hub-spike-02-evidence/`；Git 状态只包含预期的脱敏文档变更。

```bash
git add docs/spikes/2026-07-15-spike-02-decision-report.md docs/project-status.md
git commit -m "docs: record Spike-02 LLM validation result"
```

## Self-Review Checklist

- [ ] Spec 的三档规模、复杂内容、JSON、超时、截断、重试、事实、归因、调用次数和 P95 均有对应任务。
- [ ] Spec 的安全边界、Mock/GLM 范围、Codex CLI 排除和 Discovery 门禁均有对应任务。
- [ ] 所有新模块都有明确输入、输出和测试文件。
- [ ] 没有要求安装生产依赖或初始化应用框架。
- [ ] 1000 条以上合成 fixture 只用于容量，不被用于质量结论。
- [ ] 真实 GLM 缺少条件时只能输出 `unverified`，不能推断通过。
- [ ] 计划中没有空缺步骤、未定义动作或待补内容。
- [ ] 任务之间的函数名、字段名、Provider 状态和报告结构保持一致。
