# Spike-02 Media Source Linkage Specification

Status: Approved for implementation in `spike-02-implementation` (user-approved 2026-07-18)

Date: 2026-07-18

## Problem

Spike-02 当前可以输出 `media_unparsed=true` 和相应 warning，但没有说明哪些输入消息包含未解析媒体。

以 `public-008` 为例：模型正确地没有猜测图片内容，但输出没有引用 `public-008`。因此评估器无法证明“这条未解析媒体消息被纳入了结果”，导致 coverage 和 grounding 失败。这是来源链接契约缺失，不是媒体内容幻觉。

## Goal

为未解析媒体增加一个最小、明确、可校验的来源字段，使每条未解析媒体输入都能被结果直接追溯，同时保持当前“不解析、不臆测媒体内容”的边界。

## Scope

本次只调整 Spike-02 的结构化输出契约及其校验链路：

- `StructuredOutput` 数据模型；
- JSON 解析和确定性校验；
- Codex CLI prompt 及测试 mock；
- runner 将当前 chunk 的媒体消息传给校验器；
- 质量评估器对媒体相关 claim 的 coverage/grounding 判断；
- 相关单元测试和 Spike-02 输出契约说明。

本次不引入新的 Provider、持久化层、数据库、媒体解析能力或并发架构调整。

## Output contract

结构化输出增加必填字段 `media_source_message_ids`：

```json
{
  "topics": [],
  "media_unparsed": true,
  "media_source_message_ids": ["public-008"],
  "warnings": ["存在未解析媒体，未推测其内容。"]
}
```

字段规则：

1. `media_source_message_ids` 必须是字符串数组；没有未解析媒体时必须为 `[]`。
2. 当前 chunk 中存在未解析媒体时，`media_unparsed` 必须为 `true`，且 `media_source_message_ids` 必须包含当前 chunk 中全部未解析媒体消息 ID。
3. 当前 chunk 中不存在未解析媒体时，`media_unparsed` 必须为 `false`，且 `media_source_message_ids` 必须为 `[]`。
4. 每个 ID 必须同时满足：属于当前 chunk 输入，且对应输入消息的 `kind` 是 `unparsed_media`。
5. 该字段只证明媒体消息的来源，不代表媒体内容已被读取；模型仍不得推断图片、PDF、视频、音频或其他附件内容。
6. 缺失字段、未知 ID、非媒体 ID、漏引用媒体 ID 或错误的 `media_unparsed` 状态均视为 schema error，并进入现有重试路径。

为了让模型失败时可被发现，本次不采用“评估器或后处理器自动补齐 ID”。输出必须由模型明确给出，确定性校验器负责拒绝不完整结果。

## Processing behavior

### Prompt

Prompt 明确要求模型：

- 按原始消息 ID 填写 `media_source_message_ids`；
- 引用当前 chunk 中每一条 `kind=unparsed_media` 的消息；
- 没有此类消息时输出空数组；
- 不描述或推断媒体内容。

### Schema and runner

`parse_structured_output` 解析新字段到：

```python
media_source_message_ids: tuple[str, ...]
```

`validate_structured_output` 接收当前 chunk 的未解析媒体 ID 集合，并执行上述完整性校验。runner 从当前 chunk 的输入消息计算该集合后传入校验器。

### Evaluation

评估器继续以 topic 为主要语义输出，同时把 `media_unparsed`、`warnings` 和 `media_source_message_ids` 作为一个可追溯的媒体元数据结果进行评估。

对于要求“媒体未解析/不得臆测”的 claim：

- coverage 来自媒体元数据和 warning 中的明确说明；
- grounding 来自 claim 的来源 ID 是否被 `media_source_message_ids` 覆盖；
- 现有媒体幻觉检测继续检查是否对未解析媒体作出被禁止的内容断言。

## Acceptance criteria

实现完成后必须满足：

1. 现有 Spike-02 确定性测试全部通过。
2. 新增测试证明：缺失、未知、非媒体、漏引用的媒体来源字段会被拒绝；完整引用会被接受。
3. 新增测试证明：带 `public-008` 来源 ID 的未解析媒体结果，其媒体 claim 同时通过 coverage 和 grounding，且无媒体幻觉。
4. 新鲜 `public_small.json` 质量复核中，`public-008` 被显式列入 `media_source_message_ids`；目标为 6/6 coverage、6/6 grounding、severe attribution 0、media hallucination 0。
5. 若模型连续重试仍未给出合法媒体来源字段，结果必须明确失败，不得由程序静默补齐。

## Non-goals

- 不解析任何媒体内容。
- 不改变 chunk size、并发度、Codex CLI 调用方式或超时策略。
- 不把未解析媒体强行伪造成普通 topic。
- 不扩展到真实私有数据或生产系统。
