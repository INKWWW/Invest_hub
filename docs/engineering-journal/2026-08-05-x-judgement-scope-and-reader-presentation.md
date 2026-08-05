# X 判断对象范围与 Reader 展示 v4

日期：2026-08-05

本次发布针对 X 判断输出中“有操作倾向但对象未明确”的合同缺口，以及当日判断与单博主观点视觉层级不一致的问题。批准的 Spec/Plan 保持 v3 历史记录和 v3 verification replay 不变；正常单帖、窗口、跨博主链路统一切换到 v4，并以 `action_scope_status` 区分 `specified`、`unspecified` 和 `not_applicable`。

实现提交为 `1341af5`。Worker 新增三份公开版本化 Prompt 与严格 parser；控制面 normal daily completion、公共 contract bundle 和 Supabase RPC/validator 接受 v4；Reader 对 v2/v3/v4 做安全兼容投影，只在有明确对象时显示范围，缺失对象只显示不可执行提示。页面采用平铺编辑式布局，两个主模块使用浅色标题带，观点编号、直接陈述和元信息在跨博主与单博主视图中保持同一语法，博主标题行加粗。

本地验证：Supabase 全量 pgTAP 41 files / 644 tests；Worker 全量 188 tests；控制面全量 42 files / 239 tests；lint、Turbopack production build、`git diff --check` 和 `scripts/v0/redact-check.sh` 均通过。隔离 worktree 的临时依赖软链接已移除，构建使用本地 lockfile 安装的依赖完成。

生产数据库：已确认 Supabase 项目 `invest-hub-v1`，应用唯一待执行 migration `20260805141108_x_judgement_scope_v4.sql`，随后远端 migration history 已确认该版本已登记。`db push` 同时报告 pg-delta catalog 缓存证书缺失 warning，但 migration 已完成且 history 重试确认成功；未使用 migration repair、db pull 或历史数据回刷。

待完成门禁：将提交合并并推送 `origin/main`，发布 Vercel 控制面，重载 `com.investhub.x-worker`，然后在已登录普通用户会话完成稳定 `/x` 的桌面与 375px 只读验收。没有下一次正常 v4 scheduler window 前，不把生产端到端 v4 持久化写成已证明。
