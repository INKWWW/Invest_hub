Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 05 — “智能”Agent Run 成功闭环

# 06 — Run 取消、重连与失败恢复

**What to build:** 让 Agent Run 成为浏览器断线后仍可恢复、用户可真实停止、异常退出后不会吞掉额度的服务器侧任务，并保证取消、完成、租约接管和显式重试之间没有重复执行或双重结算。

**Blocked by:** 05 — “智能”Agent Run 成功闭环.

**Status:** ready-for-agent

- [ ] 关闭、刷新或重新打开浏览器不会取消服务器侧 Run；用户重连后从 Supabase 读取当前状态、已完成步骤和最终结果。
- [ ] Stop 写入持久化取消请求，Worker 在有界时间内停止后续 Tool/Provider 工作、终止对应进程组并形成 cancelled 终态。
- [ ] cancelled Run 释放 Quota Reservation，且取消与 completion 竞争时只有一个合法终态；取消后晚到 success 不得结算额度。
- [ ] Provider timeout、parser/schema failure、Worker异常退出和无 usable answer 的技术失败形成安全失败原因并释放 reservation。
- [ ] Worker lease 过期和 abandoned reservation 具有确定性恢复路径；接管不会静默生成第二个并行模型尝试或覆盖不可变历史 attempt。
- [ ] 重复 stop、failure、release、completion 和客户端网络重试均保持幂等。
- [ ] 失败后不自动创建收费 Run；用户显式重新提交时形成新的 request identity、Run 和 reservation，并保留前次失败记录。
- [ ] 并发 pgTAP/RPC 测试覆盖 cancel-versus-complete、lease expiry、reservation recovery 和 duplicate request；Worker 测试证明进程组清理无无界等待。
- [ ] 浏览器级测试覆盖运行中刷新、重开 Thread、Stop、取消结算和显式重试的可见行为。

## Comments

- None.
