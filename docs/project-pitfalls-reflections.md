# 项目踩坑反思

## 使用规则

本文件是 Invest Hub 的开发流程反思与防复发规则。任何涉及需求澄清、Spec、Plan、实现、测试、独立复核、发布或生产验收的任务，开始前必须先阅读本文件；如果任务涉及评估集、Prompt、LLM、结构化输出、数据边界或 release gate（发布门禁），必须逐条执行本文的对应检查。

本文件记录的是可复用的失败模式和流程改进，不替代正式 Spec、Plan、ADR 或当前代码合同。若本文与已批准的 Spec/Plan 冲突，必须先暂停实现，明确记录冲突并修订正式文档后再继续。

## 2026-08-08：X 当日判断 v5 Prompt Eval 评估集阻塞

Task 7 的目标是建立 24 个公开 synthetic gold cases（人工标准评估样例）、deterministic gates（确定性门禁）和 bounded Judge（有界语义评审器）。结构测试、数量测试和多轮局部修复均曾通过，但独立复核最终仍发现评估框架不能作为 release gate。该结果说明：测试全绿不等于评估集可信，更不等于可以发布。

### 暴露的问题

1. **冻结输入与标准答案不一致。** 部分 case 的 production-shaped context（生产格式上下文）中只有 security industry（安全行业）观点，却要求生成 market structure（市场结构）或 strategy/mindset（策略与心态）主题；`empty-all` 同时包含非空观点和非投资内容，却要求最终完全为空。这样的 gold contract（标准答案契约）不能从输入事实推出，会错误拒绝忠实输出或鼓励模型编造内容。

2. **生成链路与评估 authority（权威校验依据）没有闭环。** 为了避免答案泄漏而匿名化 production IDs（生产标识符）后，生成结果仍按原始 authority 校验，导致 generate → parse（生成到解析）路径不一致。部分语义 case ID、coverage 文本和 fixture 说明也仍可能泄漏题目意图，破坏 blind generation（盲测生成）。

3. **答案元数据与模型输入边界不够严格。** `focus`、gold 语义、允许证据、预期类别、fixture 说明等信息只要进入模型 Prompt，就会让模型知道题目想测试什么。仅检查显式字段名不够，还必须检查 case ID、任务 ID、自然语言说明和所有可序列化嵌套字段。

4. **安全 gate 没有覆盖完整输出树。** `no-external-number`（禁止外部数字）和 `no-system-trade-advice`（禁止系统交易建议）只检查了部分路径，其他字段可以绕过 deterministic gate。严重安全规则不能依赖每个 case 是否手工配置某条路径，而应从候选输出完整 Schema 推导并全量扫描。

5. **验证顺序错误。** 先批量创建 24 个 case、runner 和测试，再验证真实生产 parser、语义一致性、盲测 Prompt 和 generate → parse 闭环，导致结构性假阳性长期存在。独立 reviewer 虽然最终发现了问题，但发现顺序不应依赖多轮补丁。

### 根因判断

这不是 Subagent-Driven Development（子代理驱动开发）本身的问题。该工作流帮助暴露了问题；真正的流程缺口是：

- 没有在实现前冻结 Eval Case（评估样例）的输入、标准答案和边界契约；
- 没有先完成一条代表性 case 的全链路证明；
- 测试偏重 schema、数量和类型，没有首先验证“gold 是否能由输入事实推出”；
- 生成输入、评估元数据、证据 authority 和候选输出之间的所有权边界没有单独建模；
- 多轮发现同一根因后仍继续局部修复，没有及时回到 Spec/Plan 重新设计评估契约。

## 后续强制流程

### 1. 先读反思，再确认范围

任务开始必须先阅读本文件，再确认事实来源、当前阶段门禁、已批准 Spec/Plan、未决问题和验收标准。任何新增评估集、Prompt 或 release gate 都必须在任务 brief 中引用本文的相关检查项。

### 2. 先做一条完整代表性 case

批量创建评估集前，必须先证明一条 case 完整通过：

```text
production context
  → generation Prompt
  → candidate output
  → production parser
  → deterministic gates
  → bounded Judge
  → sanitized report
```

