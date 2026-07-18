# V0：基础设施与技术验证 Spec

## 文档状态

- 阶段：V0 / 基础设施与技术验证
- 书面状态：已批准（用户确认 2026-07-18）；implementation plan 已批准并已执行
- 日期：2026-07-18
- 事实输入：[项目总 Spec](2026-07-15-invest-hub-module-1-project-design.md)、[项目状态](../../project-status.md)、[Spike-01 决策报告](../../spikes/2026-07-15-spike-01-decision-report.md)、[Spike-02 决策报告](../../spikes/2026-07-15-spike-02-decision-report.md)、[intake](../../intake.md)
- 前置结论：Spike-01 通过；Spike-02 在已记录的本机 Codex CLI 条件下有条件通过。
- 本文性质：V0 的正式设计草案，不是 implementation plan，也不授权应用代码、生产依赖安装或部署。

本文提出 V0 的最小端到端验证边界。只有本文和对应 implementation plan 分别获得用户批准后，才可开始 V0 实现；V0 退出后仍须为 V1 单独编写 Spec 和 Plan。

## 1. 问题本质与 V0 目标

模块 1 的产品价值不是“网页可以显示抓到的消息”，而是把用户本地可见的外部信息，可靠地加工为云端可追溯、可恢复、权限隔离的数据。这个链路的两个事实约束是：浏览器登录态必须留在用户本地；而任务、数据、权限和阅读结果需要在云端统一管理。

Spike-01 已证明 OpenCLI Browser Bridge 可以在受控条件下采集 Discord，Spike-02 已证明 Codex CLI 能在受控条件下给出合格的结构化结果。两者都只是局部技术证据，尚未证明以下生产前提能共同成立：

1. 云端可以安全管理用户、邀请码、角色、Worker 和任务；
2. 本地 Worker 可以在不上传 Chrome Profile、Cookie 或凭据的条件下领取、执行和恢复任务；
3. 单个 Discord 来源的原始事实、Canonical 数据、结构化结果、运行证据与 checkpoint 可以端到端保持一致；
4. 任务中断、页面/Provider 失败和重复投递不会越过 checkpoint、丢失已保存事实或制造重复数据；
5. 管理员能从调试界面定位任务、来源、chunk、Provider、校验和失败状态，而普通用户不能越权读取管理数据。

因此 V0 的目标是验证一个最小的“云端控制面 + 本地执行面”闭环。它不是 Discord 正式阅读产品，也不是多来源运营版本。V0 成功只表示该闭环具备进入 V1 设计的事实基础。

## 2. V0 范围与非目标

### 2.1 范围

V0 只验证一个管理员配置的 Discord 来源、一个已注册本地 Worker 和一次或多次手动触发的 `discord_sync` 任务。它包含：

- 云端登录、邀请码注册、管理员/普通用户角色和数据库级访问隔离；
- Worker 注册、撤销、心跳、任务领取、租约、恢复和状态回报；
- 管理员创建、查看、重试一个来源级同步任务；
- 本地专用 Chrome Profile 与 OpenCLI 的前置检查，不把 Profile 或网页登录凭据上传到云端；
- 以 Active Adapter 为候选主路径的 Discord 抓取；原 OpenCLI Connector 只作为诊断基线和必要时的回退候选；
- Canonical 消息、未解决关系、未解析媒体元数据、checkpoint、Provider 调用和结构化输出的持久化与可追溯链接；
- Codex CLI 作为唯一真实 LLM Provider 候选，以及 Mock Provider 的确定性测试路径；
- 管理员调试页，展示任务、Worker、来源、checkpoint、chunk 范围、Provider 运行、Schema 校验、重试及脱敏错误；
- 公开 fixture 的自动化测试、真实授权 Discord 页面的一次端到端验证，以及中断恢复验证。

### 2.2 非目标

V0 明确不包含：

