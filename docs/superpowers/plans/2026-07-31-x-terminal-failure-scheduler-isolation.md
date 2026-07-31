# X 终态失败来源调度隔离 Implementation Plan

> 本 Plan 属于用户已授权的窄范围生产失败修复；按“测试先行 → 最小 migration → 线上验证 → Worker 验收”执行。

## Task 1：建立失败回归

- [x] 新增 `supabase/tests/023_v2_x_terminal_failure_scheduler.sql`。
- [x] 覆盖终态失败来源延后、健康来源独立调度、失败任务不复制和失败审计保留。
- [x] 本地验证前先确认测试能在旧函数上失败。

## Task 2：实现最小数据库修复

- [x] 新增 `supabase/migrations/20260731100000_x_defer_terminal_failed_sources.sql`。
- [x] 仅替换 `public.enqueue_due_x_tasks`，保留原有权限边界和窗口算法。
- [x] 不改任务、coverage、来源配置或失败记录。

## Task 3：本地验证

- [x] `supabase db reset --yes` 重新加载全部 migrations。
- [x] `supabase test db`：302 项 pgTAP 全部通过。
- [x] Worker unittest：137 项全部通过。
- [x] `git diff --check` 通过。

## Task 4：线上部署与验收

- [ ] 使用 Supabase `apply_migration` 部署到生产项目 `invest-hub-v1`。
- [ ] 只读确认 `enqueue_due_x_tasks` 已包含延后逻辑，并确认当前失败来源不再生成重复终态任务。
- [ ] 重启本机 `com.investhub.x-worker`，观察其他来源继续领取/完成窗口。
- [ ] 记录线上结果；若失败来源仍为 `opencli_contract`，保持来源级隔离，不把它解释为“博主没有更新”。
