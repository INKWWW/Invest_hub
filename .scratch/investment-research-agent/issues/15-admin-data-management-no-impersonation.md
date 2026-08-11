Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 14 — 管理员只读研究审计工作台

# 15 — 管理员研究数据管理与禁止冒充

**What to build:** 让管理员在明确管理操作下修改或删除用户研究数据，并保证所有变化可审计、不会伪装成用户行为；管理员仍不能代替用户发送消息、继续 Research Thread 或发起 Agent Run。

**Blocked by:** 14 — 管理员只读研究审计工作台.

**Status:** ready-for-agent

- [ ] 管理员可以通过独立管理动作修改或删除允许管理的 Research Thread、Memory、Trace 与相关用户研究数据，并在危险操作前看到目标和影响范围。
- [ ] 管理员修改保留真实管理员身份、原值或可审计变更摘要、目标、原因和时间；不得把管理员内容写成用户原始消息或原始研究结论。
- [ ] 删除操作遵守 Thread、Personal Long-term Memory 与30天 Trace 的独立生命周期，不能通过删除一个对象意外跨用户或跨边界级联。
- [ ] 管理员不能以用户身份创建消息、确认 Skill、继续 Thread、创建 Run、消费用户 quota 或调用 Provider。
- [ ] 普通用户无法调用管理员 mutation；service-role 仅存在于受保护服务端边界。
- [ ] 管理动作具有幂等和并发保护，重复请求不会重复删除、重复调整或破坏审计链。
- [ ] 页面/API/RLS测试覆盖允许的修改删除、取消确认、跨用户目标错误、审计回读和所有冒充入口的拒绝。

## Comments

- None.
