Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 01 — Codex CLI 运行合同与安全事件 Spike; 03 — 投资范围与免额度响应; 04 — Research Quota 管理与用户余额

# 05 — “智能”Agent Run 成功闭环

**What to build:** 让用户以“智能”提交一条支持范围内的普通投资问题，经过原子 admission、额度预占、本机 Worker 领取、Provider 执行、结果持久化和额度结算，最终在同一 Research Thread 看到可用回答和基本运行状态。

**Blocked by:** 01 — Codex CLI 运行合同与安全事件 Spike; 03 — 投资范围与免额度响应; 04 — Research Quota 管理与用户余额.

**Status:** ready-for-agent

- [ ] Run admission 原子验证当前用户、Thread ownership、supported route、Worker capability freshness、可用额度、同用户无其他 active Run 和 request idempotency。
- [ ] admission 成功时创建一个有界 Agent Run 和一个 Quota Reservation；同用户并发请求最多产生一个 active Run，重复 request identity 返回同一结果。
- [ ] Agent 专用 Worker capability 通过现有认证边界领取自己的 Run，不会领取或改变 X/Discord 采集任务。
- [ ] deterministic scripted Provider 能完成一条通用投资问答，Worker 将基本运行状态、最终回答、终态和安全元数据持久化到 Supabase。
- [ ] 用户在当前 Thread 看到提交消息、运行中状态、完成回答和结算后的余额；刷新页面读取同一持久化事实。
- [ ] usable success 只 commit 一次额度，与内部模型调用、Tool 调用或 Loop 次数无关；晚到的重复 completion 保持幂等。
- [ ] Worker、Codex CLI 或必要登录不可用时，页面显示“Agent 暂时不可用”，不创建 Run、不预占额度、不建立无限队列；历史 Thread 仍可读取。
- [ ] 主 seam 的最小 happy path 使用真实浏览器、实际 Next API、本地 Supabase、真实 Worker 状态机和 deterministic Provider，而不是仅使用 in-memory control-plane imitation。
- [ ] focused Vitest、Worker tests 和 pgTAP 覆盖授权、payload、claim、持久化、结算和一用户一 active Run；现有模块1回归保持通过。

## Comments

- None.