- 正式 Discord 阅读页、日累计总结、批次总结的面向用户体验、历史版本浏览或移动端体验；
- X 采集、X 配置、跨来源聚合、跨频道话题聚合和模块 2–4；
- 多频道批量运营、定时调度、开机补采、正式长期无人值守 SLA；
- 图片、PDF、表格、视频、语音、OCR 或外部文章正文解析；
- 自动 Provider fallback、GLM API、第二个真实 Provider 或将 Codex CLI 固化为最终 Provider；
- 将 Spike harness、Spike evidence 或 Browser Bridge 的具体命令直接升格为生产实现；
- Desktop 客户端、Playwright/CDP 的第二套完整采集框架和 Agent-Reach；
- 生产容量扩展、10 并发默认启用、250/500 chunk 重试，或将公开 fixture 质量外推为真实业务质量。

## 3. 待批准的 V0 技术验证选择

V0 需要真正部署最小闭环，才能验证云端控制面与本地执行面的边界。为避免在未验证前预设大平台，本文提出以下**仅限 V0 的候选实现组合**，等待本 Spec 批准后生效：

| 边界 | V0 候选 | 选择理由 | V0 不承诺的内容 |
| --- | --- | --- | --- |
| 云端 Web 与管理 API | Next.js + TypeScript，部署在 Vercel | 验证管理界面、受保护路由与控制面 API 的最小组合 | 不承诺永久前端框架或完整产品 UI |
| 身份、数据库与 RLS | Supabase Auth + Postgres + RLS | 在 V0 内验证邀请码、角色和数据库级数据隔离 | 不承诺最终 BaaS 或全部数据模型 |
| 本地 Worker | Python 3.11+ 独立进程 | 与已验证的 Spike 边界相邻，便于单独持有本地浏览器状态 | 不复用或直接发布 Spike harness |
| 浏览器采集 | OpenCLI Browser Bridge + Active Adapter | 继承 Spike-01 的已验证候选主路径 | 不把具体 OpenCLI 命令当作永久公共接口 |
| 结构化 Provider | 本机已登录 Codex CLI；Mock 用于测试 | 继承 Spike-02 的唯一真实 Provider 候选 | 不承诺最终模型、成本或自动 fallback |

任何一项候选在 V0 实测不通过时，先记录失败、保留数据和证据，并为替代方案另写增量 Spec/Plan；不得在 V0 实现中临时替换成未经验证的平台或 Provider。

## 4. 角色、信任边界与权限

### 4.1 角色

| 角色 | V0 权限 | 明确禁止 |
| --- | --- | --- |
| 管理员 | 管理邀请码、查看/撤销 Worker、创建/重试任务、查看来源与完整调试数据 | 读取或导出 Worker 的 Profile、Cookie、Token |
| 普通用户 | 邀请码注册、登录、查看一个最小的“暂无正式阅读页”占位入口 | 访问管理路由、任务、来源、Worker、完整诊断、原始调试输出 |
| 本地 Worker | 用自己的注册凭据发送心跳、领取授权任务、上传任务结果与脱敏诊断 | 读取其他 Worker、其他来源或非授权任务；上传浏览器凭据 |

V0 允许普通用户存在是为了验证 Auth、邀请码和 RLS，而不是交付阅读体验。普通用户对共享内容的正式阅读授权在 V1 Spec 再定义。

### 4.2 不可跨越的信任边界

- 专用 Chrome Profile、Cookie、Token、密码、Discord URL 私密部分、完整 Prompt 和完整 Codex 响应仅留在本地受保护目录；不得上传数据库、日志、Vercel、Git 或任务 payload。
- 云端的 `source_id` 只标识一个逻辑来源。Worker 在本地受保护配置中维护 `source_id → Discord channel URL + Profile reference + OpenCLI contract version` 的映射；云端任务只携带 `source_id`、运行参数版本和必要的非敏感范围，不得包含 URL、Profile 路径、Cookie 或浏览器命令行。
- 管理员生成一次性 Worker enrolment code；Worker 仅在本地用它换取随机设备密钥，云端只保存密钥 hash。code 被消费、过期或 Worker 被撤销后不得再用于领取任务。
- Worker 启动前必须验证本地 Profile 与 OpenCLI contract；登录失效、无权限或 contract 不匹配必须返回可恢复的前置条件失败，而不是空数据成功。
- 云端持久化原始内容、Canonical 数据和结构化输出时，所有访问均经 RLS；管理员调试输出必须脱敏，不显示 Cookie、Token、Prompt 正文、完整模型响应或 Profile 路径。

