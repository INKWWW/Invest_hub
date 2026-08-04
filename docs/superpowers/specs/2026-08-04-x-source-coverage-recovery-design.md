# X 来源覆盖恢复与失败定位设计

## 目标

消除 `/x` 中由来源连续覆盖水位落后造成的“覆盖不完整”提示，同时保留每一次原始失败的审计事实。修复必须先让下一次失败可定位，再对已确认可恢复的终态窗口创建受控 replacement task；不得修改、删除或把原失败任务写成成功。

## 已确认事实

“覆盖不完整”由 batch source 的 `source_behind_cutoff` 产生，表示该来源的 `source_collection_coverage.coverage_through_at` 未达到当日 batch cutoff，而非模型遗漏或 Reader 渲染漏项。硅谷居士停在 2026-07-26 00:00（上海），其终态窗口记录为 `opencli_contract`；一次不写库、不输出帖子正文的当前 Collection receipt 探针已经证明当前 OpenCLI 合同可用。金老师 Herman Jin 停在 2026-08-03 16:00（上海），其 16:00–20:00 窗口三次终态为 `persistence_failure`，旧失败 payload 没有记录发生在本地证据、远程 page persist、ack、lease renew 或 range completion 的哪一步。

`history` task 仅在其起点等于当前连续水位时才推进水位；非连续历史回补有意不移动水位。因此历史回补不能替代终态窗口的连续恢复。

## 决策

### 失败阶段协议

在现有 `task-failure` 契约增加可选、有限枚举的 `failure_stage`。它只描述系统边界，不包含异常原文、URL、Cookie、帖子内容或内部 ID。第一版枚举为：`collection_fetch`、`page_validation`、`page_mapping`、`page_boundary_validation`、`local_evidence_persistence`、`remote_page_persist`、`remote_page_acknowledgement`、`lease_renewal`、`range_completion`。

Worker 在本地 runtime 与远程持久化边界捕获并上报阶段；控制面把它写入既有 `task_attempts.failure` payload 和 `task_events.details`，管理员任务时间线可展示该安全标签。保留原有 broad `failure_class` 与 retry 策略，阶段不改变安全/重试语义。

### 终态窗口的 replacement recovery

新增 admin/service-role 受限的 `create_x_terminal_recovery_task(failed_task_id, requested_by)`。它只接受满足所有条件的 X `window` 终态失败任务：请求者为管理员、来源仍已启用/已解析、失败 range 起点仍严格等于该来源连续水位、没有活动 X task、原 task 未有 replacement。它创建一个新的 `x_sync` task，范围、来源快照、参数版本和 overlap 均来自原失败窗口，`capture_range.trigger = recovery`，并通过 `sync_tasks.recovered_from_task_id` 与原 task 建立只读关系。

replacement 通过同一 Worker、同一 page-level durability 与同一原子范围完成 RPC 运行。只有 replacement 成功时，现有连续水位逻辑前移；原 task 仍为 `failed`，其 task attempts/events 不变。调度器在 replacement 活动期间仍 defer 该来源，完成后因水位已越过原 range 起点而恢复正常逐窗口追赶。任何新失败都以新的 `failure_stage` 留痕，不自动创建第二个 replacement。

### 8 月 3 日历史事实与判断

在两个来源连续恢复确认后，使用现有受限 `history` 入口创建仅覆盖 2026-08-03、且不跨上海自然日的事实补采任务；它们不伪造连续水位。随后才执行独立的 v3 verification replay，并建立新的、明确标记为非定时恢复的 8 月 3 日判断投影。现有 `x_v3_verification_replay` 草稿是后一阶段，不与来源恢复 migration 混合部署。

## 非范围

- 不修改历史 failed task、其 attempt、失败 payload、覆盖水位或原有 daily batch。
- 不自动重试所有终态任务，也不新增常驻调度器、定时任务或 UI 操作入口。
- 不在错误阶段、管理页面或日志中写入原始帖子文本、X 登录态、异常堆栈或凭据。

## 验收标准

1. 合同、Worker、DB 测试证明失败阶段从 runtime 到 `task_attempts.failure` 与 `task_events.details` 的完整传递，未知阶段被拒绝。
2. DB 测试证明 replacement 只允许精确的终态水位阻塞窗口；其 range 与原窗口相同、原失败不变、同一原失败最多一个 replacement、活跃/已恢复/非管理员/水位不匹配均被拒绝。
3. Worker 测试证明 recovery trigger 通过同一严格 claim 校验；远程 persist、ack 与 lease 各自上报可区分的安全阶段。
4. 生产受控执行中，硅谷居士 replacement 成功后水位前移并恢复调度；Herman replacement 若仍失败，记录确切阶段后停止自动动作并据此修复，若成功则同样前移。
5. 仅在两个来源的 2026-08-03 历史事实成功持久化后，才运行独立 v3 replay；正式 Reader 既显示新恢复结果，也不抹去原失败记录。
