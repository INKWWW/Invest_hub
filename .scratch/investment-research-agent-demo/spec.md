Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-16
Approval evidence: 2026-08-16 用户在当前 Codex task 审阅“产品指令只约束一般问答、三个 Skill 遵循自身冻结指令”及公开原文单例说明后回复“批准”

# 投资研究 Agent 最小可交互 Demo Feature Contract

## 合同定位与权威切换

本合同定义 Invest Hub 当前“尽快形成可展示 Demo”目标下的投资研究 Agent 最小闭环。它是 2026-08-11 已批准的 `.scratch/investment-research-agent/spec.md` 与 17-ticket Delivery Plan 的替代候选，不修改旧产物中的历史批准事实。

本合同仍为 `draft` 时，旧方案的剩余实现保持暂停，本合同也不授权应用代码、数据库迁移、真实 Provider 调用、Worker 变更或部署。用户审阅并批准本合同后：

1. 旧 Feature Contract 与 17-ticket graph 仅作为历史和已完成实现的来源，不再授权后续 Agent 工作；
2. 已经形成的 `/agent` 页面、Research Thread、消息持久化、运行状态和 Codex CLI 适配代码可以按本合同选择性复用，但旧方案中的 Quota、Trace、Memory、复杂恢复等要求不自动进入 Demo；
3. 后续只能通过本合同生成并获批的新 ticket graph 实施，旧 tickets 不与新 tickets 并行充当执行来源。

## Problem Statement

Invest Hub 已有登录体系、投资信息 Reader，以及部分尚未发布的 Agent 页面和执行基础，但用户还没有一条可实际展示的站内路径，可以围绕投资问题与 LLM 多轮对话、显式或自动调用现成投资 Skill，并在刷新后继续查看回答。

旧 Agent 方案覆盖额度、长期记忆、结构化 Trace、复杂恢复、管理员治理和工业级证据合同，建设面明显超过当前 Demo 目标。当前需要先验证更小的问题：已登录用户能否在 Invest Hub 内提出投资问题，由其 Mac 上的 Codex CLI 完成一般投资问答或运行三个指定 Skill，并把最终 Markdown 返回并保存到同一研究会话。

## Product Outcome

Invest Hub 登录用户可以直接进入站内 `/agent` 页面，新建或打开自己的 Research Thread，并在聊天框中发送问题。每条被系统接受的消息形成一个 Agent Run；本机 Runner 使用同一 Thread 已持久化的对话历史调用 Codex CLI，随后把助手回答写入 Supabase 并由页面展示。

LLM 负责判断问题是否属于投资领域、是否需要调用一个可用 Skill，以及如何完成研究。运行时只承担身份、Skill allowlist（允许名单）、一次运行最多一个 Skill、本机写入隔离、全局单并发和状态持久化等必要边界，不建设复杂的前置语义过滤器。

## User Experience Contract

### 页面与登录

- `/agent` 复用 Invest Hub 现有登录态、Session 和用户体系；页面不增加独立登录入口。
- 未登录访问沿用现有站点登录跳转，登录后可返回 `/agent`。
- 页面保留最小两区结构：Research Thread 列表，以及当前 Thread 的消息区和输入框。桌面与手机宽度均可完成新建会话、打开历史、发送消息和阅读结果。
- 对话、最终回答和终态运行状态在刷新及重新登录后仍可读取。

### Skill 调用

页面在输入框附近展示三个 Skill 按钮，并支持同名的稳定 `/` 命令：

