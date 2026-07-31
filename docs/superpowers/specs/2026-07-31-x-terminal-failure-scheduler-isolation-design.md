# X 终态失败来源调度隔离 Spec

## 文档状态

- 阶段：V2 受控生产试运行的失败隔离修复
- 状态：**用户已授权自主批准、实施、部署与验收**
- 日期：2026-07-31
- 关联：[V2 X 信息收集与阅读设计](2026-07-22-v2-x-information-collection-and-reader-design.md)、[X 新博主当日自动激活设计](2026-07-27-x-source-same-day-auto-activation-design.md)

## 1. 问题与目标

定时调度器会为每个来源寻找最早未覆盖窗口。现有任务幂等逻辑只复用 `queued`、`leased`、`running` 和 `retryable_failed`，不复用终态 `failed`。因此某个 X 来源出现不可重试的 `opencli_contract` 失败后，每次 Worker tick 都会重新创建同一窗口，持续消耗 Worker 轮询并拖慢其他来源。

修复目标是把终态失败来源隔离在调度边界：同一来源、同一覆盖起点的终态失败窗口不再被重复创建；该来源保留失败审计和未推进水位，其他已解析且启用的来源仍可独立创建和领取自己的窗口。

## 2. 行为契约

`enqueue_due_x_tasks(worker_id, now)` 在计算来源的最早待补窗口前，检查该来源是否存在 `status = failed`、`task_type = x_sync`、窗口模式、窗口起点等于当前 `coverage_through_at` 且窗口终点晚于起点的终态任务。若存在，则跳过该来源，并在安全返回值的 `deferred_source_ids` 中记录来源 ID；不得创建重复任务。

没有终态失败任务的来源继续使用原有窗口计算和 `create_windowed_x_sync_task` 幂等逻辑。终态失败任务不被删除、不被自动改成成功或可重试，coverage 不前移；后续人工或受控身份/运行时修复仍可针对该来源单独处理。调度结果仅供 Worker 控制流使用，不向普通读者暴露内部诊断。

## 3. 非目标与安全边界

本修复不修改 X 账号标识、浏览器登录态、OpenCLI 合同、采集内容、摘要规则、Discord 任务或既有历史数据；不通过扩大重试次数掩盖失败，也不把失败来源误报为“没有更新”。真实网页会话、Cookie、Profile、帖子正文和 Prompt 均不进入数据库 migration、日志或 Git。

## 4. 验收标准

1. 一个具有终态失败窗口的来源在一次调度 tick 中不产生新任务，并出现在 `deferred_source_ids`。
2. 同一 tick 中的健康来源仍产生一个可领取窗口任务。
3. 终态失败任务数量、状态和失败审计保持不变。
4. 全量 pgTAP 与 Worker 回归通过；线上部署后，失败来源不再新增相同窗口任务，其他来源的 coverage/任务继续推进。
5. 发生回滚时只恢复旧调度函数，不删除任务或修改 coverage。
