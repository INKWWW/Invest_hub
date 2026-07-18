# Spike-02：完整容量稳定性与质量验证设计

## 文档状态

- 阶段：Discovery / Spike-02 完整验证增量设计
- 书面状态：Draft，等待用户审阅
- 日期：2026-07-18
- 上位 Spec：[Spike-02 Codex CLI 容量与质量验证设计](2026-07-15-spike-02-free-llm-capacity-quality-design.md)
- 前置证据：[Spike-02 1000 条 5/10 并发容量对比设计](2026-07-18-spike-02-capacity-concurrency-comparison-design.md)
- 本文不授权 V0/V1 生产实现，也不把验证结果写成生产默认配置。

## 1. 目标与结论边界

当前 1000 条、`chunk-size=100` 的 5 并发和 10 并发各完成过一轮，最终成功率和 evidence 完整性均通过，但单轮证据不足以解除 Spike-02 总体 `unverified`。本次增量验证只补齐两个缺口：

1. 重复容量运行，判断 5/10 并发在同一 Codex CLI 边界下是否可重复恢复；
2. 使用带人工标注的公开 fixture，重新复核结构化输出质量。

验证完成后，Spike-02 只能形成以下总体结论之一：

- `通过`：重复容量和质量门槛均满足，结果适用于已记录的本机 Codex CLI 条件；
- `有条件通过`：质量门槛满足，但存在可恢复 timeout/retry 或明确的运行约束，必须在结论中保留；
- `不通过`：出现阻断级质量错误、最终失败、证据错配或进程清理/状态竞争问题；
- `未验证`：必要运行或质量复核没有完成。

无论结论为何，都不批准 5/10 并发为生产默认值，不批准 Codex CLI 成为最终生产 Provider。

## 2. 选择的最小方案

采用“重复两轮 + 新鲜质量复核”的最小完整方案：

- 已有 1000 条 c100/c5 和 c100/c10 单轮结果分别作为第 1 个样本；
- c5 和 c10 各追加 2 轮，使用独立 evidence 目录，总计每档 3 轮；
- 每档每轮保持 1000 条 synthetic、`chunk-size=100`、240 秒单次 timeout、最多 3 次尝试，唯一变量仍是 `max-concurrency`；
- 追加 1 轮公开 `public_small.json` Codex 运行，使用已有 6 个人工标注 claims 进行新鲜质量复核；
- 不修改 runner、Provider、Prompt、Schema、chunk size、timeout 或重试逻辑，不增加长时间 soak、真实私有 fixture 或新 Provider。

只追加 1 轮会降低重复稳定性判断；增加更大真实 fixture 或长时间 soak 会扩大 Spike 范围。本方案在证据强度和执行成本之间保持当前 Spike 所需的最小平衡。

## 3. 容量重复验证

### 3.1 运行矩阵

| 配置 | 已有样本 | 新增样本 | 输入 | chunk | 尝试/timeout |
| --- | ---: | ---: | ---: | ---: | --- |
| c5 | 1 | 2 | 1000 synthetic | 100 | 最多 3 次 / 240 秒 |
| c10 | 1 | 2 | 1000 synthetic | 100 | 最多 3 次 / 240 秒 |

新增 evidence 目录必须独立且不存在；不得覆盖既有成功、失败或 Repeat-2 evidence。每轮预期产生 10 个初始 chunk。

### 3.2 单轮硬门槛

每轮必须满足：

- `primary_message_count=1000`、`chunk_size=100`，最终结果覆盖且仅覆盖 10 个 chunk；
- `final_success_rate=1.0`、`json_parse_rate=1.0`，最终结果状态全部为 `success`；
- `request_count` 等于 `requests.jsonl` 行数和 raw response 数量，结果数为 10，chunk ID 唯一；
- 每次请求的 `attempt <= 3`，`max_active_requests` 不超过配置值；
- 无 evidence 错配、EvidenceStore 损坏、CODEX_HOME 状态竞争、未回收进程组或 worktree 修改；
- `metrics.json`、`requests.jsonl`、`results.jsonl` 和 `raw_responses/` 均存在且可读取。

单次 timeout/provider failure 在最多 3 次尝试内恢复成功，且满足上述完整性门槛时，记录为 `recoverable_failure`，不单独判定该轮失败；必须保留 retry 数、首次成功率、失败状态和 P50/P95。

### 3.3 重复稳定性判定

对每个并发配置合并 3 轮结果：

- 3/3 轮都满足单轮硬门槛，且没有任何硬性基础设施错误：该配置容量稳定性通过；
- 3/3 轮最终成功但出现 timeout/retry：该配置容量稳定性为有条件通过，必须在总体结论中保留 retry 代价；
- 任一轮最终失败、超过最大尝试、evidence 错配、状态竞争或进程清理异常：该配置容量验证不通过，不能用另一档并发掩盖；
- 缺少任一轮或校验不完整：该配置保持 `unverified`。

## 4. 新鲜质量复核

### 4.1 运行边界

使用仓库内人工构造的 `spikes/spike_02/fixtures/public_small.json`，通过当前 Codex CLI Provider 新运行一轮；使用 `chunk-size=100`、`max-concurrency=1`、最多 3 次尝试和 240 秒 timeout。该运行只用于质量，不与 1000 条 synthetic 容量指标混合。

完整输出和诊断只写入本地受保护 evidence 目录；仓库只记录脱敏指标和结论。

### 4.2 质量门槛

对 fixture 中已有的 6 个 claims 逐项人工复核并生成本地 review JSONL：

- 6/6 claims covered；
- 6/6 claims grounded，且 source message ID 能回指输入；
- 6/6 claims correct attribution；
- severe attribution errors 为 0；
- media hallucinations 为 0，未解析媒体继续标记而不推测；
- JSON/Schema 率为 100%，无最终失败 chunk。

任一严重归因错误或媒体臆测都使质量门槛失败。只有旧质量记录而没有本轮新鲜输出时，不得把旧结果冒充本轮证据。

## 5. 总体结论规则

在容量重复和新鲜质量复核都完成后：

- 两档容量均通过，质量门槛通过，且无硬性基础设施错误：总体为 `通过`；
- 两档容量均最终成功、质量通过，但存在已记录的可恢复 timeout/retry 或明确运行限制：总体为 `有条件通过`；
- 任一容量档失败，或质量门槛失败：总体为 `不通过`；
- 任一必需 evidence 或 review 缺失：总体仍为 `未验证`。

“通过/有条件通过”只表示 Spike-02 在已记录环境、模型、Prompt、chunk 和 timeout 条件下完成验证，不代表生产 SLA、安全并发上限或云端部署结论。

## 6. 预期产物与阶段门禁

- 本 Spec 对应的 implementation plan；
- 4 个新增 1000 条容量 evidence 目录和 1 个新增公开质量 evidence 目录，均保存在本地受保护路径；
- 本地人工质量 review JSONL，不包含 Prompt、完整响应、凭据或私有 fixture；
- 更新后的 `docs/project-status.md`、Spike-02 decision report 和 engineering journal；
- 确定性测试结果保持 40/40 或更高。

本 Spec 获得用户审阅批准、implementation plan 获得批准前，不执行新增真实 Codex 调用，不修改生产默认值，不删除既有 evidence。
