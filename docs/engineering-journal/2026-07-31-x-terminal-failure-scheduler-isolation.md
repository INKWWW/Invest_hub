# X 终态失败来源调度隔离工程记录

## 结论

2026-07-31 已完成并部署 X 定时调度失败隔离修复。根因是 `enqueue_due_x_tasks` 不复用终态 `failed` 任务，导致同一不可重试窗口每个 Worker tick 被重新创建。修复后，当前最早窗口已有终态失败的来源会被延后，不再创建重复任务；其他来源继续独立调度。

## 实施与验证

- 新增并通过 `supabase/tests/023_v2_x_terminal_failure_scheduler.sql`：终态失败来源不复制、健康来源仍调度、失败审计保留。
- 本地 `supabase db reset --yes` 后运行 `supabase test db`：302 项 pgTAP 全部通过。
- Worker unittest：137 项全部通过。
- 生产 Supabase 项目 `invest-hub-v1` 已应用 migration `x_defer_terminal_failed_sources`，远端版本记录为 `20260731084640`；函数只读核对确认包含 `deferred_source_ids` 逻辑。
- 重启 `com.investhub.x-worker` 后，连续两个调度 tick 均为 `deferred_source_count=1`、`scheduled_task_count=5`，没有进入原先每 5 分钟重复创建失败任务的模式。

## 当前线上状态

`硅谷居士` 的 coverage 仍停留在 2026-07-25 16:00 UTC，失败分类仍为 `opencli_contract`；该来源被隔离，后续需单独修复身份/运行时合同后再受控重试。其余 5 位博主继续处理当日窗口；截至验收时，CHUIP LEUNG 已推进至 2026-07-31 12:00（上海时间），今天已有 AIInvestHK、CHUIP LEUNG、勃勃OC、来自上海的Vivian、金老师Herman Jin 的帖子或观点段数据。不能把“硅谷居士”当前无数据解释成其没有发文。

本次修复不删除任务、不修改来源标识、登录态、OpenCLI 合同或摘要规则；V2 仍保持“受控生产试运行”，不宣称无人值守 SLA。
