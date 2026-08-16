Workflow profile: matt
Status: in-progress
Approval: approved
Approved at: 2026-08-16
Approval evidence: 2026-08-16 用户在当前 Codex task 明确要求“安排并推进本次 6 tickets 的开发”；该指令批准完整 6-ticket Delivery Plan 并授权本地实现。
Blocked by: 01 — 一般投资聊天纵向闭环

# Ticket 02：多轮上下文、投资边界与 Markdown

## Outcome

把 Ticket 01 的单轮回答扩展为真实多轮投资聊天：Provider 收到同一 Thread 的完整已持久化对话和版本化产品指令，LLM负责投资范围判断与一般问答的证据化回答；一般投资回答、产品帮助和非投资拒绝都以安全 Markdown 保存并展示。本 Ticket 的产品级回答规则不约束后续 Skill 输出。

## Implementation boundary

- 建立只用于非 Skill 一般问答的版本化 Demo 产品指令和 Provider 合同；产品指令由 Runner 控制并与不可信的 Thread 文本分层，同一 Thread 的消息按顺序输入。
- Thread 在配置硬上限内发送全部消息；超过上限时明确要求新建 Thread，不建设摘要、Thread Memory 或长期 Memory。
- 投资范围由 LLM判断。用户输入只做 trim 后非空、单条不超过 20,000 字符、字段类型与 Thread 归属校验；任何通过这些传输校验的文本都进入 LLM，不增加关键词分类器、资产 allowlist 或投资建议前置过滤。
- 非投资请求返回简短 Scope Refusal，Agent 产品用法返回简短帮助；两者都是持久化 assistant message。
- 产品指令要求关键事实判断给出来源名称、发布主体、日期和原文链接，优先一手权威来源，明确区分来源事实、来源观点与 Agent 推断，无法核验时说明不确定且不得捏造。
- 一般问答 Provider 只增加最小封装：最终 Markdown、信源清单和“是否包含投资建议”标记，不继承旧结构化事实/推断/Trace Schema。
- 建仓、加仓、减仓、清仓、持有或定投建议必须引用清单内信源，并在正文写明适用条件、期限、风险和失效条件；若来源没有直接表达操作倾向，不得把 Agent 推断写成来源原话。证据不足时不提供建议。
- 确定性输出校验发生在 LLM 返回后：引用必须可解析；建议回答必须有信源和固定备注“AI投资建议，仅供参考。”。校验不判断建议是否正确，也不阻碍用户输入。
- 页面安全渲染 Markdown，允许常用标题、段落、列表、表格、代码与安全链接，阻断 raw HTML 执行和危险 URL。

## Acceptance criteria

- [ ] 第二条消息的 Provider 输入包含同一 Thread 第一轮的用户问题和助手回答，且不含其他 Thread 或其他用户内容。
- [ ] 一般投资问题返回完整 Markdown；刷新后渲染结构保持可读。
- [ ] 任一 trim 后非空且不超过 20,000 字符的消息都会进入 LLM，包括旧规则可能判为不支持资产或非投资的文本；只有超限或信封非法时在模型前拒绝。
- [ ] 明确非投资问题由 LLM路径返回简短拒绝，且没有 Skill 调用。
- [ ] Agent 产品帮助可以回答，但不扩展为通用闲聊。
- [ ] 一般问答中含关键数据或时点判断的回答有可回读信源；不存在捏造来源、把 Agent 推断伪装为来源原话或无法解析的引用。
- [ ] 一般问答中有证据的投资建议包含来源、条件、期限、风险、失效条件和固定备注；证据不足 case 明确不提供投资建议。
- [ ] 超长 Thread 获得明确新建会话提示，不静默截断早期消息。
- [ ] Markdown 中的脚本、事件属性、`javascript:` URL 和不安全 HTML 不会执行。

## Verification

1. 使用 scripted Provider 完成投资、多轮补充、非投资拒绝、产品帮助、有证据建议和证据不足不建议等外部行为 case。
2. 动态捕获 Prompt，证明产品指令存在且版本可识别，并证明测试 case ID、期望标签、gold 文本和其他用户内容没有进入模型输入。
3. 使用生产候选 parser 处理成功、空回答、无法解析引用、建议缺少信源/固定备注、异常 Markdown 和 Provider failure fixture。
4. 使用一份冻结公开原文和人工构造的候选回答验证 parser、引用解析和人工回读标准。例如，冻结某上市公司的公开年报，提问“年报披露的营收变化是否支持加仓”：人工核对回答中的数字、日期和链接是否与年报一致；若年报未直接表达加仓倾向，回答只能将加仓判断标为 Agent 的有条件推断。把数字改错或写成“年报建议加仓”的候选必须失败。真实 Codex 的一般问答单例留给 Ticket 06 的独立 Release Authorization；结果只证明该 case，不宣称从结构校验获得普遍事实真实性保证。
5. 运行页面 375px/桌面组件测试，以及受影响 Control Plane、Worker、lint/typecheck/build 套件。

## Not in this ticket

Skill 按钮、`/` 命令、自动 Skill 路由、Skill 脚本及其内在回答规则、真实 Codex 调用和流式输出。

## Comments

- 2026-08-16：由已批准 Feature Contract 生成；完整 ticket graph 尚未获批。
- 2026-08-16：已实现一般问答产品指令/信源校验合同与安全 Markdown parser；真实 Provider 与全套 Control Plane 验收仍待本地依赖恢复。
