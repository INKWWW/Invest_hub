Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 02 — 私有 Research Thread 聊天骨架

# 03 — 投资范围与免额度响应

**What to build:** 在聊天入口先建立投资研究范围边界，让 Product Help、简短问候、Scope Refusal 和 Unsupported Investment Scope 形成正确、可阅读且无研究副作用的响应；支持研究在正式 Run 闭环尚未可用时保持 fail-closed。

**Blocked by:** 02 — 私有 Research Thread 聊天骨架.

**Status:** ready-for-agent

- [ ] 路由结果使用封闭枚举区分 supported investment research、Product Help、Scope Refusal、Unsupported Investment Scope、missing-input clarification 和 mixed request，非法或不确定结构 fail-closed。
- [ ] Invest Hub 功能、额度、会话和操作问题以及简短问候返回 Product Help，不调用研究 Tool、不创建 Agent Run、不形成 Personal Long-term Memory。
- [ ] 完全无关的非投资请求返回简短 Scope Refusal，不以通用聊天回答绕过边界。
- [ ] 加密货币、外汇、衍生品、债券和非上市资产被识别为 Unsupported Investment Scope，而不是 Scope Refusal 或技术故障。
- [ ] A股、港股、美股、ETF、基金、上市 REITs 及其直接相关的公司、行业、宏观、商品、估值、技术分析、投资方法、组合和风险问题进入 supported candidate；在 Ticket 05 完成前不会被伪装成已执行研究。
- [ ] mixed request 被结构化识别，为 Ticket 07 保留投资部分与拒绝部分的安全边界；当前票不提前调用研究 Tool。
- [ ] 无关内容不写入研究 Trace 摘要或 Personal Long-term Memory；只保留执行范围判定所需的最小结果。
- [ ] Scope Eval 覆盖正例、负例、边界资产、问候、Product Help、混合请求和提示注入式绕过，严重 domain escape fail-closed。

## Comments

- None.
