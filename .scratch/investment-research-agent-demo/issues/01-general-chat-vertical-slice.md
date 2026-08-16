Workflow profile: matt
Status: in-progress
Approval: approved
Approved at: 2026-08-16
Approval evidence: 2026-08-16 用户在当前 Codex task 明确要求“安排并推进本次 6 tickets 的开发”；该指令批准完整 6-ticket Delivery Plan 并授权本地实现。
Blocked by: None — can start after the complete ticket graph is approved

# Ticket 01：一般投资聊天纵向闭环

## Outcome

交付第一条浏览器可见的 tracer bullet：已登录用户在 `/agent` 新建 Research Thread，发送一条投资问题，本机 Worker 使用确定性 Provider 完成处理，助手 Markdown 写入 Supabase，刷新后仍可读取。该闭环不依赖 Research Quota、Trace 或 Memory。

## Implementation boundary

- 以 `.worktrees/agent-integration` 当前集成基线 `5e7e9345551b136bbeb31e8bf0702fdb4d735e92` 为复用来源，在新的隔离 worktree/branch 中实施；不得直接修改脏主工作树。
- 复用现有 `/agent`、登录态、`research_threads`、`research_messages`、RLS、页面轮询和 Worker/Codex adapter 中符合新 Spec 的部分。
- 新增最小 additive `agent_demo_runs` seam，保存 owner、thread、request identity、user/assistant message、question、invocation mode、Skill ID、queued/running/succeeded/failed 状态与时间。不要放宽旧 `agent_runs` 或 Quota Reservation 的约束。
- 提供最小原子提交、Worker claim、成功完成和失败完成边界；Ticket 01 只证明单请求正常路径，竞争、离线与幂等强化留给 Ticket 05。
- 页面不显示额度、Memory、Trace、Stop 或 Regenerate。

## Acceptance criteria

- [ ] 现有 Invest Hub 用户登录后直接进入 `/agent`，无第二套登录。
- [ ] 新建 Thread、发送问题、创建 user message 与 `agent_demo_runs` 记录是同一受控提交路径。
- [ ] 单实例 Worker 可以 claim Run、调用 scripted Provider、写入 assistant Markdown 并设置成功终态。
- [ ] 页面轮询到助手消息，刷新及重新打开 Thread 后内容不丢失。
- [ ] `agent_demo_runs` 与消息均受 owner-bound RLS；浏览器不接触 service-role credential。
- [ ] 正常闭环没有读取或结算 Research Quota，也没有写 Trace、Memory 或 Artifact。

## Verification

1. 先完成一条真实本地 HTTP + Supabase + Worker + scripted Provider 代表性 case，再增加聚焦单元测试。
2. 运行新增 pgTAP、Control Plane API/组件测试和 Worker 聚焦测试。
3. 捕获数据库前后状态，证明只有一个 user message、一个 Run、一个 assistant message，且 assistant message 可通过产品 API 回读。
4. 运行受影响套件的 lint/typecheck/build；既有无关失败必须单独列明，不能记为通过。

## Not in this ticket

真实 Codex、范围拒绝、完整 Thread 上下文、Markdown 安全渲染、Skill 路由、Skill 脚本、忙碌/离线强化、远程 migration 和部署。

## Comments

- 2026-08-16：由已批准 Feature Contract 生成；完整 ticket graph 尚未获批。
- 2026-08-16：已实现 additive Demo Run、owner-bound admission/claim/complete、Worker freshness、页面轮询与 scripted Provider seam；真实 HTTP→Worker→页面链路和全套 Control Plane 验收待本地依赖恢复。
