Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 09 — “下单前巴菲特拷问”工作流; 10 — “持仓组合分析”工作流; 15 — 管理员研究数据管理与禁止冒充

# 16 — 三个 seam 的完整本地验收

**What to build:** 将全部已完成能力收敛到三个获批测试 seam，形成可重复的本地 release gate：真实浏览器到 deterministic Provider 的主链路、Supabase 原子/RLS专项链路，以及 Ticket 01 的真实 Codex CLI 合同证据，同时验证免费容量与脱敏边界。

**Blocked by:** 09 — “下单前巴菲特拷问”工作流; 10 — “持仓组合分析”工作流; 15 — 管理员研究数据管理与禁止冒充.

**Status:** ready-for-agent

- [ ] 主 seam 使用真实登录浏览器、实际 Next API、本地 Supabase、真实 Worker 状态机和 deterministic Provider，覆盖完整 Thread → Run → Progress → Answer → Quota → Memory → Trace 回读。
- [ ] 主 seam 使用两个普通 Test Identity 和一个管理员，证明跨用户 Thread、消息、Run、quota、Artifact、Memory 和 Trace 的 listing/guessed-ID 隔离，以及管理员只通过审计路径访问。
- [ ] 主 seam 覆盖 Product Help、Scope Refusal、Unsupported Investment Scope、mixed request、Worker offline、成功、Evidence-limited Result、技术失败、刷新重连、取消、显式重试和重复提交。
- [ ] 三个首批 Skill 的显式选择、Auto 行为、缺失输入免额度、Checklist 推荐抑制和 portfolio-review 非误触发均通过外部行为验收。
- [ ] pgTAP/RPC seam 使用真实并发事务验证 owner RLS、管理员策略、一用户一 active Run、reservation/commit/release、cancel-versus-complete、租约恢复和审计写入。
- [ ] Codex seam 引用 Ticket 01 的真实代表性 generate → production parser 与取消证据；普通回归只使用脱敏 fixtures，不以模型随机输出作为 CI 稳定性门禁。
- [ ] 容量测试测量代表性 Thread、Run、Trace 和 Memory 的持久化体积，证明原始 JSONL 不进入 Supabase、30天 Trace 清理有效，并给出免费层容量估算。
- [ ] 完整控制面、Worker、Supabase、E2E、lint、production build、diff check 和 redaction check 全部通过；失败必须修复或回到 Spec/graph 重新审批，不降低门禁。
- [ ] 输出本地验收报告，明确已证明、未证明、外部 release 风险和 Ticket 17 的精确前置条件；不得把本地结果描述为生产可用或真实外部用户容量。

## Comments

- None.
