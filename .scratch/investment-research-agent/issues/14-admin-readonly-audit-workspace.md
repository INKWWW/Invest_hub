Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 12 — Personal Long-term Memory 与“我的记忆”; 13 — 安全 Research Progress 与 Agent Trace

# 14 — 管理员只读研究审计工作台

**What to build:** 在现有管理员区域增加独立 Agent 管理工作台，让管理员以真实身份查看 Test Identity 的 Research Thread、Agent Run、Memory 和安全 Trace，同时保持普通用户隔离，并为管理员读取行为留下审计记录。

**Blocked by:** 12 — Personal Long-term Memory 与“我的记忆”; 13 — 安全 Research Progress 与 Agent Trace.

**Status:** ready-for-agent

- [ ] 只有管理员可以进入 Agent 管理工作台；普通用户通过页面、API 或猜测标识访问都被拒绝。
- [ ] 管理员可以按用户定位并查看 Research Thread、消息、Agent Run、quota状态、Personal Long-term Memory 和 sanitized Agent Trace。
- [ ] 每次管理员打开用户列表、详情或敏感研究记录都以真实管理员身份写入审计事件，包含目标、动作和时间。
- [ ] 管理员视图不暴露原始 Chain-of-thought、私有 Prompt、密钥、Cookie、本地 JSONL 或已被 Trace 合同排除的数据。
- [ ] 管理员只读视图不能调用用户聊天 API、改变 Thread 上下文或发起 Agent Run，也不提供“以该用户继续”入口。
- [ ] Agent 管理能力位于独立管理员工作区，不占用普通用户聊天左栏。
- [ ] 至少一个管理员和两个普通 Test Identity 的页面/API/RLS测试证明管理员可见、普通用户隔离和每次读取可审计。

## Comments

- None.
