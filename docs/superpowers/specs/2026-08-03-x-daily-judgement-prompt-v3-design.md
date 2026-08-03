# X 当日判断 Prompt v3 设计

## 目标

将跨博主当日判断从 v2 的两类中性归纳升级为可追溯的三类投资信息：个股与产业判断、市场结构判断、投资策略与心态建议。博主已经明确表达的建仓、买入、卖出等倾向可被忠实归因和结构化展示；系统和模型不得自行生成交易建议。

## 范围与边界

本次只实现新的公共 Prompt 合同及其端到端执行边界：Worker、Worker HTTP 接口、数据库完成校验和 Reader-safe 投影。旧版本判断记录保持可读，不重写历史输出；不创建评测集、不运行影子评测、不改变采集、来源、覆盖、调度或筛选规则。

新的输出 schema 为 `v3-x-cross-blogger`，Prompt 版本为 `v3-x-cross-blogger-1`。它包含 `security_industry_viewpoints`、`market_structure_viewpoints`、`strategy_mindset_viewpoints` 和顶层 `uncertainties`。每条观点都保留现有的来源、分析和帖子证据关系，并新增 `action_intent`、`action_scope` 与 `conditions`。`action_intent` 只允许固定枚举；当博主没有明确行动表述时，必须为 `none`。

## 读取与安全

Reader 将三类判断分别展示，并在有明确行动倾向时显示“博主倾向”。`action_scope`、条件和不确定性仅展示通过结构校验的文本。旧 v2 输出因没有新字段，继续安全展示为原有两类内容；不得因此把旧内容误写为 `none` 或补造第三类内容。

模型仅处理 `included` 来源。输出必须排除非投资内容、输入中携带的指令文本、外部知识、未经博主明确表达的操作倾向，以及模型自身的交易建议。所有新字段也不得泄露 opaque ID。任何 schema、证据归属、枚举、自然语言 ID、系统建议或强共识违规，均必须在持久化前被拒绝。

## 验收标准

1. Worker 只接受并提交 `v3-x-cross-blogger` / `v3-x-cross-blogger-1`，且新 Prompt 在运行时被加载。
2. 每类观点均要求完整且同源的分析、证据和来源关系；策略与心态条目也遵守同一证据合同。
3. 未明确的操作倾向不能通过；明确、归因的博主倾向可通过，且系统命令式投资建议仍被拒绝。
4. 数据库、Worker HTTP 接口和 Reader 对 v3 合同一致；旧 v2 已存版本仍可安全阅读。
5. Python、控制面、数据库回归、lint、build、脱敏检查及生产页面验收通过后，才允许发布。
