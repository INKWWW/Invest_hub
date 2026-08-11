Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 08 — 版本化 Skill 准入与“大师投研”

# 10 — “持仓组合分析”工作流

**What to build:** 接入固定上游版本的 `portfolio-review`，仅在用户主动提供持仓并明确要求组合层面分析时执行，形成集中度、相关性、风险、机会成本和调整方向的可追溯回答，而不会因用户提到持有一只股票而误触发。

**Blocked by:** 08 — 版本化 Skill 准入与“大师投研”.

**Status:** ready-for-agent

- [ ] `portfolio-review` 以固定来源版本通过 Skill 准入，显示文案为“持仓组合分析”。
- [ ] 只有用户主动提供足以分析的持仓信息并请求组合层面审视时，显式选择或 Auto 才能执行该 Skill。
- [ ] 用户只说“我持有某只股票”、讨论单一个股或没有提供必要组合信息时不自动调用，并在需要时先免额度澄清。
- [ ] 回答覆盖集中度、相关性、风险、机会成本和调整方向，并区分用户输入、外部事实与 Agent 推断。
- [ ] 持仓文本仅用于当前 Thread/Run；在 Ticket 12 的显式 Memory 同意生效前，不得自动写入 Personal Long-term Memory。
- [ ] 组合分析遵守来源日期、Evidence-limited Result、条件判断、不执行交易和一次 Run 一次 quota 的合同。
- [ ] Run、回答和 Trace 显示实际 Skill ID 与固定版本，显式选择不可静默替换。
- [ ] Skill Eval 覆盖完整组合、信息不足、单股提及、组合请求但无持仓、敏感 Memory 非自动写入和 Tool 越界等样本。

## Comments

- None.
