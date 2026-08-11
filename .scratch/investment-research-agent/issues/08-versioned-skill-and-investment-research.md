Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 07 — 公开证据研究与 Evidence-limited Result

# 08 — 版本化 Skill 准入与“大师投研”

**What to build:** 建立网站 Agent 的版本化 Skill 准入闭环，并首先接入固定上游版本的 `investment-research`。用户可以保留“智能”或显式选择“大师投研”，选择在 composer 中可见、只作用于一次 Run 且不得被静默替换。

**Blocked by:** 07 — 公开证据研究与 Evidence-limited Result.

**Status:** ready-for-agent

- [ ] Skill registry 明确稳定 ID、显示文案、Description、固定来源版本、启用状态、输入合同、市场范围、Tool allowlist、调用上限和停止条件。
- [ ] 第三方 Skill 在启用前完成来源版本、许可证、安全、所需配置、Eval 和管理员试用检查；安装或文件存在不等于对网站用户启用。
- [ ] 保留固定上游 `investment-research` 正文，Invest Hub 只维护轻量 Description、UI 文案和 Runtime 配置，不额外重写为重型包装工作流。
- [ ] composer 显示“智能”和“大师投研”；一次 Run 最多 Selected Skill 一个，选择以结构化字段提交、在输入区可见、Run 中锁定并在发送后清除。
- [ ] “智能”可以选择一个已启用 Skill或进行通用投资问答；显式“大师投研”不得静默切换到其他 Skill。
- [ ] 输入不满足显式 Skill 合同时，系统先说明缺失信息并追问，不创建 Run、不预占 quota。
- [ ] “大师投研”回答覆盖上市公司的商业模式、护城河、管理层、行业、风险和估值，并遵守 Ticket 07 的来源与证据边界。
- [ ] Run、回答和 Trace 记录实际 Skill ID 与固定版本，显示文案未来变化不能改变执行合同。
- [ ] Skill Eval 覆盖 Auto 选择、显式优先、错误输入、禁用版本、Tool 越界、停止条件、必要覆盖项和不适用问题。

## Comments

- None.
