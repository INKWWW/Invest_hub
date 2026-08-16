Workflow profile: matt
Status: in-progress
Approval: approved
Approved at: 2026-08-16
Approval evidence: 2026-08-16 用户在当前 Codex task 明确要求“安排并推进本次 6 tickets 的开发”；该指令批准完整 6-ticket Delivery Plan 并授权本地实现。
Blocked by: 01 — 一般投资聊天纵向闭环

# Ticket 05：全局单并发、可用性与用户隔离

## Outcome

把快乐路径收紧为可展示的公共站点行为：全系统只有一个 Agent 执行槽；忙碌或 Mac 离线时立即拒绝新运行；网络重放不产生重复 Run；两个普通用户不能互读研究数据。

## Implementation boundary

- 在 Supabase authority 中原子保证全局最多一个 queued/running `agent_demo_runs`，而不是只依赖按钮禁用或单进程惯例。
- admission 在创建 user message/Run 前检查当前执行槽与现有 Worker freshness。忙碌或不可用时不创建排队 Run，也不写入一个看似已发送的用户问题。
- 忙碌返回“Agent 正忙，请稍后重试”；Worker/Codex 不可用返回“Agent 暂时不可用”。输入框保留原问题供用户重试。
- `(owner_id, request_id)` 保证同一次网络重放只得到同一个结果；不同 request ID 不自动重试失败运行。
- RLS/API 同时覆盖 Thread、message 和 `agent_demo_runs`；service-role 只存在于受控 Worker 服务端边界。
- Demo 保持手工处理主机硬崩溃遗留状态，不增加租约续跑、Stop、自动恢复或无限队列。

## Acceptance criteria

- [ ] 两个真实并发 admission 中只有一个创建 Run，另一个得到 busy；数据库从未出现两个 active Demo Runs。
- [ ] Worker 不可用时历史 Thread 可读，新运行被立即拒绝且没有 user message/Run 残留。
- [ ] 相同 request ID 重放不创建第二个 user message、Run 或 assistant message。
- [ ] 失败 Run 只有用户重新发送新 request ID 才能再次执行。
- [ ] 用户 A 无法通过列表、API 或猜测 ID 读取/修改用户 B 的 Thread、message 或 Run。
- [ ] 页面在桌面和 375px 下清楚显示 busy/unavailable，且保留草稿供重试。

## Verification

1. pgTAP/RPC 使用真实并发事务验证全局唯一 active Run 与 request identity。
2. Control Plane 集成测试覆盖 busy、offline、duplicate、failure retry 和跨用户 guessed-ID。
3. Worker freshness 使用现有安全 heartbeat/capability seam，不伪造生产在线声明。
4. 运行受影响数据库、Control Plane、Worker、lint/typecheck/build 和脱敏检查。

## Not in this ticket

高可用、自动修复、租约恢复、取消、排队、公平调度、额度控制和多 Worker 扩容。

## Comments

- 2026-08-16：由已批准 Feature Contract 生成；完整 ticket graph 尚未获批。
- 2026-08-16：本地 054/055 pgTAP 已覆盖全局忙碌、Worker freshness、离线拒绝、请求幂等、失败后新 request、owner RLS；并修复了 busy 检查顺序根因。
