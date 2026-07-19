# Invest Hub 文档导航

本目录记录 Invest Hub 的需求输入、阶段设计、执行过程、架构决策和阶段结果。

## 文档职责

| 文档 | 回答的问题 | 写作时机 |
| --- | --- | --- |
| Intake | 项目背景和待验证输入是什么 | 项目输入阶段 |
| Spec | 做什么、为什么做、做到什么算成功 | 设计阶段，实施前批准 |
| Plan | 这一阶段准备怎么做 | Spec 批准后、实施前批准 |
| Engineering Journal | 实际发生了什么、试过什么、为什么调整 | 执行过程中持续记录 |
| ADR | 为什么最终选择 A，而不是 B | 出现需要长期沿用的架构决策时 |
| Final Report | 阶段结果、证据、遗留问题和下一阶段门槛是什么 | 阶段结束时 |

## 当前文档结构

```text
docs/
├── README.md
├── intake.md
├── project-status.md
├── superpowers/
│   ├── specs/
│   └── plans/
├── engineering-journal/
│   ├── 2026-07-15-spike-01.md
│   ├── 2026-07-15-spike-02.md
│   └── 2026-07-18-v0.md
└── spikes/
    ├── 2026-07-15-spike-01-decision-report.md
    ├── 2026-07-15-spike-02-decision-report.md
    └── 2026-07-18-v0-decision-report.md
```

当前暂不创建 `docs/adr/`。Spike-01 的架构取舍已在其 Spec 和 Final Report 中记录；当 Spike-02 或 V0 产生需要跨阶段沿用的正式架构决策时，再新增独立 ADR。

## 推荐工作流

```text
intake
  → brainstorming
  → spec
  → 用户批准
  → implementation plan
  → 用户批准
  → 执行与测试
  → Engineering Journal + Final Report
  → 更新 project-status
```

每个 Spike、V0 或 V1 都应拥有独立的 Spec、Plan、执行记录和 Final Report。后续阶段不得把前一阶段的 Plan 直接当作实现授权。

## 当前入口

- [项目状态](project-status.md)
- [项目输入](intake.md)
- [模块 1 总体设计](superpowers/specs/2026-07-15-invest-hub-module-1-project-design.md)
- [Spike-01 Spec](superpowers/specs/2026-07-15-spike-01-opencli-discord-incremental-design.md)
- [Spike-01 Plan](superpowers/plans/2026-07-15-spike-01-opencli-discord-implementation-plan.md)
- [Spike-01 Engineering Journal](engineering-journal/2026-07-15-spike-01.md)
- [Spike-01 Final Report](spikes/2026-07-15-spike-01-decision-report.md)
- [Spike-02 Engineering Journal](engineering-journal/2026-07-15-spike-02.md)
- [Spike-02 Final Report](spikes/2026-07-15-spike-02-decision-report.md)
- [V0 基础设施与技术验证 Spec（已批准）](superpowers/specs/2026-07-18-v0-infrastructure-technical-validation-design.md)
- [V0 基础设施与技术验证 Plan（已批准）](superpowers/plans/2026-07-18-v0-infrastructure-technical-validation.md)
- [V0 Engineering Journal](engineering-journal/2026-07-18-v0.md)
- [V0 Final Report（通过：有界单页真实 Discord 验证）](spikes/2026-07-18-v0-decision-report.md)
- [V1 Discord 正式可用 MVP Spec（已批准）](superpowers/specs/2026-07-19-v1-discord-mvp-design.md)
- [V1 Discord 正式可用 MVP Plan（已批准）](superpowers/plans/2026-07-19-v1-discord-mvp.md)
