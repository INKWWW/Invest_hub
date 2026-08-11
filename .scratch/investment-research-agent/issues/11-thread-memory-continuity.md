Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 06 — Run 取消、重连与失败恢复; 07 — 公开证据研究与 Evidence-limited Result

# 11 — Thread Memory 与跨 Run 连续性

**What to build:** 让同一 Research Thread 在多个 Agent Run 之间通过可压缩、可追溯的 Thread Memory 保持连续性，同时保留完整聊天记录，并确保任何新 Run 都能从 Supabase 重建上下文而不依赖 Codex session。

**Blocked by:** 06 — Run 取消、重连与失败恢复; 07 — 公开证据研究与 Evidence-limited Result.

**Status:** ready-for-agent

- [ ] Thread Memory 由最近相关对话、滚动摘要、当前研究状态和必要证据引用组成，并始终绑定单一 Thread 和 owner。
- [ ] 完整用户与助手消息继续可阅读；上下文压缩不会删除、覆盖或伪造原始会话历史。
- [ ] 滚动摘要的每项关键状态或结论可追溯到原消息、Agent Run 或 Artifact 引用，不能成为无来源的事实权威。
- [ ] 新 Run 从 Supabase 中的消息、Thread Memory 和引用重建上下文；删除 Codex session 或更换 Worker 不破坏多轮连续性。
- [ ] 取消、失败和 Evidence-limited Result 对 Thread Memory 的写入规则明确，失败草稿不会被当作已确认结论。
- [ ] 同一 Thread 中用户可以切换到新的投资主题；首版不自动强制新建 Thread，但摘要不得把无关主题错误合并为一个结论。
- [ ] 两个普通用户无法读取或召回彼此的 Thread Memory；管理员能力留给后续管理票。
- [ ] 长对话测试验证确定性压缩、上下文上限、来源追溯、刷新重建和不依赖 `codex exec resume`。

## Comments

- None.
