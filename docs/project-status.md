# Project Status

Last updated: 2026-07-18

## Current phase

**Discovery / Spike-01 已完成，Spike-02 完整验证有条件通过；项目仍未进入 V0/V1 生产实现**

项目仍处于 Discovery，不代表已经进入 V0/V1 生产实现。Spike-01 已完成真实网页轨验证；Spike-02 harness、进程超时清理、小批次质量验证、有界并发验证、1000 条 c100 的 5/10 并发重复容量验证和媒体来源链路修复后的新鲜质量复核均已完成。按已批准的增量验证口径，Spike-02 在已记录的本机 Codex CLI 条件下有条件通过；你已确认未来生产试运行优先采用 chunk size 100、5 个并发请求，但这仍是后续生产设计的候选配置，不等于生产边界、SLA 或最终 Provider 选型已经确定。

## Approval status

- Approved specification：
  - [模块 1 总体设计](superpowers/specs/2026-07-15-invest-hub-module-1-project-design.md)
  - [Spike-01 Discord 增量采集设计](superpowers/specs/2026-07-15-spike-01-opencli-discord-incremental-design.md)
  - [Spike-02 Codex CLI 容量与质量设计](superpowers/specs/2026-07-15-spike-02-free-llm-capacity-quality-design.md)
  - [Spike-02 有界并发设计](superpowers/specs/2026-07-18-spike-02-bounded-concurrency-design.md)
  - [Spike-02 未解析媒体来源链路设计](superpowers/specs/2026-07-18-spike-02-media-source-linkage-design.md)
- Approved implementation plan：
  - [Spike-01 Discord 增量采集计划](superpowers/plans/2026-07-15-spike-01-opencli-discord-implementation-plan.md)
  - [Spike-02 Codex CLI 容量与质量计划](superpowers/plans/2026-07-15-spike-02-free-llm-capacity-quality.md)
  - [Spike-02 有界并发计划](superpowers/plans/2026-07-18-spike-02-bounded-concurrency-plan.md)
  - [Spike-02 未解析媒体来源链路计划](superpowers/plans/2026-07-18-spike-02-media-source-linkage-plan.md)
- Approved technology stack：无

`intake.md` 中的技术方向、版本范围和实现建议属于前期讨论输入；其中标注为建议或待 Spike/Spec 确认的事项，尚未自动成为生产实现决策。Spike-01 和 Spike-02 的结论只作为后续设计输入。

## Current scope

当前只处理模块 1「投资信息收集」。模块 2「选股研判」、模块 3「策略和复盘」和模块 4「投资体系」暂不进入实现范围。

模块 1 的前期目标是建立从 Discord/X 信息采集，到原始内容持久化、规则清洗、LLM 结构化理解、批次总结、日累计总结，再到网页阅读和证据回溯的可持续流水线。

## Repository state

当前仓库包含项目治理文档、Spike-01 harness 和 Spike-02 harness。Spike harness 仅限验证，不是生产应用代码；没有初始化生产应用框架，也没有安装生产依赖。真实内容、Codex Prompt、完整响应和本地 evidence 不进入 Git。

## Spike-01 result

- 确定性测试：32/32 通过；
- bounded soak：202 条原始消息成功采集；
- 两轮 evidence 合计：1504 条唯一 Canonical 消息；
- checkpoint 恢复、network 空窗和逐页 telemetry 验证通过；
- 决策结论：OpenCLI-first 可作为后续设计输入，但生产采用必须保留 freshness、有限重试、失败恢复和逐页 telemetry。

## Spike-02 result