| 页面名称 | Skill ID | `/` 命令 | 上游合同 |
| --- | --- | --- | --- |
| 大师投研 | `investment-research` | `/investment-research` | [SKILL.md](https://github.com/xbtlin/ai-berkshire/blob/main/codex-skills/investment-research/SKILL.md) |
| 持仓组合分析 | `portfolio-review` | `/portfolio-review` | [SKILL.md](https://github.com/xbtlin/ai-berkshire/blob/main/codex-skills/portfolio-review/SKILL.md) |
| 下单前巴菲特拷问 | `investment-checklist` | `/investment-checklist` | [SKILL.md](https://github.com/xbtlin/ai-berkshire/blob/main/codex-skills/investment-checklist/SKILL.md) |

- 点击按钮或输入 `/` 命令，只为当前待发送消息显式调用对应 Skill；发送后恢复为未显式调用状态。
- 页面可以用“智能”表示未显式调用的默认状态，但“智能”不是第四个 Skill。点击“智能”只清除当前输入中的显式 Skill 调用。
- 用户未显式调用时，LLM 根据当前问题和同一 Thread 的对话上下文，自由判断调用一个可用 Skill 或直接完成一般投资问答。
- 用户显式调用时，该 Agent Run 使用指定 Skill；LLM 不能静默替换为另一个 Skill。投资领域边界仍然有效，显式 Skill 不能把非投资问题变成可执行任务。
- 一个 Agent Run 最多执行一个 Skill，不组合或串联多个 Skill。
- Skill 不形成会话级选中状态。Skill 返回补充信息问题后，用户的下一条消息属于新的 Agent Run，由用户再次显式调用，或由 LLM 根据对话上下文判断是否再次调用原 Skill。

### 持仓补充交互

`portfolio-review` 没有得到足够持仓信息时，应在聊天中自然追问，不读取或暴露本机共享文件路径。首选产品措辞是：

> 当前研究会话还没有持仓数据，请直接发送持仓清单。

回答可以继续给出比例格式或股数、成本、现金格式的简短例子。Demo 不增加持仓表单、持仓数据库或文件上传。

### 回答展示

- 助手结果以完整 Markdown 写入 `research_messages.content`，页面安全渲染标题、段落、列表、表格、代码和链接。
- 首版在运行完成后一次性展示完整回答，不实现 token streaming（流式输出）。页面通过持久化状态轮询显示“处理中”、成功或失败。
- Skill 生成了本机报告文件时，报告只作为形成最终 Markdown 的临时输入；用户的持久研究记录是 Supabase 中的助手消息。

### 一般问答的信源与投资建议

- Runner 必须向不调用 Skill 的一般问答注入版本化 Invest Hub 产品指令；该指令由产品控制，不与用户消息拼接成同一权限层，也不得被 Thread 中的文本改写。LLM 的投资范围判断和自动路由可以读取必要的产品范围与 Skill 描述，但不把以下回答规则追加到 Skill 执行。
- 关键事实判断必须给出可回读信源。涉及数字、时间敏感事实或外部主体观点时，回答至少标明来源名称、发布主体、发布日期和原文链接；优先使用公司公告、监管或交易所文件、官方统计、审计财报等一手来源，机构研究和新闻用于补充，博主内容只能作为明确归属的个人观点。
- LLM 不得捏造数据、来源、链接或发布日期。无法核验时应明确说明“暂无可核验依据”或不确定性，并区分“来源事实”“来源观点”和“Agent 推断”。
- Agent 可以给出建仓、加仓、减仓、清仓、持有或定投建议，但每条建议必须绑定可核验信源，并写明适用条件、投资期限、主要风险和失效条件；证据不足时不得给出投资建议。
- 只有来源原文明确表达某项操作倾向时，回答才能写“该报告/博主建议加仓或减仓”。否则必须表述为“基于该来源披露的事实或观点，Agent 推断……”，不得把模型推断冒充为来源原话。
- 任何包含上述投资建议的回答都必须显示固定备注：“AI投资建议，仅供参考。”免责声明不能替代信源和条件。
- 一般问答的最小 Provider 输出封装为最终 Markdown、可回读信源清单和“是否包含投资建议”标记。确定性代码只校验引用是否能在清单中解析、建议回答是否存在信源及固定备注，不用规则判断建议本身是否正确；信源是否真实支持结论由 LLM 指令和有界真实验收共同约束。
- 三个 Skill 排除在本节之外。显式或自动路由到 Skill 后，只加载该 Skill 的冻结指令及其明确引用的脚本、工具和资源；产品层不追加本节产品指令，也不以本节的信源封装或免责声明校验拒绝 Skill 输出。Runtime 仍执行固定 Skill allowlist、一次运行最多一个 Skill、本机文件隔离、敏感信息保护、终态持久化和安全 Markdown 渲染。

## Investment Scope Contract

- LLM 可以回答直接服务于证券、基金、组合、公司、行业、宏观、商品、估值、风险、交易决策和投资方法的问题。
- 用户询问 Invest Hub Agent 自身用法、Skill 用法或当前运行状态时，LLM可以提供简短产品帮助。
- 对完全无关的非投资问题，LLM返回简短边界说明，不继续回答实质内容，也不调用 Skill。
- 系统不使用大规模关键词表、资产枚举或独立规则引擎替代 LLM 判断。用户文本在进入 LLM 前只做传输边界校验：去除首尾空白后非空、单条消息不超过 20,000 字符、请求字段与类型合法；这些校验不检查用户谈论的资产、观点或问题类别。
- 消息结构校验只验证 API 信封和 Thread 归属；输出终态与信源引用校验都发生在 LLM 返回之后，不构成用户输入过滤。
- 每条被接受的聊天消息都允许 LLM参与判断；Scope Refusal（范围拒绝）也是一个正常助手回答，并持久化到当前 Research Thread。

## Execution Contract

### 部署拓扑

~~~text
Invest Hub /agent on Vercel
  → Supabase Research Thread、消息与待执行 Run
  → 用户 Mac 上的单实例 Runner
  → Codex CLI + 固定 Skill bundle
  → Supabase 助手 Markdown 与终态
  → /agent 轮询展示
~~~

- Vercel 只处理登录用户请求、持久化和状态读取，不承载长时间 Codex 进程。
- Supabase 是 Research Thread、用户/助手消息、最小 Agent Run 状态、调用方式和最终回答的持久事实来源。
- 用户 Mac 必须在线且 Runner 可用，新的 Agent Run 才能开始；网站和历史会话不依赖 Mac 在线。
- 不接入云端 LLM fallback，也不引入新的付费模型 API。

### 对话上下文

- Runner 按顺序读取当前 Research Thread 已持久化的用户和助手消息，并与当前问题一起交给 LLM。
- Demo 不建设 Thread Memory、Personal Long-term Memory、向量检索或对话摘要。若完整 Thread 超出配置的硬上限，系统明确提示用户新建会话，不静默丢弃早期消息。
- 另一个用户的消息、Reader 内容、X/Discord 原始数据和其他 Thread 不进入当前 Prompt。

### Skill 执行与本机写入

- Runner 只暴露固定版本的 `investment-research`、`portfolio-review`、`investment-checklist`，Skill bundle 对运行过程只读。
- 固定版本必须保留上游 Skill 的完整指令和其明确引用的脚本/资源，不能只保留名称或摘要使 Skill 名存实亡；精确 commit SHA 在 Delivery Plan 中冻结。
- 每个 Agent Run 创建独立、owner-only 的临时工作目录。Skill 引用的脚本、财务数据工具和报告生成可以执行，但所有可写输出必须限制在该目录。
- Codex CLI 可以使用其公开网页搜索和三个 Skill 明确需要的公开数据工具；不得把 Invest Hub 私有 Reader、X/Discord 原始内容或本机其他个人数据当作隐式来源。
- 运行过程不得写入共享 `$HOME`、仓库工作树、共享 `reports/portfolio-latest.md`、OpenOrder 或其他 Run 的目录。
- Runner 在终态后删除该 Run 的临时目录；删除失败只保留本机安全故障摘要，不把原始报告、Prompt、完整 Codex 输出或本机路径写入 Supabase。
- 不使用 Supabase Storage，也不为临时报告增加 Artifact 文件模型。

## Admission and Failure Contract

- 全部用户共享一个全局 Agent 执行槽；任意时刻最多有一个 `queued` 或 `running` 的 Demo Agent Run。
- 当执行槽忙碌时，新提交立即返回“Agent 正忙，请稍后重试”，不创建队列、不在后台等待，也不消耗模型调用。
- 当 Mac Runner、Codex CLI 或必要登录不可用时，页面显示“Agent 暂时不可用”；历史会话保持可读，新运行不进入无限队列。
- 正常 Provider 或 Skill 失败时，当前 Run 进入失败终态并显示简短可重试提示；用户重新发送才形成新 Run。
- Demo 不提供 Stop、自动重试、租约恢复或崩溃后的自动续跑。Runner 或主机硬崩溃留下的异常运行允许在 Demo 阶段人工处理，不宣称无人值守能力。
- 页面重复点击和网络重放使用一个请求标识避免同一次提交形成两个 Run；该幂等边界不扩展为工业级任务恢复系统。

## Data and Privacy Contract

- 普通用户只能读取和修改自己的 Research Thread 与消息；继续复用 Supabase Auth 和 owner-bound RLS。
- 浏览器不接触 Supabase service-role credential、本机 Codex 凭据或 Skill 执行目录。
- Prompt、完整 Codex JSONL、隐藏推理、Cookie、密钥、本机路径和 Skill 临时文件不进入用户消息或云端日志。
- Demo 不展示或执行 Research Quota，不创建长期 Memory，不建设管理后台、Trace 浏览器或数据导出。
- 旧方案已经存在的 Quota、Trace、Memory 或 Artifact 代码/表可以保持不动，但新 Demo 主路径不得依赖它们才能完成一次聊天。

## User Stories

1. As an Invest Hub logged-in user, I want to open `/agent` without another login, so that Agent feels like part of the same product.
2. As a user, I want to ask an investment question and receive a persisted LLM answer, so that I can demonstrate the complete interaction loop.
3. As a user, I want to continue in the same Research Thread, so that the LLM can understand prior questions and answers.
4. As a user, I want a non-investment request refused by the LLM, so that the page remains an investment Agent without a large prefilter system.
5. As a user, I want to explicitly invoke one Skill with a button or `/` command for the current message, so that I control the workflow when needed.
6. As a user, I want the LLM to choose a Skill or general investment Q&A when I do not specify one, so that normal chat remains simple.
7. As a user, I want Skill invocation to reset after sending, so that it never becomes an invisible thread mode.
8. As a user, I want `portfolio-review` to ask for holdings in chat, so that I do not need a portfolio database or local report file.
9. As a user, I want a completed Skill report displayed as Markdown and preserved after refresh, so that the Demo produces a useful research artifact.
10. As a user, I want an immediate busy or unavailable message, so that I do not mistake a non-executing request for queued work.
11. As a second ordinary user, I want another user's research hidden, so that the Demo preserves the product's existing privacy boundary.
12. As the operator, I want all Skill writes isolated to one temporary Run directory, so that a Demo execution cannot overwrite shared Mac data.

## Acceptance Criteria

The Feature is locally ready for release review only when all of the following are demonstrated:

1. An existing Invest Hub user reaches `/agent` through the current Session and can create, reopen and continue a Research Thread.
2. One general investment question completes through browser → Supabase → Mac Runner → Codex adapter → Supabase → browser, and its Markdown remains after refresh.
3. One clearly non-investment question receives a concise refusal generated through the LLM path and invokes no Skill.
4. Each of the three buttons and each corresponding `/` command records an explicit current-Run invocation and executes the mapped Skill without switching identities.
5. With no explicit invocation, at least one case demonstrates LLM-selected Skill use and one case demonstrates general investment Q&A without a Skill.
6. After an explicit invocation is submitted, the next composer state has no persistent Skill selection.
7. `portfolio-review` without holdings produces the agreed natural-language clarification; a following holdings message can complete analysis through explicit invocation or LLM selection.
8. A Skill-generated full Markdown answer is stored in `research_messages.content`; no user-visible response contains a local path.
9. File-boundary tests prove that Skill scripts can create required temporary files inside the Run workspace and cannot write to the repository, shared report paths or another Run workspace.
10. Two Test Identities cannot list, open or mutate each other's Threads or messages through UI, API or guessed identifiers.
11. While one Run is active, another submission receives “Agent 正忙，请稍后重试” and creates no queued Run. When the Runner is unavailable, history remains readable and new execution is rejected clearly.
12. Page tests cover desktop and 375px interaction without blocking the composer, Thread navigation or Markdown reading.
13. The Demo path shows no quota, long-term memory, Trace-management or file-upload interaction.
14. A factual general-chat answer identifies its sources; a non-Skill answer containing investment advice binds each recommendation to resolvable sources and conditions and displays “AI投资建议，仅供参考。” Skill answers remain governed by their frozen Skill instructions.
15. A non-empty message within 20,000 characters reaches the LLM regardless of asset names or semantic category; no keyword or asset classifier refuses it before the model.

## Testing Decisions

1. The first end-to-end proof is one representative general investment case through the actual browser/API/database/Runner boundaries using a deterministic Provider. Its persisted input, output and terminal state must agree before additional cases are added.
2. Deterministic regression uses scripted Provider and artificial public inputs. Real Codex output, private Prompt text and live financial data are not committed as fixtures.
3. Scope examples cover supported investment questions, non-investment refusals and Agent product help. Eval metadata and expected labels remain outside the generation Prompt; captured Prompt checks prove they do not leak into model input.
4. Skill contract tests cover exact button/command mapping, explicit priority, Auto selection, one-Skill maximum, missing-input clarification and non-persistence across messages.
5. Filesystem tests use sentinel paths inside and outside the Run workspace and verify the complete output tree, not only the expected report filename.
6. Database/API tests cover owner-bound RLS, duplicate request identity, global single-active-Run admission, busy rejection and offline rejection using real concurrent submissions where the contract concerns a race.
7. Markdown rendering tests include links, tables, code blocks and raw HTML attempts; unsafe HTML and dangerous URLs are not executed.
8. 一般问答信源合同先用一个公开、可人工回读的单例验证“关键判断 → 引用 → 来源清单”闭环，再覆盖建议充分、建议证据不足、来源仅表达事实但未直接给出操作倾向三类 case；测试期望和人工结论不得进入生成 Prompt。该验收不用于约束或评分三个 Skill。
9. 确定性测试验证不存在前置关键词/资产拒绝、所有引用均能解析、建议回答包含信源及固定备注。它不以“格式通过”证明来源真实或结论正确。
10. After deterministic gates pass, release review runs one bounded real case for each Skill and one general investment chat using the actual Codex CLI. Real Provider calls, Vercel deployment, Worker installation/restart and authenticated production acceptance require explicit Release Authorization in the future ticket graph.
11. No bulk gold corpus, LLM Judge, quota suite, Memory suite, Trace-retention suite or high-concurrency soak is required for this Demo.

## Out of Scope

- Research Quota、token 计费、额度购买或管理员额度管理；
- Thread Memory、Personal Long-term Memory、向量数据库和跨 Thread 个性化；
- 持仓数据库、持仓导入、文件上传、图片/PDF/表格解析和 Supabase Storage；
- X/Discord Reader 数据作为 Agent 研究来源；
- 多 Skill 编排、子 Agent 团队、后台长队列、多 Worker、云端 Provider fallback 和高可用 SLA；
- token streaming、回答分支、重新生成、编辑后重跑、自动重试和用户取消；
- 原始 Chain-of-thought、完整 Provider Trace、Trace 管理页面和复杂审计；
- 自动交易、券商连接、订单模拟和替用户作出最终投资决定；
- 为 `stock-data-fetch`、`claim-verification`、`strategic-materials` 或其他 Skill 增加用户侧按钮；
- 对旧 17-ticket 方案未完成部分的继续实现。

## Delivery Assumptions and Cost Boundary

- 复用 `.worktrees/agent-integration` 中已有 `/agent`、Research Thread、消息/RLS、状态轮询和 Codex CLI 适配是成本估算成立的前提。
- 预期实施规模为一名熟悉仓库的开发者约 5～8 人日；相较原 4～7 人日估算，版本化产品指令、最小信源封装、建议后置校验和真实来源代表性验收预计增加约 0.5～1.5 人日。主要成本仍是 Skill 临时写入隔离、完整对话上下文、调用合同和端到端验证，而不是聊天页面本身。
- 若现有 Agent Run admission 与 Quota 强耦合，Delivery Plan 可以选择最小 additive migration 或独立 Demo admission seam；选择标准是让 Demo 主路径不依赖 Quota，同时保留现有历史数据，不以复用旧抽象为目标扩大改造。
- 本合同不承诺 Vercel、Supabase 或 Codex 永久免费，只要求首个 Demo 不新增付费服务。Codex CLI 仍受当前账号额度、网络和 Mac 在线状态限制。

## Approval Gate

本 Feature Contract 的最终修订版已于 2026-08-16 获得用户明确批准。批准范围包括：一般问答受版本化信源与投资建议产品指令约束，三个 Skill 排除在该产品指令之外并遵循各自冻结指令，以及使用公开原文单例验证一般问答信源链路。

本批准只冻结 Feature Contract，不授权应用代码。下一门禁是用户审阅并整体批准已同步修订的 6-ticket graph；Git push、远程 migration、生产写入、Vercel deployment、本机 Runner 安装或重启、真实 Codex 调用和生产验收继续要求 Delivery Plan 中的明确 release ticket 与独立授权。

## Comments

- 2026-08-16：用户在完成 grill-with-docs 决策讨论后回复“批准”，其语境为批准进入 `to-spec`。该回复授权生成本草案，不构成对尚未生成的完整 Feature Contract 的批准。
- 2026-08-16：用户收到并审阅完整 Feature Contract 链接后再次回复“批准”。本 Feature Contract 获批，下一门禁为 `to-tickets` 生成完整 ticket graph 并单独审批 Delivery Plan。
- 2026-08-16：用户要求确认输入校验边界，并新增“关键判断必须有高可信信源、不得捏造、投资建议必须绑定准确来源并显示固定免责声明”的产品约束。该变更影响 Prompt、输出合同和验收标准，因此 Feature Contract 恢复为 `draft`，等待重新批准。
- 2026-08-16：用户进一步明确版本化产品指令只约束一般问答；三个 Skill 排除在外并遵循各自冻结指令。合同、Ticket 02/04/06 与验收矩阵同步收窄，继续保持 `draft`。
- 2026-08-16：用户在审阅上述最终修订与公开原文单例示例后回复“批准”。Feature Contract 恢复为 `approved`，下一门禁为完整 6-ticket graph 的整体审批。
