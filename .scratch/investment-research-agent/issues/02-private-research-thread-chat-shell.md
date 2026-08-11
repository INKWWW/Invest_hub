Workflow profile: matt
Status: done
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: None — can start immediately after the complete ticket graph is approved

# 02 — 私有 Research Thread 聊天骨架

**What to build:** 让登录用户在独立 Agent 入口创建、打开、重命名和删除自己的 Research Thread，并在其中发送和阅读纯文本消息。页面采用已确认的 A“纸面工作台”结构，数据由 Supabase 持久化并按用户严格隔离。

**Blocked by:** None — can start immediately after the complete ticket graph is approved.

**Status:** done

- [x] 登录用户可以创建 Research Thread；新 Thread 具有不可变 owner，自动生成短标题并出现在按时间分组的左侧列表中。
- [x] 用户可以打开 Thread、发送纯文本消息并在刷新或重新登录后读取完整历史；浏览器本地状态不是消息事实来源。
- [x] 用户可以重命名自己的 Thread，且不能通过猜测标识读取或修改其他普通用户的 Thread 或消息。
- [x] 删除操作需要确认，并删除该用户可见的 Thread、消息和当时存在的 Thread Artifact；界面明确提示未来独立 Personal Long-term Memory 需要单独管理。
- [x] 桌面采用左侧 Thread 列表、右侧对话和底部 composer 的 A 原型层级；移动端列表折叠为抽屉，并复用 Invest Hub 现有视觉语言。
- [x] 首版页面不出现搜索、文件夹、收藏、分支、Regenerate、通用上传或“技术画线分析”按钮。
- [x] 至少两个普通 Test Identity 的 RLS/API/UI 验证证明相互不可见；未登录访问进入现有登录保护。
- [x] 页面、API、RLS 与删除行为均有外部行为测试，并保持现有 X/Discord Reader 回归通过。

## Comments

- 2026-08-11：已在独立 worktree `/Users/hanyuec/Desktop/Invest_hub/.worktrees/agent-ticket-02-chat-shell` 领取 Ticket 02，基于 planning baseline `9acdffc` 实施；主 checkout 保持不动。
- 2026-08-11：本地实现与验证完成；控制面全量 48 files/257 tests、Supabase 全量 43 files/689 tests、lint、production build、redaction check 通过；已完成双 Test Identity 本地 HTTP/RLS 隔离、刷新持久化、删除级联和未登录保护验收。当前仅待提交本地分支，未执行 push、PR、远程 migration、部署或真实 Provider 调用。
- 2026-08-11：集成审计发现 API 时间字段与客户端模型命名不一致、消息写入未推进 Thread 活动时间；已在集成分支补充受控字段映射、消息活动时间触发器及回归断言。未执行远程 migration、部署或其他外部状态操作。
- 2026-08-11：集成组合验证完成；控制面 48 files/258 tests、Supabase 43 files/690 tests、lint、production build、diff check 和 redaction check 通过。两套本地 Test Identity 的真实登录、Thread 创建/消息持久化/刷新、跨用户列表隔离、猜测 ID 404 和 SSR 页面不泄露均通过；全量 `tsc --noEmit` 仍受既有非 Agent 测试类型错误阻断。
