# Invest Hub

Invest Hub 是面向个人及少量受邀用户的投资信息与投资决策工作台，目标是持续沉淀外部投研信息、个人判断、交易策略和复盘结果。

当前范围只有模块 1「投资信息收集」：将 Discord 和 X 的外部信息经过采集、持久化、规则清洗、结构化理解和分批次/日累计总结后，提供网页阅读与证据回溯能力。后续模块不在当前实现范围内。

## 当前状态

V0「基础设施与技术验证」已通过：控制面、工作节点、Active Adapter、Provider 边界、管理员调试页、RLS 和恢复测试框架均已验证。隔离 Supabase 迁移和 Vercel 预览已部署；合成任务已完成远程注册 → 心跳 → 领取 → 持久化 → 回报结果并确认检查点落库，普通用户管理员阻断与租约恢复也已补测。2026-07-19 已完成用户明确授权的真实 Discord 有界单页任务：首次超时未推进检查点，第 2 次完成采集、结构化、远程持久化、结果回报与非空安全检查点确认。该结论不是生产发布批准，也不外推为历史回填或持续运营能力。

仓库现在包含 V0 验证实现和脱敏 E2E harness，但不包含真实内容、凭据、Prompt、完整响应或本地 evidence。V0 的真实页面和远程部署验收已完成；进入 V1 必须独立编写并批准 V1 Spec 与 implementation plan。

详见 [docs/project-status.md](docs/project-status.md)。

## 重要文档

- [docs/intake.md](docs/intake.md)：前期讨论形成的需求输入、产品边界、推进版本、测试要求和待确认事项。
- [AGENTS.md](AGENTS.md)：项目治理规则、当前阶段门禁、数据安全和工作方式。
- [docs/project-status.md](docs/project-status.md)：当前阶段、批准状态和后续工作入口。
- [docs/superpowers/specs/2026-07-18-v0-infrastructure-technical-validation-design.md](docs/superpowers/specs/2026-07-18-v0-infrastructure-technical-validation-design.md)：V0 已批准 Spec。
- [docs/superpowers/plans/2026-07-18-v0-infrastructure-technical-validation.md](docs/superpowers/plans/2026-07-18-v0-infrastructure-technical-validation.md)：V0 已批准 implementation plan。
- [docs/engineering-journal/2026-07-18-v0.md](docs/engineering-journal/2026-07-18-v0.md)：V0 执行记录与验证证据。
- [docs/spikes/2026-07-18-v0-decision-report.md](docs/spikes/2026-07-18-v0-decision-report.md)：V0 脱敏 Final Report。
- [docs/superpowers/specs/2026-07-19-v1-discord-mvp-design.md](docs/superpowers/specs/2026-07-19-v1-discord-mvp-design.md)：V1 Discord 正式可用 MVP Spec（已批准）。
- [docs/superpowers/plans/2026-07-19-v1-discord-mvp.md](docs/superpowers/plans/2026-07-19-v1-discord-mvp.md)：V1 implementation plan（已批准）。

## 后续推进方向

V1 Spec 与 implementation plan 已批准，下一步选择执行方式后启动 V1 实现。V2 X、V3 收敛以及模块 2–4 仍不在当前范围。

## 安全边界

不要提交密钥、Cookie、Chrome Profile、私有来源信息、邀请码、私有 Prompt、真实 fixture 或历史数据。项目从一开始按未来可能公开的仓库标准管理。
