# Spike-02：1000 条 5/10 并发容量对比验证设计

## 文档状态

- 状态：Draft，等待用户审阅
- 日期：2026-07-18
- 上位 Spec：[Spike-02 Codex CLI 容量与质量验证设计](2026-07-15-spike-02-free-llm-capacity-quality-design.md)
- 前置设计：[Spike-02 5 并发稳定性与 1000 条容量验证设计](2026-07-18-spike-02-concurrency-five-repeatability-design.md)
- 本文是对当前测试验收口径的增量调整，不授权 V0/V1 生产实现。

## 1. 背景与目标

500 条、`chunk-size=100`、5 并发的 Repeat-2 中，一个 chunk 首次请求在 240 秒超时，但第二次重试成功。该现象说明 timeout 是可恢复事件，不能只用“是否发生过一次 timeout”判断整轮最终可用性；同时，5 并发的吞吐收益还需要与 10 并发进行直接对比。

本次验证目标是：在相同 Prompt、Schema、chunk 语义和 Codex CLI 安全边界下，分别运行 1000 条 synthetic fixture 的 5 并发和 10 并发，比较最终成功率、重试代价、批次墙钟、实际并发和 evidence 完整性。

## 2. 验收口径调整

### 2.1 可恢复事件

单个请求 timeout、provider failure 或其他可重试错误，只要在 `max_attempts=3` 内重试成功，且没有造成 evidence 错配、进程清理异常或状态目录竞争，则记录为 `recoverable_failure`，不单独判定整轮失败。

因此：

- `first_success_rate < 1.0` 可以接受，但必须记录；
- `retry_count > 0` 可以接受，但必须记录；
- `final_success_rate < 1.0` 不接受；
- 超过最大尝试次数、evidence 错配、状态竞争或进程组无法清理不接受。

### 2.2 结论边界

即使 5/10 并发两轮都最终成功，也只能形成“当前 synthetic fixture 下的容量对比证据”，不能直接批准 10 并发为生产配置，也不能把 synthetic 输出当作业务质量证据。

## 3. 验证范围

### 3.1 包含内容

- 使用 1000 条 synthetic fixture，固定 `chunk-size=100`；
- 分别运行 `max-concurrency=5` 和 `max-concurrency=10`，每种配置使用独立 evidence 目录；
- 固定每请求超时 240 秒、最多 3 次尝试，不改变重试等待、Prompt、Schema、Provider 或进程组清理逻辑；
- 记录初始 chunk 数、请求数、结果数、raw response 数、首次/最终成功率、JSON/Schema 率、重试数、P50/P95、批次墙钟、配置/实际并发和失败分类；
- 比较 5 并发与 10 并发的效率、重试代价和稳定性风险；
- 完成后更新 decision report、project-status 和 engineering journal。

### 3.2 不包含内容

- 不修改 runner、Provider、Prompt、Schema、chunk size 或 timeout 代码；
- 不使用 Codex 会话复用、app-server、OpenRouter、其他 Provider 或自动 fallback；
- 不运行真实私有内容，不把完整 Prompt、响应、诊断或 credentials 加入 Git；
- 不把本轮结果直接当作生产并发配置或 SLA。

## 4. 验证矩阵

| Run | 输入 | 配置 | 目的 |
| --- | --- | --- | --- |
| Capacity-1000-C5 | 1000 条 synthetic | c100，max5，240s，最多 3 次尝试 | 验证当前 5 并发在更大批次的最终可用性 |
| Capacity-1000-C10 | 1000 条 synthetic | c100，max10，240s，最多 3 次尝试 | 验证更高并发的效率收益和竞争风险 |

1000 条 c100 预期产生 10 个初始 chunk。允许部分请求发生可恢复重试，因此 `request_count` 可以大于 10；最终 `results.jsonl` 应有 10 个最终 chunk 结果，raw response 数量应等于 request 数量。

## 5. 单轮验收标准

每个并发配置都必须满足：

- `primary_message_count=1000`、`chunk_size=100`，初始 chunk 数为 10；
- `final_success_rate=1.0`，10 个 chunk 最终均有可校验结果；
- `json_parse_rate=1.0`，最终 results 的 chunk ID 唯一且覆盖 10 个初始 chunk；
- `max_active_requests` 不超过配置值，且 evidence 中没有请求/结果错配；
- 所有请求都在最多 3 次尝试内结束；允许 timeout 后 retry success，但必须记录 `first_success_rate`、`retry_count` 和失败分类；
- 无未回收的 Codex 进程组、CODEX_HOME 状态竞争错误、EvidenceStore 写入损坏或 worktree 修改；
- `metrics.json`、`requests.jsonl`、`results.jsonl` 和 `raw_responses/` 完整存在。

如果任一配置出现最终失败 chunk、超过最大尝试次数、evidence 错配、状态目录竞争或进程清理异常，标记该配置为 `failed`，保留 evidence，不用另一种配置的成功掩盖失败。

## 6. 对比与结论

比较两轮：

- 批次墙钟和相对串行 c100 基线的 speedup；
- P50/P95 请求延迟；
- request 数、retry 数、first/final success rate；
- 实际最大并发是否达到配置上限；
- timeout、provider failure、状态竞争和 evidence 异常分类。

结果使用以下描述之一：

- `capacity_probe_pass`: 该配置最终成功且 evidence/进程边界完整；
- `capacity_probe_recoverable`: 最终成功，但发生了 timeout/retry，需要重复验证；
- `capacity_probe_failed`: 存在最终失败、状态竞争、evidence 错配或清理异常；
- `unverified`: 缺少必要证据或未完成对比。

即使 5 和 10 并发都为 `capacity_probe_pass`，Spike-02 总体结论仍保持 `unverified`，直到上位 Spec 要求的质量、重复稳定性和其他容量门槛分别完成。

## 7. 阶段门禁

本文获得批准后，编写对应 implementation plan；Plan 获得批准后才执行 1000 条 5/10 并发真实调用。执行前不修改生产默认值，不删除既有失败 evidence，不把 10 并发写成安全配置。
