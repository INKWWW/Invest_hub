# X 租约过期窗口自动跳过 Implementation Plan

> 本计划只覆盖 2026-08-17 scope amendment 的最小增量。

## Task 1：以 bounded lease expiry 复用现有 gap transition

- 先新增 pgTAP RED：来源 A 两次租约过期后不得产生第三次 attempt，必须写入 `lease_expired` gap 并让来源 B 可领取。
- 生成一份 additive migration；在现有 claim 前回收已过期且已有两次 attempt 的启用 X window。
- 将 attempt 标记为 `failed`，写安全 failure payload 与 task event，调用既有 `advance_x_failed_window_unchecked`。
- 保持原 claim 逻辑、Worker、Reader、日报和其他来源行为不变。
- 运行 focused RED/GREEN、全量 Supabase pgTAP、Worker、Control Plane、lint/build、redaction 和 diff 检查。
- 进行 fresh code review；发现 Critical/Important 问题必须回到 RED→GREEN。

## 生产边界

本计划只授权隔离 worktree 的本地实现、测试、commit 和 review。远程 migration、Worker 更新、部署、历史补采、真实 X/OpenCLI/Provider 调用均不执行。
