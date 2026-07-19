# Project Status

Last updated: 2026-07-19

## Current phase

**V0 通过（有界单页真实 Discord 验证完成）**

Spike-01 已完成真实网页轨验证，Spike-02 在已记录的本机 Codex CLI 条件下有条件通过；随后已按批准的 V0 Spec/Plan 完成控制面、Supabase/RLS、Python 工作节点、Active Adapter、Provider 边界、管理员调试页和脱敏 E2E harness。2026-07-19 已创建隔离 Supabase/Vercel 预览、应用远程迁移并部署新控制面；受保护预览上的合成核心工作节点链路注册 → 心跳 → 领取 → 持久化 → 回报结果已通过并回读确认检查点，普通用户管理员阻断和过期租约的检查点恢复也已远程补测。同日已完成一次用户明确授权的真实 Discord 有界单页任务：首次超时不推进安全检查点，第 2 次成功采集、结构化、远程持久化、结果回报并确认非空安全检查点。V0 因此通过；它仍不是生产发布批准。

## Approval status

- Approved specification：
  - [模块 1 总体设计](superpowers/specs/2026-07-15-invest-hub-module-1-project-design.md)
  - [Spike-01 Discord 增量采集设计](superpowers/specs/2026-07-15-spike-01-opencli-discord-incremental-design.md)
  - [Spike-02 Codex CLI 容量与质量设计](superpowers/specs/2026-07-15-spike-02-free-llm-capacity-quality-design.md)
  - [Spike-02 有界并发设计](superpowers/specs/2026-07-18-spike-02-bounded-concurrency-design.md)
  - [Spike-02 未解析媒体来源链路设计](superpowers/specs/2026-07-18-spike-02-media-source-linkage-design.md)
  - [V0 基础设施与技术验证设计](superpowers/specs/2026-07-18-v0-infrastructure-technical-validation-design.md)
- Approved implementation plan：
  - [Spike-01 Discord 增量采集计划](superpowers/plans/2026-07-15-spike-01-opencli-discord-implementation-plan.md)
  - [Spike-02 Codex CLI 容量与质量计划](superpowers/plans/2026-07-15-spike-02-free-llm-capacity-quality.md)
  - [Spike-02 有界并发计划](superpowers/plans/2026-07-18-spike-02-bounded-concurrency-plan.md)
  - [Spike-02 未解析媒体来源链路计划](superpowers/plans/2026-07-18-spike-02-media-source-linkage-plan.md)
  - [V0 基础设施与技术验证计划](superpowers/plans/2026-07-18-v0-infrastructure-technical-validation.md)
  - [V0 收口与远程验收实施计划](superpowers/plans/2026-07-19-v0-closure-remote-validation.md)
  - [V0 真实运行有界批次恢复计划](superpowers/plans/2026-07-19-v0-real-run-bounded-batch-recovery.md)
- V0 implementation status：已完成确定性实现、远程持久化、隔离预览部署、核心工作节点 HTTPS、远程角色/恢复和真实有界单页验收，结论为通过；真实内容仍只保留在仓库外受保护目录。
- V0 validation stack：Next.js + Supabase/RLS、Python 3.11+ Worker、OpenCLI Active Adapter 边界、Mock/Codex CLI Provider；这些是 V0 验证选择，不等于最终生产架构批准。

`intake.md` 中的技术方向、版本范围和实现建议属于前期讨论输入；其中标注为建议或待 Spike/Spec 确认的事项，尚未自动成为生产实现决策。Spike-01 和 Spike-02 的结论只作为后续设计输入。

当前 Provider 路线决策：后续路线使用 Codex CLI 作为唯一真实 LLM Provider 候选，Mock 仅用于确定性测试；不实现 GLM API 和自动 fallback。intake 中早期的 GLM 相关内容保留为历史输入，不直接作为当前实现授权。

## Current scope

当前只处理模块 1「投资信息收集」。模块 2「选股研判」、模块 3「策略和复盘」和模块 4「投资体系」暂不进入实现范围。

模块 1 的前期目标是建立从 Discord/X 信息采集，到原始内容持久化、规则清洗、LLM 结构化理解、批次总结、日累计总结，再到网页阅读和证据回溯的可持续流水线。

## Repository state

