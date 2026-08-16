Workflow profile: matt
Status: in-progress
Approval: approved
Approved at: 2026-08-16
Approval evidence: 2026-08-16 用户在当前 Codex task 明确要求“安排并推进本次 6 tickets 的开发”；该指令批准完整 6-ticket Delivery Plan 并授权本地实现。
Blocked by: 01 — 一般投资聊天纵向闭环

# Ticket 03：Skill 显式调用与 LLM 路由

## Outcome

用户可以通过三个按钮或稳定 `/` 命令，为当前消息显式指定 Skill；未显式指定时，由 LLM在三个 Skill 与一般投资问答之间选择。调用决定持久化到当前 Run，发送后不保留会话级 Skill 状态。

## Implementation boundary

- 页面映射固定为：大师投研 → `investment-research`，持仓组合分析 → `portfolio-review`，下单前巴菲特拷问 → `investment-checklist`。
- `/investment-research`、`/portfolio-review`、`/investment-checklist` 只在消息开头解析；未知命令保留为普通文本并给出可理解提示，不进入 Skill 执行。
- 点击按钮形成当前 composer 可见的显式调用；发送成功或点击“智能”后清除。打开历史 Thread 不恢复上一次调用状态。
- Run 持久化 `invocation_mode=explicit|auto` 与 nullable `skill_id`。显式调用在投资范围成立时必须保持所选 ID；Auto 决定只能是 general、refuse 或三个固定 Skill 之一。
- Auto/Scope router 由 LLM完成并返回最小闭集决定；Runtime 校验闭集和一次 Run 最多一个 Skill。router 的测试元数据不进入 Prompt。
- 本 ticket 使用 scripted Skill adapter 证明调用合同，不执行上游脚本。

## Acceptance criteria

- [ ] 三个按钮和三个 `/` 命令分别得到准确、相同的 Skill ID。
- [ ] 显式调用只作用于当前消息；发送完成、切换 Thread 和刷新后 composer 均回到“智能”。
- [ ] 显式调用不会被 LLM静默换成另一个 Skill；非投资输入仍可被 LLM拒绝且不执行 Skill。
- [ ] Auto 至少有一个 scripted case 选择 Skill，另一个 case 选择 general，并且任何结果最多一个 Skill。
- [ ] Run 回读可以看到调用方式和 Skill ID，但普通消息不暴露内部 Prompt 或本机路径。
- [ ] `portfolio-review` 缺少持仓时返回约定追问；下一条消息重新经过 explicit 或 Auto，而不是沿用隐藏状态。

## Verification

1. 覆盖按钮、命令、未知命令、显式优先、Auto general、Auto Skill、Scope Refusal 和补充持仓八个产品行为。
2. Prompt capture 证明 expected route、case name 和 Skill 测试答案不进入 router 输入。
3. API/DB 测试证明 invocation metadata 与 user message 原子一致，重复读取不会改变选择。
4. 运行受影响组件、API、Worker、pgTAP 与 lint/typecheck/build 套件。

## Not in this ticket

上游 Skill 安装、脚本执行、临时工作目录、真实 Codex 路由和生产发布。

## Comments

- 2026-08-16：由已批准 Feature Contract 生成；完整 ticket graph 尚未获批。
- 2026-08-16：已实现三 Skill 映射、命令解析、显式优先与单 Skill 闭集，并将 invocation metadata 接入 Demo Run；UI/API 全套测试待本地 Control Plane 依赖恢复。
