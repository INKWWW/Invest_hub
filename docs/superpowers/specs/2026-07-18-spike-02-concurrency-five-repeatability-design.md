# Spike-02：5 并发稳定性与 1000 条容量验证设计

## 文档状态

- 状态：Draft，等待用户审阅
- 日期：2026-07-18
- 上位 Spec：[Spike-02 Codex CLI 容量与质量验证设计](2026-07-15-spike-02-free-llm-capacity-quality-design.md)
- 前置设计：[Spike-02 受控并发验证设计](2026-07-18-spike-02-bounded-concurrency-design.md)
- 本文只扩展 Discovery 阶段的测试验证边界，不授权 V0/V1 生产实现。

## 1. 背景与目标

当前已经完成一次 500 条 synthetic fixture、`chunk-size 100`、`max-concurrency=5` 的探针：5 个 chunk 全部成功、0 重试、批次墙钟 129,814 ms，实际最大活动请求数为 5。该结果显示 5 并发具有明显吞吐收益，但单次运行不足以证明稳定性、状态目录竞争边界或更大规模容量。

本次验证的目标是：在不改变 Prompt、Schema、chunk 语义、Codex CLI 安全边界和 Provider 行为的前提下，重复验证 500 条 c100/5 并发，再验证 1000 条 c100/5 并发，最后用公开小 fixture 检查并发没有改变来源归因、Schema 和未解析媒体边界。

## 2. 范围

### 2.1 包含内容

- 以当前已实现的 bounded worker runner 和 `max-concurrency=5` 作为被测对象；
- 使用相同的 `chunk-size=100`、最多 3 次尝试和每请求 240 秒超时；
- 重复运行 3 轮 500 条 synthetic fixture，每轮使用独立的本地 evidence 目录；
- 在 3 轮 500 条测试均通过后，运行 1 轮 1000 条 synthetic fixture；
- 使用公开小 fixture 做一次 configured `max-concurrency=5` 的质量复核；该 fixture 当前拆成 4 个 chunk，因此实际最大活动请求数不超过 4；
- 记录请求/结果/raw response 数量、首次/最终成功率、JSON/Schema 率、重试、P50/P95、批次墙钟、实际最大并发和失败分类；
- 运行完成后更新 decision report、project-status 和 engineering journal，保持证据可追溯。

### 2.2 不包含内容

本次不包含：

- Codex 会话复用、`app-server`、`exec resume` 或 Provider 更换；
- 修改 Prompt、Schema、chunk-size、重试策略或进程清理逻辑；
- 自动把 5 并发提升为生产默认值；
- 真实私有内容、生产数据、OpenRouter、自动 fallback、队列、数据库或生产调度；
- 使用 synthetic 输出宣称业务事实、归因或媒体处理质量通过。

## 3. 验证矩阵

| 阶段 | 输入 | 配置 | 目的 |
| --- | --- | --- | --- |
| Repeat-1/2/3 | 500 条 synthetic | c100，max5，240s，最多 3 次尝试 | 验证 5 并发的重复稳定性 |
| Capacity-1000 | 1000 条 synthetic | c100，max5，240s，最多 3 次尝试 | 验证更大批次是否出现状态竞争、超时或 evidence 错配 |
| Quality smoke | 12 条公开 fixture | c3，configured max5，240s，最多 3 次尝试 | 检查并发不改变 Schema、来源归因和未解析媒体边界 |

每轮必须使用独立 evidence 目录，不覆盖已有串行、2 并发或 5 并发证据。真实 Codex Prompt、完整响应、诊断和私有状态只保存在本地受保护目录，不进入 Git。

## 4. 验收标准

### 4.1 500 条重复稳定性

三轮都必须满足：

- 初始 chunk 数为 5；5/5 首次成功、最终成功率为 100%；
- 请求数为 5、重试数为 0；所有 Provider 状态为 `success`，没有 timeout、provider failure、empty response、invalid JSON/Schema 或 CODEX_HOME 状态竞争错误；
- JSON/Schema 率为 100%；`max_active_requests` 不超过 5，且至少有一轮观测到实际并发大于 1；
- `requests.jsonl`、`results.jsonl` 和 `raw_responses/` 均完整，chunk ID 唯一且可对应；
- 每轮批次墙钟都明显低于已有串行基线 645,827 ms；记录实际耗时和波动，不把当前单次 129.8 秒当作 SLA；
- 每轮运行结束后 worktree 保持 clean。

任一轮出现未解释的并发状态冲突、evidence 错配、进程组清理异常或请求失败，立即停止后续容量测试，保留该轮 evidence 并标记 5 并发稳定性验证失败。

### 4.2 1000 条容量

仅在三轮 500 条重复测试全部通过后执行。该轮必须满足：

- 初始 chunk 数为 10，10/10 首次及最终成功；
- 请求数为 10、重试数为 0，所有 Provider 状态为 `success`，无 timeout、provider failure、empty response、invalid JSON/Schema 或状态竞争错误；
- JSON/Schema 率为 100%，`max_active_requests` 不超过 5；
- 10 条 request、10 条 result 和 10 个 raw response 均完整且 chunk ID 无错配；
- worktree 保持 clean。

1000 条仍是 synthetic capacity evidence，不构成业务质量结论或生产容量 SLA。

### 4.3 公开小 fixture 质量复核

运行 configured `max-concurrency=5` 的公开小 fixture，并复用已有人工质量复核标准：6/6 claims grounded 且正确归因，严重归因错误为 0，媒体臆测为 0，`media_unparsed` 边界保持正确。若本轮没有新的模型输出可复核，则必须明确记录为“并发 Schema smoke 通过、质量复核未新增”，不得把旧质量结果冒充新证据。

## 5. 失败处理与结论

- 500 条重复测试失败：不运行 1000 条；保留失败 evidence，分类是 Provider/状态竞争、timeout、Schema、evidence 或进程清理问题。
- 1000 条失败：不自动降低并发并重跑同一轮；先记录失败，再决定是否新增 c3/c2 对照验证。
- 任一轮成功但耗时波动明显：不判定为稳定通过，只记录吞吐收益和波动范围。
- 所有阶段通过：结论最多为“`chunk-size=100 + max-concurrency=5` 在当前 synthetic fixture 和本机 Codex CLI 条件下具备可重复的 Spike 容量证据”；Spike-02 总体仍需结合既有质量和其他容量门槛决定，不能直接进入 V0/V1 生产。

## 6. 阶段门禁

本文获得批准后，编写对应 implementation plan；Plan 获得批准后再执行真实 Codex 调用。执行完成前不修改生产架构结论，不把 5 并发写成默认生产配置，不把本地 evidence 或完整模型响应加入 Git。