当前仓库包含项目治理文档、Spike harness、V0 控制面/Worker 验证实现、确定性 E2E harness 和管理员调试面。真实内容、Codex Prompt、完整响应和本地 evidence 不进入 Git；隔离远程数据库迁移、Preview 部署、合成核心 HTTP、普通用户阻断、租约恢复和真实有界单页验收均已执行。

## Spike-01 result

- 确定性测试：32/32 通过；
- bounded soak：202 条原始消息成功采集；
- 两轮 evidence 合计：1504 条唯一 Canonical 消息；
- checkpoint 恢复、network 空窗和逐页 telemetry 验证通过；
- 决策结论：OpenCLI-first 可作为后续设计输入，但生产采用必须保留 freshness、有限重试、失败恢复和逐页 telemetry。

## Spike-01 Active Adapter 后续方向

- Active Adapter 不是第二套完整浏览器采集框架，而是基于 OpenCLI Browser Bridge，由项目侧主动控制 Discord 频道规范化、分页、响应匹配、freshness、有限重试和失败分类的采集适配层；Canonical Schema、Evidence Store 和 checkpoint 仍沿用项目边界。
- 后续验证结果：Active Adapter 确定性测试 24/24 通过，原始 Spike-01 回归测试 32/32 通过；完成 1008 条原始/Canonical 消息处理，其中 969 条接受、39 条标记为未解决关系，重复和无效消息均为 0，并验证了 checkpoint 恢复；缺失/陈旧响应降为 0，平均每页尝试次数由 20 降至 1.13。
- 证据边界：原始 Connector 对照运行使用了错误会话，首屏未成功，因此不能据此宣称严格的同条件性能提升；长期无人值守稳定性、长尾 P95、跨日期运行、网络变化和浏览器升级后的行为仍需在 V0 设计中继续验证。
- 当前决策：Active Adapter 作为 V0 Discord 抓取的候选主路径；原始 OpenCLI Connector 保留为诊断基线和必要时的回退候选。V0 已实现该边界，但真实页面稳定性和长期生产采用仍需补证据。

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

## V0 result

- 确定性验收：通过。控制面 30 个测试、Worker 46 个测试、Spike-01 回归 35 个测试、V0 E2E 8 个测试和 Supabase pgTAP 55 条断言均通过。
- 持久化收据：通过。Worker 必须先写入远程持久化收据；结果中的消息计数和结构化运行 ID 与收据不一致、或只有伪造的 `persisted` 标记时，数据库拒绝推进 checkpoint。
- 隔离远程部署：核心链路通过。已将第 002 号迁移应用至隔离 Supabase，最新 Vercel 预览为 Ready；通过受保护部署通道完成合成注册 → 心跳 → 领取 → 持久化 → 回报结果，并确认回执与检查点已落库。
- 安全与恢复：通过。邀请码单次消费、普通用户 403、lease 竞争、raw/Canonical/structured 持久化失败、Provider timeout、媒体来源精确链路和 checkpoint 不前移均有证据。
- 管理调试面：通过。状态区分 `no_new_data`、`retryable_failed`、`failed`、`succeeded_with_unresolved`、`succeeded`；Credential、Prompt、Profile reference 和完整模型响应不进入调试视图。
- 真实页面：通过。用户明确授权的专用浏览器配置档在第 2 次尝试完成一页真实 Discord 采集、Codex 结构化、远程持久化、证据关联和安全检查点回报；第 1 次超时被保留为可恢复失败。该证据只覆盖有界单页，不外推为历史回填或持续运营能力。
- 远程部署：通过。核心工作节点 HTTP、普通用户管理员阻断和租约/检查点恢复均已验收；不含真实 Discord 内容。

完整证据见 [V0 Engineering Journal](engineering-journal/2026-07-18-v0.md) 和 [V0 Final Report](spikes/2026-07-18-v0-decision-report.md)。

## Next gate

V0 的条件证据已补齐。进入 V1 前必须独立编写并批准 V1 Spec 与 Plan；在此之前不启动 V1 实现，不实现 X、多来源运营、正式阅读页、GLM 或自动 fallback。V0 的单页真实验收不是生产 SLA，也不替代未来的历史回填、持续增量和长期稳定性验证。
