Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 11 — Thread Memory 与跨 Run 连续性

# 12 — Personal Long-term Memory 与“我的记忆”

**What to build:** 让用户跨 Research Thread 保留可管理的 Interest、Research Conclusion 和 Preference Memory，并通过“我的记忆”页面查看、修改和删除；Memory 具有来源、敏感信息同意和结论 supersession 规则，不是完整聊天副本。

**Blocked by:** 11 — Thread Memory 与跨 Run 连续性.

**Status:** ready-for-agent

- [ ] Personal Long-term Memory 仅包含 Interest Memory、Research Conclusion Memory 和 Preference Memory，并按 owner 在 Supabase 中持久化与隔离。
- [ ] 已成功完成的 Run 可以产生 Memory Candidate；候选只有通过类型、来源、时间、条件、敏感性和状态校验后才成为可召回 Memory。
- [ ] 低敏感关注信息和有 Run/Artifact 来源、时间与条件的关键结论可以自动写入；真实持仓、资产规模和个人财务状况必须由用户明确要求保存。
- [ ] Research Conclusion Memory 保留原版本；后续结论通过 supersedes 或 invalidates 关系取代或判定失效，不静默覆盖历史。
- [ ] 账户菜单提供极简“我的记忆”页面，用户可以查看、修改和删除自己的 Memory；删除或 inactive 条目立即停止未来召回。
- [ ] 新 Thread 只召回与当前问题相关且仍有效的 Memory，并将历史结论作为带日期和条件的历史信息，而非当前事实。
- [ ] 删除 Research Thread 不静默删除已独立形成的 Personal Long-term Memory；Thread 删除提示用户到“我的记忆”单独处理。
- [ ] 首版使用普通 PostgreSQL 查询与规则，不引入 Vector Database、embedding service、完整聊天复制或本地用户文件夹。
- [ ] 多 Test Identity 测试覆盖跨 Thread 召回、敏感信息同意、supersession、编辑、删除、Thread 删除独立性和跨用户隔离。

## Comments

- None.