完成标准必须同时满足：模型输入不含答案元数据；输入事实能推出标准答案；生成结果可被生产 parser 接受；严重违规必定 fail-closed（失败关闭）；报告不含原文、私有内容或可注入自然语言。

### 3. 分离模型输入与评估器元数据

每个 Eval Case 必须明确划分：

| 区域 | 可提供给模型 | 仅评估器可见 |
| --- | --- | --- |
| 生产上下文 | 生产协议允许的作者、观点、资产、时间、条件和证据 | 不适用 |
| 运行标识 | 不含语义的 opaque IDs（不透明标识符） | 原始 case ID 与映射表 |
| 标准答案 | 不提供 | gold contract、允许证据、预期类别 |
| 安全规则 | 不提供规则答案 | deterministic rules、严重级别 |
| Judge 输入 | 只提供必要的候选、输入摘要和受控证据 | 完整评分依据 |

必须用动态 Prompt capture（提示词捕获）验证：case 名、gold、focus、允许证据、预期主题、fixture 说明、私有 marker 均不进入生成 Prompt。

### 4. 建立 Corpus Validator

每次修改公开评估集必须自动检查：

- case ID 精确、唯一、无语义泄漏、无路径穿越；
- 每个冻结 context 通过真实 production parser；
- gold 中的每个结论都能追溯到输入中的具体语义字段；
- 作者、观点、类别、资产、时间、条件和 empty 状态互相一致；
- `empty` case 的所有上下游字段确实支持空结果；
- allowed evidence（允许证据）和输入证据一一对应；
- forbidden rules（禁止规则）覆盖候选输出的全部相关字段；
- 公开 fixture 不含真实博主、私有 Prompt、原始响应和私有链接。

### 5. 安全规则必须全量扫描

外部数字、系统交易建议、确定性升级、错误归因、外部事件、Prompt injection（提示词注入）等严重规则必须在完整候选 JSON 树上执行。新增字段、嵌套数组或旁路文本出现时，默认仍然受保护；不能通过“该 case 没有配置这条规则”而放行。

### 6. 独立复核必须从第一轮覆盖全链路

Reviewer 的第一轮检查必须同时包含：

1. 真实 production parser；
2. 24-case 语义一致性；
3. 动态 blind Prompt；
4. generate → parse 闭环；
5. deterministic fail-closed；
6. Judge schema、证据白名单和严重级别；
7. report 脱敏与 Git 外部目录边界；
8. 恶意旁路字段和路径穿越回归。

如果两轮复核都发现同一类根因，必须停止局部补丁，回到 Spec/Plan 修订数据契约和所有权边界。

### 7. Release gate 的推进条件

评估任务未通过时，不得进入本地 release gate、发布、生产正常运行或页面验收。只有以下证据全部具备，才能推进下一任务：

- 全部公开 case 通过 Corpus Validator；
- 代表性 case 和批量 case 都完成 production parser 与语义一致性验证；
- 生成 Prompt 动态捕获确认无答案泄漏；
- generate → parse → gate → Judge → report 闭环成功；
- 所有严重违规 fail-closed；
- live eval（真实评估）只写入 Git 外临时目录；
- 独立 reviewer 明确 PASS；
- 未决风险已写入 Engineering Journal 和 Final Report。

## 可复用检查清单

开始任务前：

- [ ] 已阅读本文件、当前核心文档、相关 Spec 和 Plan。
- [ ] 已确认任务没有越过当前阶段门禁。
- [ ] 已明确事实输入、标准答案、评估元数据和输出 authority 的所有权。

实现前：

- [ ] 一条代表性 case 已通过完整链路。
- [ ] 公开 fixture 的事实能够推出 gold，不存在上下游矛盾。
- [ ] 生成输入与 Judge/评估器输入已物理或逻辑分离。

完成前：

- [ ] 已运行真实 parser、Prompt capture、generate → parse 和恶意旁路测试。
- [ ] 已验证全量字段树的 deterministic fail-closed。
- [ ] 已验证报告脱敏、Git 外路径、无真实数据和无外部 Provider 默认调用。
- [ ] 已由独立 reviewer 按全链路清单给出 PASS。
