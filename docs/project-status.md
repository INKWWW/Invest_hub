# Project Status

## Current phase

**Discovery / Spike-01 已完成**

项目仍处于 Discovery，不代表已经进入 V0/V1 生产实现。Spike-01 已完成真实网页轨验证，当前准备进入下一个独立 Spike 的需求澄清阶段。

## Approval status

- Approved specification：
  - [模块 1 总体设计](superpowers/specs/2026-07-15-invest-hub-module-1-project-design.md)
  - [Spike-01 Discord 增量采集设计](superpowers/specs/2026-07-15-spike-01-opencli-discord-incremental-design.md)
- Approved implementation plan：
  - [Spike-01 Discord 增量采集计划](superpowers/plans/2026-07-15-spike-01-opencli-discord-implementation-plan.md)
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

没有初始化生产应用框架，也没有安装生产依赖。真实 Discord evidence 保存在本地受保护目录，不进入 Git。

## Spike-01 result

- 确定性测试：32/32 通过；
- bounded soak：202 条原始消息成功采集；
- 第一轮真实采集：1392 条唯一 Canonical 消息；
- 第二轮 checkpoint 恢复：新增 112 条，0 duplicate、0 invalid；
- 两轮 evidence 合计：1504 条唯一 Canonical 消息；
- network 空窗通过 checkpoint-resume 安全处理；
- 决策结论：OpenCLI-first 可作为后续设计输入，但生产采用必须保留 freshness、有限重试、失败恢复和逐页 telemetry。

## Next gate

下一阶段应先审阅和澄清 [docs/intake.md](intake.md) 中与 Spike-02 相关的未决事项，再独立形成 Spike-02 specification 和 implementation plan。Spike-02 的文档尚未创建或批准。

在 Spike-02 spec 和 plan 获得批准前：

- 不开始 Spike-02 实现；
- 不启动 V0/V1 生产实现；
- 不把 Spike-01 harness 直接升级为生产应用；
- 不把 OpenCLI、Discord Desktop 或官方 API 固化为最终生产架构。
