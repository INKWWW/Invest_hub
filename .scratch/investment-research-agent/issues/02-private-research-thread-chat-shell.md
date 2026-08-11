Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: None — can start immediately after the complete ticket graph is approved

# 02 — 私有 Research Thread 聊天骨架

**What to build:** 让登录用户在独立 Agent 入口创建、打开、重命名和删除自己的 Research Thread，并在其中发送和阅读纯文本消息。页面采用已确认的 A“纸面工作台”结构，数据由 Supabase 持久化并按用户严格隔离。

**Blocked by:** None — can start immediately after the complete ticket graph is approved.

**Status:** ready-for-agent

- [ ] 登录用户可以创建 Research Thread；新 Thread 具有不可变 owner，自动生成短标题并出现在按时间分组的左侧列表中。
- [ ] 用户可以打开 Thread、发送纯文本消息并在刷新或重新登录后读取完整历史；浏览器本地状态不是消息事实来源。
- [ ] 用户可以重命名自己的 Thread，且不能通过猜测标识读取或修改其他普通用户的 Thread 或消息。
- [ ] 删除操作需要确认，并删除该用户可见的 Thread、消息和当时存在的 Thread Artifact；界面明确提示未来独立 Personal Long-term Memory 需要单独管理。
- [ ] 桌面采用左侧 Thread 列表、右侧对话和底部 composer 的 A 原型层级；移动端列表折叠为抽屉，并复用 Invest Hub 现有视觉语言。
- [ ] 首版页面不出现搜索、文件夹、收藏、分支、Regenerate、通用上传或“技术画线分析”按钮。
- [ ] 至少两个普通 Test Identity 的 RLS/API/UI 验证证明相互不可见；未登录访问进入现有登录保护。
- [ ] 页面、API、RLS 与删除行为均有外部行为测试，并保持现有 X/Discord Reader 回归通过。

## Comments

- None.
