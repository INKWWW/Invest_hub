# Invest Hub 项目治理

## 项目定位

Invest Hub 面向个人及少量受邀用户，是一个持续沉淀外部投研信息、个人判断、交易策略和复盘结果的投资信息与投资决策工作台。

当前模块化主线只讨论和开发模块 1：投资信息收集。模块 2（选股研判）、模块 3（策略和复盘）和模块 4（投资体系）不属于当前范围，但模块 1 的数据结构应为后续模块保留关联来源、作者、标的、时间、观点、操作倾向、证据和摘要版本的能力。另有独立于模块 2–4 的“投资研究 Agent”能力，其实现范围只以 `docs/project-status.md` 中记录的已批准 Feature Contract 与 Delivery Plan 为准，不自动开放模块 2–4。

## 事实来源与决策边界

- `docs/intake.md` 是项目背景、需求输入、前期讨论方案和未决事项的事实来源；当前阶段、批准状态、已完成结果和下一门禁以 `docs/project-status.md` 为准。
- 不得擅自改写 `docs/intake.md` 中已经记录的事实、范围、约束或前期讨论结论。
- intake 中标注为“建议”“总体技术方向”“待 Spike 或 Spec 阶段确认”的内容，不得在 Discovery 阶段当作最终技术选型、正式架构或实现承诺。
- 任何新决策都必须记录在 `docs/agents/workflow.md` 定义的对应权威文档中；只有已批准的 Feature Contract 和 Delivery Plan 能产生实现授权。

## 当前阶段与授权门禁

开始或继续任何 feature 前，必须先读取 `docs/project-status.md` 确认当前阶段、已批准范围和下一门禁，再按 [`docs/agents/workflow.md`](docs/agents/workflow.md) 确认该 feature 的唯一 workflow profile、Feature Contract 和 Delivery Plan。

在 Feature Contract 和 Delivery Plan 分别获得批准前：

- 只允许进行需求澄清、方案审阅、技术 Spike 设计或执行、数据与验收标准讨论，以及治理文档维护；
- 不得生成应用代码、框架脚手架或应用代码目录；
- 不得选择或固化技术栈；
- 不得安装生产依赖；
- 不得把 intake、roadmap、CONTEXT、ADR、triage label 或历史文档直接当作实现授权。

已批准产物只授权其中明确记录的范围。Git push、远程 migration、生产写入、部署、Worker 操作、真实 Provider 调用和会改变外部状态的生产验收，仍须在 Delivery Plan 或独立 release ticket 中明确列出并获得对应授权。

## 产品与工程原则

- 事实优先：总结必须基于实际采集到的文本；原始事实、发言者观点、系统归纳和不确定判断必须区分；未解析的媒体或外部文章正文不得被臆测。
- 内容优先：阅读层以总结内容为主，运行状态、生成时间、覆盖范围和 Provider 等元信息后置。
- 可追溯：原始 Discord/X 内容按 intake 约定保留一年，摘要长期保留；在保留期内支持从总结回溯到原始消息或原始链接。
- 增量处理：来源使用 checkpoint 增量同步；数据成功持久化后才能推进 checkpoint；离线恢复应补采，单来源失败不得阻断其他来源。
- 低成本优先：优先控制并发、局部重试、结构化缓存和 fallback，同时以最终可用性为目标。
- 可迁移：认证、数据、任务和 LLM Provider 等边界不应过度绑定单一平台；任何具体实现仍需经过 Spike/Spec 确认。

## 信息采集边界

前期方案采用 OpenCLI-first：OpenCLI 负责浏览器采集运行时、登录态复用、Browser Bridge、DOM/网络数据读取和 Adapter/Plugin 执行；业务逻辑应通过 Discord/X Connector 和 Invest Hub Canonical Schema 隔离原始输出。Playwright/CDP 只作为特定场景的局部后备，不提前建设第二套完整采集框架。以上仍须通过 Spike 验证，不得在本阶段固化实现。

只采集用户本人已加入、已付费或有权限访问、且在已登录网页中正常可见的 Discord 频道，以及用户已登录 X 网页版中配置的指定博主内容。专用浏览器 Profile 不得登录邮箱、金融账户或其他无关账号。

V1 媒体处理边界保持为：保存附件/媒体元数据和链接，但不解析图片、PDF、表格、视频、语音、OCR 或外部文章正文；核心信息依赖未解析内容时，必须明确标记，不得生成确定性结论。

## 用户与数据边界

系统只有管理员和普通用户两个角色。所有用户共享同一套已生成数据；V1 不支持用户独立信息源、独立数据空间、阅读进度、已读未读或未读数量。管理员配置和任务操作必须与普通用户阅读权限隔离。

项目按未来可能公开的标准管理：密钥、Cookie、Chrome Profile、私有频道/博主信息、邀请码、私有 Prompt、真实 fixture 和历史数据不得进入 Git。真实 fixture 即使脱敏也只保存在本地；仓库只允许人工构造的公开 fixture。

## 工作方式

- **工作流强制前置：** 新 Agent 能力默认采用 Matt Pocock profile；已有 Superpowers Spec/Plan 的模块 1 工作继续沿用 Superpowers。任何 feature 开始前必须读取 [`docs/agents/workflow.md`](docs/agents/workflow.md)；`ready-for-agent` 只表示材料就绪，不等于用户批准；一个 feature 同一时间只能有一个权威执行来源。
- **强制前置阅读：** 任何开发、需求澄清、Spec、Plan、实现、测试、独立复核、发布或生产验收任务开始前，必须先阅读 [`docs/project-pitfalls-reflections.md`](docs/project-pitfalls-reflections.md)。如果任务涉及评估集、Prompt、LLM、结构化输出、数据边界或 release gate，必须逐条执行该文档中的对应检查；发现同类根因重复出现时，暂停局部修复并回到 Spec/Plan 修订。
- 先确认范围、事实来源、未决问题和验收标准，再提出方案。
- 确定性工作由程序完成，LLM 只负责 intake 所述的结构化理解、分类、提炼和总结；输出必须可校验、可追溯、可恢复。
- 默认坚持幂等、局部重试、任务恢复、版本记录和可回滚；任何例外必须在批准的 plan 中说明。
- 只在代码测试中进行对抗式审查；非代码治理讨论不提前引入实现性审查。
- 完成任何阶段前，检查是否越过当前阶段门禁，并核对文件树、Git diff、测试/Spike 结果和未决项。

## Agent skills

### Issue tracker

Matt profile 的 issues 和 specs 使用 `.scratch/<feature-slug>/`；既有 Superpowers 产物继续保留在 `docs/superpowers/`。参见 `docs/agents/issue-tracker.md`。

### Triage labels

Uses the default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: root `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.
