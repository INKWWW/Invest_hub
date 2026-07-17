# Spike-02：Codex CLI 受控并发验证设计

## 文档状态

- 状态：Draft，等待用户审阅
- 日期：2026-07-18
- 上位 Spec：[Spike-02 Codex CLI 容量与质量验证设计](2026-07-15-spike-02-free-llm-capacity-quality-design.md)
- 本文只设计 Spike-02 harness 的并发验证，不授权 V0/V1 生产实现。

## 1. 背景与目标

当前 500 条 synthetic fixture 使用 `chunk-size 100` 时会拆成 5 个 chunk，并串行启动 5 次 Codex CLI。5 次请求耗时合计约 645.8 秒，约 10 分 46 秒；5/5 首次成功、无重试。

本次设计的目标是：在不改变 Prompt、Schema、Codex 安全边界和 chunk 语义的前提下，增加最多 2 个并发 Codex CLI 调用，降低整批任务的墙钟时间，并验证并发是否引入状态竞争、证据错配或失败恢复问题。

## 2. 范围

### 2.1 包含内容

- 为 Spike-02 runner 增加受控并发参数，默认并发数保持为 1；
- 验证 `max-concurrency=2` 下的 500 条、`chunk-size 100` 容量运行；
- 每个 chunk 仍使用一个独立、非交互的 `codex exec` 进程；
- 只重试失败 chunk，已完成 chunk 不重复执行；
- 保留每个 chunk 的独立 request、raw response 和 result evidence；
- 增加批次墙钟耗时、并发上限和实际并发观测指标；
- 验证并发模式下 JSON/Schema 校验、进程组清理和 worktree 只读边界保持有效。

### 2.2 不包含内容

本次不包含：

- Codex 会话复用、`app-server` 或 `exec resume`；
- 提高 `chunk-size` 到 125、150、250 或更大；
- Prompt 压缩、消息预摘要或改变输入语义；
- 更换模型、Provider、OpenRouter 或自动 fallback；
- 生产 Worker、队列、数据库、云端并发调度或应用代码。

## 3. 并发模型

采用固定上限的 worker 模型：

```text
Fixture
  → build_chunks(chunk-size 100)
  → bounded queue
  → 最多 2 个 worker
       → 一个 worker 同时只处理一个 chunk
       → 失败 chunk 在同一 worker 内按现有策略重试
  → 按 chunk index 汇总结果
  → JSON/Schema 校验与 metrics
```

每个 worker 的 Codex 调用继续使用现有边界：`codex exec`、`--sandbox read-only`、`--add-dir <CODEX_HOME>`、`--ephemeral`、`--output-last-message`。并发只改变调度，不改变单次 Provider 的进程组、超时和清理逻辑。

证据写入必须支持并发调用：每条记录保留 `run_id`、`chunk_id`、`attempt` 和退出状态；最终报告按 chunk index 稳定汇总，不能依赖请求完成顺序。并发模式下共享的 Codex 状态目录若出现竞争性失败，必须记录为失败证据，不得静默忽略。

## 4. 验证与验收

### 4.1 确定性验证

- 使用 fake Provider 验证最多活动请求数不超过配置上限；
- 验证成功 chunk 不重复调用，失败 chunk 可独立重试；
- 验证并发完成顺序变化不会改变最终 chunk 排序和统计；
- 验证 `max-concurrency=1` 保持原有串行行为；
- 完整确定性测试保持通过。

### 4.2 真实 Codex 验证

先使用公开小 fixture 做 `max-concurrency=2` smoke test，再使用 500 条 synthetic fixture、`chunk-size 100`、240 秒超时和最多 3 次尝试进行完整容量测试。真实 evidence 只写入本地受保护目录，不进入 Git。

至少记录：

- 输入消息数、chunk 数、并发上限和实际最大并发数；
- 首次/最终成功率、JSON/Schema 率、请求数和重试数；
- 每个请求的 latency、P50/P95 和整批墙钟耗时；
- timeout、provider failure、empty response、invalid JSON/Schema 和状态目录竞争错误；
- worktree 是否保持无修改。

本轮容量验证的通过条件是：5 个 chunk 均获得可校验结果，未出现无法解释的并发错配或进程清理问题，并且整批墙钟时间明显低于现有约 10 分 46 秒串行基线。约 6–7 分钟是基于当前 latency 的参考目标，不作为生产 SLA。

synthetic fixture 只用于容量和调度验证，不用于业务事实、归因或媒体处理质量结论。

## 5. 风险与恢复

- Codex 多进程可能竞争共享 `CODEX_HOME` 状态目录；smoke test 失败时停止扩大发送，不把并发结果当作容量通过；
- 并发 evidence 写入可能产生顺序变化；所有记录必须使用 chunk/attempt 标识，并在汇总时排序；
- 单个 chunk timeout 只能终止对应进程组，不得终止其他 worker；
- 并发模式失败时，保留串行模式作为默认和回退验证路径；
- 本次不改变失败分类、JSON/Schema 校验和媒体未解析边界。

## 6. 阶段门禁

本文获得批准后，才编写对应 implementation plan。Plan 获得批准并完成验证前：

- 不把并发 runner 视为生产架构；
- 不启动 V0/V1 实现；
- 不引入 Codex 会话复用或其他 Provider；
- 不更新 Spike-02 为通过结论；结果仍须回写 decision report、project-status 和 engineering journal。
