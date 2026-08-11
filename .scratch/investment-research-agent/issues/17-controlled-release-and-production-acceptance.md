Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: 16 — 三个 seam 的完整本地验收
Release authorization: Required before execution

# 17 — 受控发布、回滚与生产页面验收

**What to build:** 在 Ticket 16 全部通过且用户另行给出 Release Authorization 后，按受控顺序完成精确远程 migration、Vercel 发布、本机 Worker 更新、真实 Test Identity 页面验收和回滚验证；任何一步失败都停止扩大外部状态变更。

**Blocked by:** 16 — 三个 seam 的完整本地验收.

**Status:** ready-for-agent

- [ ] 执行前再次确认用户对本票的独立 Release Authorization；完整 ticket graph 批准或本地测试通过均不能替代该授权。
- [ ] 发布候选固定到精确 commit，确认工作树范围、远端分支、migration history、环境绑定、Worker配置和 Vercel/Supabase 目标无歧义。
- [ ] 在任何 push、remote migration、部署或真实 Provider 页面验收前，运行完整 Ticket 16 gate、diff check 和 redaction check，并保存不含秘密的结果摘要。
- [ ] 对 Supabase 免费层缺少自动备份的风险给出可执行回滚与必要的安全导出方案；migration 先 dry-run，再按批准顺序执行并只读核对远端 history。
- [ ] Vercel production deployment 绑定预期 commit和 Supabase 项目，匿名访问仍受登录保护，现有 X/Discord Reader 保持不变。
- [ ] 本机 Agent Worker 从同一发布候选运行，更新/重启有回滚路径；不会重新启用已停止的个人 Discord 采集，也不会改变 X Worker 职责。
- [ ] 使用管理员控制的多个邮箱 Test Identity 完成额度分配、用户隔离、Thread、多轮 Run、Skill、Progress、Memory、Stop 和管理员审计的真实登录页面验收。
- [ ] 真实 Codex 调用保持有界且使用批准的测试问题；失败不会伪造成功、重复扣费或泄漏 Prompt、Chain-of-thought、凭据和本地路径。
- [ ] 桌面和375px页面无阻断性布局、错误覆盖层或横向溢出，A 原型层级和 Skill 文案保持一致，“技术画线分析”继续隐藏。
- [ ] 发布失败按预定义边界回滚并保留审计证据；成功后更新工程记录和项目状态，只陈述实际验收范围，不宣称多用户 SLA 或无限免费容量。

## Comments

- 尚未获得 Release Authorization；即使完整 Delivery Plan 后续获批，也不得自动执行本票的外部状态变更。
