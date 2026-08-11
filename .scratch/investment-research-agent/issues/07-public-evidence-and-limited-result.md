Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 05 — “智能”Agent Run 成功闭环

# 07 — 公开证据研究与 Evidence-limited Result

**What to build:** 让“智能”Run 能够使用获准的公开资料、公司或监管披露及获准数据能力形成可追溯研究，展示来源和日期并区分事实、观点、推断与缺失；证据不足时形成 Evidence-limited Result，而不是伪造确定性结论。

**Blocked by:** 05 — “智能”Agent Run 成功闭环.

**Status:** ready-for-agent

- [ ] 只允许使用用户提供文字、公司或监管披露、公开网络资料，以及在 Ticket 01 中已证明并经过批准的免费行情或财务数据能力。
- [ ] Tool/来源准入由 Runtime allowlist 确定性执行；任意 shell、未批准数据源、X 原始内容和 Discord 派生总结不能被模型自行启用。
- [ ] 时效性事实展示来源、发布日期或观察日期；回答区分 confirmed fact、attributed claim、Agent inference、disagreement、uncertainty 和 missing evidence。
- [ ] 来源不可用、证据不足或互相矛盾但已形成有用研究时，返回 Evidence-limited Result，明确已确认事实、分歧和缺失信息并 commit 一次 quota。
- [ ] 因技术故障没有形成 usable answer 时进入 technical failure 并 release reservation，不得把失败包装成 Evidence-limited Result。
- [ ] mixed request 只把投资部分送入研究 Tool 和回答，明确拒绝其他部分；只要正式研究完成就正常结算一次额度。
- [ ] 条件性判断包含适用条件、时间范围和失效风险，不执行交易、不生成无条件买卖指令。
- [ ] deterministic fixtures 覆盖来源成功、无结果、冲突、过期、解析失败、混合请求和恶意来源文本；严重证据越界 fail-closed。
- [ ] 一条代表性 generate → production parser → persistence → UI case 先通过，再扩展批量 Answer/Source Eval。

## Comments

- None.
