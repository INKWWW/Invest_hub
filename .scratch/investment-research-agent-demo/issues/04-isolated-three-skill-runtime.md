Workflow profile: matt
Status: in-progress
Approval: approved
Approved at: 2026-08-16
Approval evidence: 2026-08-16 用户在当前 Codex task 明确要求“安排并推进本次 6 tickets 的开发”；该指令批准完整 6-ticket Delivery Plan 并授权本地实现。
Blocked by: 02 — 多轮上下文、投资边界与 Markdown; 03 — Skill 显式调用与 LLM 路由

# Ticket 04：三个 Skill 的隔离本机执行

## Outcome

本机 Runner 能够完整执行三个固定上游 Skill 及其引用脚本，把最终报告转换为 assistant Markdown，同时证明所有写入都限制在当前 Run 的临时工作目录。

## Frozen upstream version

- Repository: `https://github.com/xbtlin/ai-berkshire`
- Commit: `d64751635308d1920bcdae234e6dd957fd79e736`
- Packages: `codex-skills/investment-research`、`codex-skills/portfolio-review`、`codex-skills/investment-checklist`

任何 commit、目录或 Skill 数量变化都会改变 Delivery Plan；实施必须停止并先让完整 ticket graph 恢复 `draft`、重新批准。

## Implementation boundary

- 将冻结快照作为 Runner 只读 Skill bundle；保留每个 `SKILL.md` 的完整指令及其明确引用的脚本、工具和资源，不改写成名称占位符。
- 每个 Run 创建 owner-only 临时目录并以其作为 Codex 工作目录。只允许该目录写入；仓库、共享 `$HOME`、OpenOrder、共享 `reports/portfolio-latest.md` 和其他 Run 目录保持不可写。
- Codex 可以读取冻结 Skill bundle，使用公开网页搜索和 Skill 明确需要的公开数据工具；不把 Invest Hub 私有 Reader 或本机个人文件作为来源。
- 三个 Skill 只遵循各自冻结的上游指令及其内在回答逻辑，不注入 Ticket 02 的一般问答产品指令，也不套用一般问答的信源封装和免责声明校验。
- 产品 Runtime 只承担 Skill ID 准入、一次运行最多一个 Skill、本机文件隔离、敏感信息保护、终态持久化和安全 Markdown 渲染，不改写 Skill 最终结论。
- 运行完成后从最终 Agent message 或 Skill 报告提取 Markdown，写入 `research_messages.content`，再删除临时目录。
- `portfolio-review` 无持仓时不尝试共享本机报告，直接返回“当前研究会话还没有持仓数据，请直接发送持仓清单。”及简短输入例子。
- 失败只保存安全分类和用户可读提示；完整 JSONL、Prompt、原始报告、本机路径和 stderr 不进入 Supabase。

## Acceptance criteria

- [ ] 三个 Skill 均从同一冻结 commit 加载，页面 Skill ID 与实际包一一对应。
- [ ] `investment-research` 和 `investment-checklist` 可以运行其所需脚本并形成完整 Markdown。
- [ ] `portfolio-review` 的缺失持仓追问和提供持仓后的分析两条路径均成立。
- [ ] Prompt capture 证明 Skill 执行包含对应冻结 Skill 指令，且不包含 Ticket 02 的一般问答产品指令。
- [ ] sentinel 测试证明当前 Run 可以在临时目录创建报告，但无法写仓库、共享报告路径或另一个 Run 目录。
- [ ] 成功回答只在 Supabase 保留 assistant Markdown；Run 终态后临时目录被删除。
- [ ] Provider/脚本失败不会泄漏完整命令、Prompt、凭据、stderr 或本机绝对路径。

## Verification

1. 先用人工公开输入和 scripted Codex event fixture 证明一个 Skill 的 generate → parser → message 闭环，再覆盖另外两个 Skill。
2. 执行完整输出树和路径穿越测试，包括 symlink、`../`、绝对路径及共享报告文件 sentinel。
3. 普通回归不调用真实 Codex 或外网；真实 Skill case 留给 Ticket 06 的 Release Authorization。
4. 运行 Worker 完整相关测试、Control Plane 回读测试、redact check、lint/typecheck/build。

## Not in this ticket

新增用户侧 Skill、Skill 串联、Supabase Storage、持仓数据库、长期报告文件和生产 Runner 变更。

## Comments

- 2026-08-16：上游 `main` 通过只读 `git ls-remote` 解析为冻结 SHA；完整 ticket graph 尚未获批。
- 2026-08-16：已导入冻结快照、provenance/hash 校验、三 Skill/两工具 allowlist、Run 目录 symlink/path 隔离与 helper 执行 seam；真实 Codex/外网 Skill case 保持未执行。
