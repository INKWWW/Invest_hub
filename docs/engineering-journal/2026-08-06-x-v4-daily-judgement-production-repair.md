# X v4 当日判断生产修复

2026-08-06 的五个定时窗口均完成了采集结算，但“当日判断总结”进入 `judgement_failed`。排查确认不是 X 原始采集缺失，而是判断链路存在三个连续断点：生产数据库和 Worker 已使用 v4，Control Plane 仍以 v3 解析正常 context；旧批次终态失败且零版本时没有精确恢复入口；恢复写入版本后，batch 状态机仍拒绝受审计的 `judgement_failed -> succeeded`。

本次修复将正常 repository context/completion 合同对齐到 v4，保留独立 v3 verification replay；新增仅限 `service_role` 的 `recover_failed_x_daily_judgement`，只允许管理员对“终态失败、零版本、存在 Provider 输入、无活动 run”的原冻结 batch 新增 regeneration run；状态迁移仅在最新管理员 regeneration 已成功且 immutable version 已存在时开放。终态失败文案同步改为“已停止自动重试”。恢复过程中又发现 08:00 批次的模型连续把博主操作倾向写成命令式买卖句，确定性校验器正确拒绝了输出；最终保持校验器不变，仅把既有 Prompt 安全合同明确为中性“操作倾向为……”事实陈述，禁止复制“建议/应该/必须/立即 + 买卖操作”的命令句。

本地验证通过：Control Plane 239 项测试、lint 与 production build；Worker 189 项测试；Supabase 42 个文件、663 项 pgTAP；`git diff --check` 与 redact gate。生产 Control Plane deployment `dpl_BdTkfi2PCXDmGbCQZ8ZeyCLGrENQ` 为 Ready，稳定域名继续指向该部署；两条 additive migration `20260806231500`、`20260806233500` 已应用到生产 Supabase；本机 `com.investhub.x-worker` 已重启并加载修复后的 main。

生产恢复保留全部旧失败 run 与本地原始响应证据，没有重置 attempt、删除 batch 或重新采集。2026-08-06 的 00:00、08:00、12:00、16:00、20:00 五个原 batch 均为 `succeeded`，各有且仅有一个 revision 1，metadata 均为 `v4-x-cross-blogger`、`v4-x-cross-blogger-1`、`codex_cli`。已登录稳定 `/x` 的 2026-08-06 页面显示 20:00、16:00、12:00、08:00 均为“已更新”；页面顶部 00:00“判断处理中”属于 2026-08-07 自然启动的新调度批次，不是本次恢复失败。仍有一个既存 deferred X 来源被 fail-closed 排除，这是独立采集问题，不影响本次判断链路修复结论。
