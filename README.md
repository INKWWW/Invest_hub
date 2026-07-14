# Invest Hub

Invest Hub 是面向个人及少量受邀用户的投资信息与投资决策工作台，目标是持续沉淀外部投研信息、个人判断、交易策略和复盘结果。

当前范围只有模块 1「投资信息收集」：将 Discord 和 X 的外部信息经过采集、持久化、规则清洗、结构化理解和分批次/日累计总结后，提供网页阅读与证据回溯能力。后续模块不在当前实现范围内。

## 当前状态

项目处于 Discovery 阶段。尚无批准后的 specification 和 implementation plan，因此当前仓库只维护需求输入和项目治理结构，不包含应用代码、框架脚手架或生产依赖。

详见 [docs/project-status.md](docs/project-status.md)。

## 重要文档

- [docs/intake.md](docs/intake.md)：前期讨论形成的需求输入、产品边界、推进版本、测试要求和待确认事项。
- [AGENTS.md](AGENTS.md)：项目治理规则、当前阶段门禁、数据安全和工作方式。
- [docs/project-status.md](docs/project-status.md)：当前阶段、批准状态和后续工作入口。

## 后续推进方向

按 intake 中的建议，后续先审阅和澄清需求，再分别推进 OpenCLI Discord Web 采集 Spike、LLM 容量 Spike、V0 基础设施、V1 Discord、V2 X 和 V3 收敛。每个阶段都应先形成并批准对应的 specification 和 implementation plan，再进入实现。

## 安全边界

不要提交密钥、Cookie、Chrome Profile、私有来源信息、邀请码、私有 Prompt、真实 fixture 或历史数据。项目从一开始按未来可能公开的仓库标准管理。
