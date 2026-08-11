Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 08 — 版本化 Skill 准入与“大师投研”

# 09 — “下单前巴菲特拷问”工作流

**What to build:** 接入固定上游版本的 `investment-checklist`，既支持用户显式选择，也支持 Auto 在识别到具体投资决策或下单意图时先询问是否使用；用户确认后执行一次可追溯 Checklist Run，拒绝后不重复打扰。

**Blocked by:** 08 — 版本化 Skill 准入与“大师投研”.

**Status:** ready-for-agent

- [ ] `investment-checklist` 以固定来源版本通过 Skill 准入，显示文案为“下单前巴菲特拷问”，不要求用户预先提交结构化投资逻辑。
- [ ] 用户显式选择后，工作流复核核心假设、反面证据、估值与安全边际、风险和决策纪律；不将其用于初次筛选或完整公司研究。
- [ ] Auto 识别到具体投资决策或下单意图时先返回免额度确认问题，不创建研究 Run、不预占 quota。
- [ ] 用户自然语言确认后，下一次提交被结构化为显式 Selected Skill，并在 composer 和 Run 记录中可见，不要求再次点击按钮。
- [ ] 用户拒绝后，同一标的、同一次下单意图内不重复推荐；新的标的、新的下单决策或显著变化条件才恢复推荐资格。
- [ ] 缺少标的、决策或必要条件时先澄清；只有输入合同满足并正式开始 Run 后才 reserve quota。
- [ ] 输出遵守公开证据、Evidence-limited Result、条件判断和不执行交易边界。
- [ ] Skill Eval 包含显式选择、Auto 推荐、确认、拒绝抑制、新决策恢复、初筛误触发和完整研究误触发等正负样本。

## Comments

- None.