## 5. 最小领域模型与一致性规则

V0 只建立支撑闭环所需的数据，不提前建设 V1 阅读、全文搜索或跨来源分析模型。名称可随 implementation plan 调整，但下列身份、关系和不变量不可改变。

| 实体 | 最小字段与关系 | 关键不变量 |
| --- | --- | --- |
| `profiles` / `roles` | `user_id`、`role`、创建/停用时间 | 仅 `admin` 可操作控制面；角色不由客户端请求体决定 |
| `invites` | 不可逆 token hash、状态、过期时间、使用者 | token 明文只在生成时显示一次；每个邀请码最多成功消费一次 |
| `workers` | Worker ID、凭据 hash、状态、最后心跳、能力版本 | Worker 凭据可撤销；离线不等于永久失败 |
| `sources` | 逻辑来源 ID、类型、启停、授权 Worker、非敏感配置版本 | V0 仅一条 Discord 来源；不得保存真实 URL 或 Profile 路径 |
| `sync_tasks` | task ID、来源、状态、尝试数、lease、触发者、失败分类 | 每个 task 在一个时刻最多被一个有效 lease 执行 |
| `checkpoints` | 来源、最后安全边界、版本、更新时间 | 只有原始、Canonical、校验和相关运行记录成功持久化后才推进 |
| `raw_messages` / `canonical_messages` | 来源外部 ID、内容、作者、时间、关系/媒体元数据、run ID | `(source_id, external_message_id)` 唯一；重复投递不得重复写入 |
| `structured_runs` / `structured_outputs` | 输入 message ID 集合、chunk 序号、Provider、Prompt 版本、状态、输出版本 | 每个输出可回溯至输入 Canonical ID；Schema 失败不得标为成功 |
| `task_events` | task、阶段、时间、脱敏分类、retry 信息 | 只追加；不得通过覆盖事件抹去失败事实 |

### 5.1 任务状态机

`queued → leased → running → succeeded` 是正常路径。`leased` 或 `running` 遇到可恢复问题进入 `retryable_failed`；管理员重试或租约到期恢复后创建新的 attempt，并回到 `queued`。不可恢复的前置条件、权限、Schema 或人工停止进入 `failed` 或 `cancelled`，保留原因和安全 checkpoint。

Worker 只能原子领取 `queued` 且来源授权给它的任务；领取动作写入 lease owner、lease expiry 和 attempt。Worker 每 60 秒发送心跳，并在剩余 lease 小于 2 分钟时续租。默认 lease 为 10 分钟；单个同步阶段不得无限延长，超时必须写事件并走恢复状态。若 Worker 失联或 lease 到期，云端不得假定任务成功，也不得推进 checkpoint；恢复时从最后安全 checkpoint 重新处理，依靠唯一键保证幂等。

### 5.2 来源同步顺序

一次 `discord_sync` 的顺序固定如下：

1. Worker 完成本地预检：OpenCLI contract、专用 Profile、Discord 登录态、来源可访问性；
2. Worker 领取任务并报告 `running`；
3. Active Adapter 采集当前 checkpoint 之后的候选消息，记录逐页 telemetry、freshness 和失败分类；
4. 先保存原始采集事实，再映射/验证 Canonical Schema；未知回复或引用保留 `unresolved`，不伪造关系；
5. 对新 Canonical 消息进行确定性去重、排序、分块；未解析媒体仅保存元数据和链接标识，不推断内容；
6. 使用 Mock 或 Codex CLI 进行结构化调用，保存 Provider、模型报告值、Prompt 版本标识、输入范围、耗时、重试和 Schema 结果；
7. 所有必要持久化和校验成功后，推进 checkpoint；
8. 回报 task 终态和脱敏事件。任何中断只保留已安全完成的范围。

