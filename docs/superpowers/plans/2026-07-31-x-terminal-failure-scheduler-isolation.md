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

- [x] 使用 Supabase `apply_migration` 部署到生产项目 `invest-hub-v1`（远端版本 `20260731084640`）。
- [x] 只读确认 `enqueue_due_x_tasks` 已包含延后逻辑；部署后没有新增相同窗口的终态失败任务。
- [x] 重启本机 `com.investhub.x-worker`；连续两个 tick 报告 1 个延后来源、5 个正常调度来源。
- [x] 记录线上结果；`硅谷居士` 仍保留 `opencli_contract` 失败审计并被来源级隔离，不解释为“博主没有更新”。
