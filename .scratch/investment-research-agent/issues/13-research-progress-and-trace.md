Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 06 — Run 取消、重连与失败恢复; 07 — 公开证据研究与 Evidence-limited Result

# 13 — 安全 Research Progress 与 Agent Trace

**What to build:** 将真实 Runtime、Tool 和 Provider-neutral 事件转化为用户可见的 Research Progress，并为每个 Agent Run 保存可排查、可评估的结构化 Agent Trace；两者都必须经过 allowlist 和脱敏，不展示原始 Chain-of-thought。

**Blocked by:** 06 — Run 取消、重连与失败恢复; 07 — 公开证据研究与 Evidence-limited Result.

**Status:** ready-for-agent

- [ ] Agent Trace 按顺序记录安全事件类型、Selected Skill/版本、Tool和模型元数据、耗时、用量、错误、停止原因、安全输入输出摘要和 Artifact 引用。
- [ ] Provider-specific JSONL 只通过 Ticket 01 的版本化 adapter 转换为 Provider-neutral 事件；未知或不安全字段不能透传到数据库或前端。
- [ ] Research Progress 只使用真实 Runtime 状态、Tool调用、来源进度、安全阶段 Commentary 和经过允许的 Reasoning Summary，不生成虚构步骤。
- [ ] 运行中进度默认展开，完成后可以折叠和重新查看；失败或取消保留已完成步骤与安全失败原因。
- [ ] Chain-of-thought、私有 Prompt、密钥、Cookie、浏览器凭据、service-role、本地路径、完整 JSONL 和重复私有来源正文被确定性拒绝或脱敏。
- [ ] 本地原始 Provider 事件仅作为 owner-only、可删除的短期诊断 evidence，不成为 Supabase Trace、Thread Memory 或 Personal Long-term Memory。
- [ ] 云端 sanitized Trace 不复制聊天正文，最长保留30天并有可验证的自动清理；回答、消息和 Memory 不随 Trace 清理被删除。
- [ ] 对抗测试注入凭据、路径、原始正文和指令式字段，证明 persistence 与 UI 均 fail-closed；刷新后进度仍从持久化安全事件恢复。

## Comments

- None.