- 确定性测试：46/46 通过；
- Codex CLI：`codex-cli 0.144.3`，当前运行时报告模型为 `gpt-5.6-luna`；
- 12 条公开 fixture 的一次真实 Codex CLI 运行：最终成功率 100%、JSON/Schema 率 100%，P50/P95 均为 150,956 ms；
- 6/6 人工质量 claims grounded 且正确归因，严重归因错误和媒体臆测均为 0；
- 120 秒窗口出现超时，默认窗口已调整为 240 秒；
- `chunk-size 500` 和前一轮 `chunk-size 250` 的 500 条真实运行首个 chunk 均在约 240 秒超时；2026-07-17 重跑 `chunk-size 250` 时首个 chunk 约 77 秒成功，第二个 chunk 三次均在约 240 秒超时，最终成功率 50%，进程组均正常回收；因此 250 仍不是安全配置，当前建议降至 `chunk-size 100` 或更小；
- 2026-07-18 使用 `chunk-size 100` 完成 500 条 synthetic capacity run：5/5 chunk 首次及最终成功，0 次重试，JSON/Schema 率 100%，P50/P95 为 123,354/157,740 ms，进程退出码均为 0；该结果支持 100 作为当前容量候选，但重复运行稳定性、业务质量和生产边界仍未验证；
- 在不复用 Codex 会话的前提下增加最多 2 并发：公开小 fixture smoke 为 4/4 成功、批次耗时 39,884 ms、`max_active_requests=2`；500 条 `chunk-size 100` synthetic run 为 5/5 成功、0 次重试、批次墙钟 321,965 ms、P50/P95 为 127,935/129,800 ms，较串行请求延迟总和 645,827 ms 约快 2.006x；该证据只支持容量吞吐改善，不支持业务质量或生产限流结论；
- 追加一次 5 并发探针：500 条 `chunk-size 100` synthetic run 为 5/5 成功、0 次重试、批次墙钟 129,814 ms、P50/P95 为 112,947/129,807 ms，较串行约快 4.975x、较 2 并发约快 2.480x；该结果只有一次运行，暂不把 5 并发列为安全或生产配置；
- 5 并发重复验证已执行两轮：Repeat-1 通过；Repeat-2 有 1 个 chunk 在 240,018 ms timeout 后重试成功，最终成功率 100% 但首次成功率 80%、重试数 1；按门槛停止 Repeat-3 和 1000 条测试，5 并发稳定性仍未验证；
- 在接受“最多 3 次尝试内恢复成功属于可恢复事件”的增量口径后，完成 1000 条、`chunk-size 100` 的单轮容量对比：5 并发为 10/10 最终成功、0 重试、JSON/Schema 率 100%、P50/P95 为 119,898/129,648 ms、批次墙钟 253,921 ms；10 并发为 10/10 最终成功、0 重试、JSON/Schema 率 100%、P50/P95 为 123,711/132,231 ms、批次墙钟 132,241 ms；实际最大并发分别为 5 和 10，evidence 均完整，按增量 Spec 两档均为 `capacity_probe_pass`，但只代表单轮 synthetic 容量证据；
- 完整验证追加 1000 条 c100 重复运行：5 并发三轮批次墙钟为 253,921/304,162/264,062 ms，10 并发三轮为 132,241/139,351/144,374 ms；六轮均 10/10 最终成功、首次成功率和 JSON/Schema 率均为 100%、重试数均为 0、实际最大并发符合配置，容量重复稳定性通过；
- 完整验证的首轮公开 fixture 质量运行曾为 5/6 covered/grounded，缺口是 `public-008` 没有来源链路；该缺口随后按已批准的方案 1 修复：新增必填 `media_source_message_ids`，由 Schema 校验当前 chunk 的全部未解析媒体 ID，评估器使用该字段判断 grounding；确定性回归为 46/46 通过；
- 修复后的新鲜公开质量 evidence：`/private/tmp/invest-hub-spike-02-evidence/codex-public-small-media-linkage-20260718-luna`。1/1 chunk 首次及最终成功，JSON/Schema 率 100%，请求数 1、重试数 0、P50/P95 为 46,938/46,938 ms；Codex CLI 运行时报告模型为 `gpt-5.6-luna`；`public-008` 出现在 `media_source_message_ids`，6/6 claims covered、grounded、correct attribution，严重归因错误 0，媒体臆测 0；
- 综合结论：Spike-02 为**有条件通过**。1000 条、chunk size 100 的 5/10 并发各 3 轮容量重复稳定性通过，质量门槛也通过；但此前 500 条、chunk size 100 的 5 个并发请求 Repeat-2 曾出现一次可恢复 timeout/retry，且 chunk size 250/500 已实测不稳定。因此，未来生产试运行的初始候选配置为 chunk size 100、5 个并发请求；10 个并发请求暂作为后续扩容候选，不把 Codex CLI 写成最终生产 Provider；
- Codex timeout 清理回归测试、EvidenceStore 并发写入保护和 runner 并发/重试隔离测试已加入，完整确定性测试为 46/46；
- 脱敏决策报告：[Spike-02 决策报告](spikes/2026-07-15-spike-02-decision-report.md)。

小批次成功不等同于容量通过，也不批准 V0/V1 生产实现或自动 fallback。

## Next gate

下一阶段暂不启动 V0。未来恢复生产设计时，可基于 Spike-02 的有条件通过结果，另行明确真实数据运行、限流/SLA、Provider 选择和失败降级策略，并以 chunk size 100、5 个并发请求作为初始候选；本次公开 fixture 质量结果不外推为真实业务质量。

在真实容量结论明确、后续正式 Spec 和 plan 获得批准前：

- 不把现有 Spike-02 harness 直接升级为生产实现；
- 不启动 V0/V1 生产实现；
- 不把 Spike-01 harness 直接升级为生产应用；
- 不把 OpenCLI、Discord Desktop、Codex CLI 或官方 API 固化为最终生产架构。