## 6. Worker、采集与 Provider 约束

### 6.1 Discord 采集

- Active Adapter 是 V0 候选主路径，必须由项目侧控制频道路由规范化、分页、响应匹配、freshness、有限重试、失败分类和逐页 telemetry。
- 原 OpenCLI Connector 不承担字段补齐；仅作为诊断基线或经过任务记录的必要回退候选。
- 每页操作保留 90 秒硬截止作为失控保护。超时、missing/stale response、登录失效和无权限不得被记作空页面或成功。
- 本地运行必须记录 OpenCLI 版本/contract 标识，不在云端保存具体命令或敏感路径。
- V0 实际验证至少覆盖一次用户有权限的真实 Discord 页面；真实正文和 raw evidence 不进入 Git。

### 6.2 Codex CLI 结构化调用

- 真实 Provider 仅为本机已登录 Codex CLI；Mock 仅用于确定性测试。
- 起始候选参数为 `chunk_size=100`、`max_concurrency=5`、单请求 timeout 240 秒、最多 3 次尝试。失败 chunk 独立重试；必要时经明确任务事件将并发降至 2。
- `chunk_size=250/500` 是已验证不稳定的配置，V0 不得启用。`max_concurrency=10` 仅作未来扩容候选，V0 不得设为默认。
- 每个真实调用必须以只读项目边界执行，并保存可审计的运行元数据；完整 Prompt、原始模型响应和诊断只留本地受保护目录。
- 不实现 GLM、其他真实 Provider 或自动 fallback。Codex 连续失败时保存失败状态、输入范围和可重试入口。
- 输出必须通过 JSON Schema、输入来源 ID、归因及未解析媒体来源链路校验；未解析媒体必须显式标记，并覆盖对应消息 ID，不得推断其内容。

## 7. 管理员调试体验

V0 只交付管理员调试页，不交付普通用户正式阅读页。界面内容优先级为“当前是否可安全运行和恢复”，不是运营仪表盘。

管理员至少能查看：

- Worker 在线/离线、最后心跳、能力/contract 版本和撤销状态；
- V0 的单个 Discord 来源状态、最后安全 checkpoint、最近成功/失败时间；
- 每个任务的状态、attempt、lease、阶段、重试数、失败分类和恢复入口；
- 运行的原始/Canonical 计数、重复数、unresolved 数、未解析媒体数、chunk 输入范围；
- Provider、模型报告值、Prompt 版本标识、P50/P95、Schema 校验和结果状态；
- 脱敏错误和 evidence 索引，而不是原始 Credential、Profile 路径、Prompt 正文或完整模型响应。

页面必须区分“无新数据”“可恢复失败”“不可恢复失败”“成功但有 unresolved”四种状态，禁止用一个泛化的成功/失败徽章掩盖差异。

## 8. 验收标准与退出门槛

### 8.1 自动化与安全验收

1. 所有 V0 确定性测试通过；测试只使用人工构造公开 fixture、Mock 和受控 fake boundary，不包含真实正文、Cookie、Token、Profile 或私有 Prompt。
2. 邀请码只能消费一次；管理员和普通用户的路由/API/RLS 测试证明普通用户无法读取或修改控制面数据。
3. Worker 未注册、已撤销、来源未授权、过期 lease、心跳丢失和重复领取均被拒绝或进入明确的恢复状态。
4. 同一 `(source_id, external_message_id)` 的重复上传不创建重复 Canonical 数据；同一 task attempt 的重复回报不改变已完成 checkpoint。
5. 任何原始/Canonical/结构化持久化失败、Schema 失败或 task 中断，都不能推进 checkpoint。
6. 登录失效、无权限、OpenCLI contract 不匹配、missing/stale response、Provider timeout、无效 JSON 和 Schema 错误都有可查询的脱敏失败分类。
7. 未解析媒体没有内容推断；媒体来源链接必须能追溯到对应输入消息 ID。

