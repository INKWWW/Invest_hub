Workflow profile: matt
Status: in-progress
Approval: approved
Approved at: 2026-08-16
Approval evidence: 2026-08-16 用户在当前 Codex task 明确要求“安排并推进本次 6 tickets 的开发”；该指令批准完整 6-ticket Delivery Plan 并授权本地实现。
Blocked by: 02 — 多轮上下文、投资边界与 Markdown; 04 — 三个 Skill 的隔离本机执行; 05 — 全局单并发、可用性与用户隔离
Release authorization required: yes — real Codex, remote migration, Vercel deployment, local Runner change and production acceptance require a separate explicit approval

# Ticket 06：本地整体验收与受控 Demo 发布

## Outcome

在同一集成候选上完成 Feature Contract 的本地验收，生成脱敏 release package；只有在用户另行批准 Release Authorization 后，才执行真实 Codex、远程 migration、Vercel deployment、本机 Runner 变更和已登录生产验收。

## Local acceptance

- 合并 Ticket 01～05 的已验证提交到唯一 Demo integration branch，不从脏主工作树捎带无关变更。
- 先跑一条浏览器 → API → Supabase → Worker → scripted Provider/Skill → assistant Markdown 的完整代表性 case，再运行剩余矩阵。
- 矩阵覆盖：一般投资多轮、无前置语义拦截、非投资拒绝、产品帮助、一般问答的带信源关键判断、有证据投资建议、证据不足不建议、来源原话与 Agent 推断区分、固定免责声明，以及三个 Skill 各自的内在输出、三个按钮、三个 `/` 命令、Auto general、Auto Skill、Skill 不持续选中、portfolio 补充持仓、刷新恢复、busy、offline、duplicate、跨用户 RLS、Markdown 安全和文件写入隔离。
- 运行 Supabase、Control Plane、Worker、E2E、lint、typecheck、production build、diff check 与 redact check。任何既有失败必须有基线证据并与本 Feature 改动分离。
- 产出脱敏验收报告，只包含 commit、测试命令/结果、安全状态、已知限制和待执行发布步骤；不包含真实 Prompt、完整模型响应、凭据、私有研究内容或本机路径。

## Release gate

用户批准 Release Authorization 后，严格按以下顺序一次执行并逐步回读：

1. 对目标 Supabase 做 migration history 只读核对和 dry-run；只应用本 graph 的 additive migration。
2. 部署同一已验收 commit 到 Vercel，确认 Ready 后再切换正式别名。
3. 安装或重启指向同一 commit/配置指纹的 Mac Runner，并回读 freshness/capability。
4. 使用已登录 Test Identity 完成一次带可回读信源的一般投资聊天、一次一般问答的有证据投资建议、一次一般问答的证据不足不建议、三个 Skill 各一个仅按自身指令执行的有界真实 Codex case、一次 portfolio 补充信息、多轮恢复、busy 与 offline 页面验收。
5. 验证 Supabase 只保留允许的消息/终态，临时目录已清理，日志与页面没有敏感信息。

任一步失败即停止后续步骤；数据库 migration 采用 additive forward fix，Vercel 回切前一 Ready deployment，Runner 恢复前一已知配置。不得重写 migration history、篡改旧 Run 或伪造成功记录。

## Acceptance criteria

- [ ] Feature Contract 15 项 Acceptance Criteria 在同一 commit 上有可回读证据。
- [ ] 本地完整矩阵、生产构建、diff/redact gate 全部通过，或明确停在真实、未掩盖的 blocker。
- [ ] release package 可以让独立 reviewer 判断每条范围是否通过，不依赖口头说明。
- [ ] 未获独立 Release Authorization 时，没有真实 Codex、远程写入、部署、Runner 重启或生产验收。
- [ ] 获批执行后，Vercel、Supabase、Runner 和页面都指向同一版本，三个 Skill 映射及冻结 SHA 可回读。
- [ ] 一般问答版本化产品指令的标识可回读；一般问答真实单例的信源原文支持关键判断，投资建议满足证据绑定合同和固定备注；三个 Skill 的 Prompt 不含该产品指令。
- [ ] 任何失败都执行既定停止/回滚边界，不把局部成功宣称为 Demo 发布完成。

## Not in this ticket

正式 SLA、外部用户规模验证、付费容量、长期监控、自动恢复、额度、Memory、Trace 和新增 Skill。

## Comments

- 2026-08-16：由已批准 Feature Contract 生成；完整 ticket graph 与 Release Authorization 均尚未获批。
- 2026-08-16：已生成脱敏本地验收包；本地数据库/纯合同/Skill 隔离证据已具备，但全套 Control Plane、Worker 依赖、lint/typecheck/build 与真实浏览器链路仍未满足，因此未宣称 Demo 发布完成。
