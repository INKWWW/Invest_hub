# Project Status

## Current phase

**Discovery / Spike-01 已完成，Spike-02 harness 已完成但 GLM 真实轨未验证**

项目仍处于 Discovery，不代表已经进入 V0/V1 生产实现。Spike-01 已完成真实网页轨验证，Spike-02 harness 已完成，当前等待真实 GLM 轨验证。

## Approval status

- Approved specification：
  - [模块 1 总体设计](superpowers/specs/2026-07-15-invest-hub-module-1-project-design.md)
  - [Spike-01 Discord 增量采集设计](superpowers/specs/2026-07-15-spike-01-opencli-discord-incremental-design.md)
- Approved implementation plan：
  - [Spike-01 Discord 增量采集计划](superpowers/plans/2026-07-15-spike-01-opencli-discord-implementation-plan.md)
  - [Spike-02 免费 LLM 容量与质量计划](superpowers/plans/2026-07-15-spike-02-free-llm-capacity-quality.md)
- Approved technology stack：无

`intake.md` 中的技术方向、版本范围和实现建议属于前期讨论输入；其中标注为建议或待 Spike/Spec 确认的事项，尚未自动成为生产实现决策。Spike-01 的 OpenCLI-first 结论只作为带恢复和遥测约束的后续设计输入。

## Current scope

当前只处理模块 1「投资信息收集」。模块 2「选股研判」、模块 3「策略和复盘」和模块 4「投资体系」暂不进入实现范围。

模块 1 的前期目标是建立从 Discord/X 信息采集，到原始内容持久化、规则清洗、LLM 结构化理解、批次总结、日累计总结，再到网页阅读和证据回溯的可持续流水线。

## Repository state

当前仓库包含项目治理文档和已完成的 Spike-01 harness：

- `AGENTS.md`
- `README.md`
- `.gitignore`
- `docs/project-status.md`
- `docs/README.md`
- `docs/spikes/2026-07-15-spike-01-decision-report.md`
- `spikes/spike_01/`：仅限 Spike 验证，不是生产应用代码
- `spikes/spike_02/`：仅限免费 LLM 容量与质量验证，不是生产应用代码

没有初始化生产应用框架，也没有安装生产依赖。真实 Discord evidence 保存在本地受保护目录，不进入 Git。

## Spike-01 result

- 确定性测试：32/32 通过；
- bounded soak：202 条原始消息成功采集；
- 第一轮真实采集：1392 条唯一 Canonical 消息；
- 第二轮 checkpoint 恢复：新增 112 条，0 duplicate、0 invalid；
- 两轮 evidence 合计：1504 条唯一 Canonical 消息；
- network 空窗通过 checkpoint-resume 安全处理；
- 决策结论：OpenCLI-first 可作为后续设计输入，但生产采用必须保留 freshness、有限重试、失败恢复和逐页 telemetry。

## Spike-02 result

- 确定性测试：27/27 通过；
- Mock 小批次、约 500 条和 1000 条以上规模运行可以完成；
- 1000 条合成 fixture 在 chunk size 25/100 下分别产生 40/10 次 Mock 请求，最终成功率和 JSON 解析率均为 100%；
- 真实 GLM 未运行，结论为 `unverified`，没有真实容量、质量、P95 或 token 观测；
- 脱敏决策报告：[Spike-02 决策报告](spikes/2026-07-15-spike-02-decision-report.md)。

Mock 结果不等同于 GLM 通过，也不批准 V0/V1 生产实现。

## Next gate

下一阶段需要在本地受保护环境提供 GLM 运行配置，完成小批次、约 500 条和 1000 条以上真实 GLM 验证及人工质量复核，再根据证据更新 Spike-02 结论。

在真实 GLM 结论明确、后续正式 Spec 和 plan 获得批准前：

- 不把现有 Spike-02 harness 直接升级为生产实现；
- 不启动 V0/V1 生产实现；
- 不把 Spike-01 harness 直接升级为生产应用；
- 不把 OpenCLI、Discord Desktop 或官方 API 固化为最终生产架构。