### 8.2 部署端到端验收

1. 云端控制面、数据库和一个本地 Worker 成功连通；Worker 注册、心跳、任务领取和任务终态均能在管理员调试页看到。
2. 管理员通过邀请流程创建一个普通用户，验证角色和 RLS；普通用户不能访问管理路由和调试 API。
3. 管理员手动创建一次 `discord_sync`，Worker 从已授权的真实 Discord 页面实际采集至少一个增量页；不得用人工导出、离线导入或人工注入消息替代。
4. 本次运行对写入的消息完成 raw → Canonical → 结构化结果的可追溯关系；管理员能从任务查看每个 chunk 的输入范围、Provider 结果和 Schema 状态。
5. 在安全 checkpoint 前人为中断一次运行或使 lease 到期；恢复后没有重复 Canonical 数据、没有跳过未确认数据，并从最后安全 checkpoint 继续。
6. 对真实 Provider 的 V0 验证使用 c100/c5/240 秒/最多 3 次尝试候选参数；若出现可恢复失败，必须记录重试和降并发行为，不得隐瞒为首次成功。
7. 验证过程不把真实内容、私人来源、Cookie、Profile、密钥、完整 Prompt 或完整 Codex 响应写入 Git、部署日志或云端调试页面。

### 8.3 V0 退出结论

只有 8.1 和 8.2 全部满足，且所有阻断问题已修复或被明确判定为失败，V0 才能结论为“通过”。若闭环可运行但有明确运行限制，例如 Codex 可恢复 timeout、浏览器版本前置条件或不可接受的稳定性缺口，结论只能为“有条件通过”，并将限制输入 V1 Spec。

任何权限绕过、checkpoint 越过未确认数据、原始事实丢失、不可追溯结构化输出、凭据外泄、无法恢复的重复写入，均为阻断失败。V0 失败不允许直接跳到 V1；必须先记录证据，并为修复或替代路线编写增量 Spec/Plan。

## 9. 交付物、测试证据与阶段门禁

本文批准后才可编写 V0 implementation plan。Plan 必须精确列出应用目录、数据库迁移、RLS policy、Worker 协议、任务接口、管理路由、测试和部署步骤；不得把本文中的候选描述当作未审阅的代码授权。

V0 实施完成时必须产出：

- V0 implementation plan、工程日志和脱敏 Final Report；
- 可复现的公开 fixture 测试结果；
- 本地受保护的真实网页和 Provider evidence；
- 已更新的 `docs/project-status.md`、文档导航和 V0 阶段结论；
- 对通过、有条件通过或不通过的明确判定，以及进入 V1 的已知限制和未决项。

在本 Spec 与 V0 implementation plan 获得批准前：

- 不创建 `apps/`、`src/`、数据库迁移或 Worker 应用目录；
- 不安装 Next.js、Supabase、Vercel、Python 生产依赖或任何其他生产依赖；
- 不创建云端项目、不部署、不写入真实来源配置；
- 不把 Active Adapter、OpenCLI、Codex CLI、Supabase 或 Vercel 宣称为已最终选定的生产架构。

## 10. Spec 自检

- 范围检查：只覆盖 V0 的端到端验证闭环；V1 正式阅读、X 和多来源能力已排除。
- 事实检查：Spike-01/02 的结论作为设计输入，未被写成无条件生产保证。
- 决策检查：候选技术组合和运行参数明确标为等待本 Spec 批准的 V0 选择，不倒写为既成事实。
- 数据检查：原始、Canonical、结构化、evidence 与 checkpoint 的顺序和可追溯关系明确。
- 失败检查：Worker、采集、Provider、Schema、持久化、权限和恢复分别定义了失败状态与验收。
- 安全检查：浏览器登录态、真实内容和敏感诊断没有进入 Git 或云端调试面。
- 阶段检查：本文不授权实现；V0 需要单独 Plan 批准，V1 仍需新的 Spec/Plan。
