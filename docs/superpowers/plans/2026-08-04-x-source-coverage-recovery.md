# X 来源覆盖恢复与失败定位 Implementation Plan

**Goal:** 让来源终态失败可定位、可由受控 replacement 安全恢复，并为 2026-08-03 的独立 v3 回放准备完整事实输入。

**Architecture:** `task-failure` 新增有限 `failure_stage`，Worker 对 runtime 与 page-persistence 边界分别标记，控制面原样持久化安全枚举。数据库新增仅 admin/service-role 可调用的 terminal recovery RPC，创建新的同范围 `trigger=recovery` task，并以不可变 foreign key 指回原 failed task。它复用已有 range completion 和水位前移，不改写失败审计。

**Constraints:** 先测试后实现；不调用一次性 replay、不修改原 failed task、不直接更新 coverage/checkpoint、不自动重试、不提交真实 X 内容、handle、task ID 或凭据。

### Task 1: Failure-stage contract

- [ ] 在 Worker/控制面/pgTAP 先写红测试：安全 stage 传递、未知 stage 拒绝、event details 留存。
- [ ] 更新 JSON schema、路由类型、Worker error model与报告、runtime page persistence boundary、`record_task_failure` event details、管理员时间线。
- [ ] 跑 focused Worker、控制面与 migration pgTAP；确认既有无 stage payload 仍有效。

### Task 2: Terminal replacement authority

- [ ] 先写 pgTAP：管理员授权、only failed X window、exact watermark gate、single replacement、range/snapshot preservation、original immutability、scheduler defer/release。
- [ ] 用 `supabase migration new x_terminal_source_recovery` 创建追加 migration：允许 recovery trigger、增加 `recovered_from_task_id` 与唯一约束、创建和收紧 recovery RPC grants。
- [x] 更新 Worker claim validation 以接受 `recovery` 且禁止 scheduled window key；同步 `task-claim`、`window-range-completion` 与控制面镜像契约，防止服务端租约先成立而 Worker 因 claim response 不可解析进入循环；更新生成 DB 类型和最小控制面 repository（无新 UI）。
- [x] 为 X 长窗口增加逐条 post analysis 的 lease renewal；保留每个 capture page 持久化后的 renewal，避免 64 条以上的恢复窗口在最终 completion 前过期。
- [ ] 跑全部相关 pgTAP 和 Worker tests。

### Task 3: Release and source recovery

- [ ] 跑完整 `supabase test db`、Worker unittest、控制面 tests、lint、build、redaction 与 diff check。
- [ ] 暂停/重载 Worker 的短窗口内应用 migration、部署同一 main 的控制面与新 Worker，验证 schema/grants/Worker liveness；不输出 secrets。
- [ ] 先仅创建硅谷居士原 terminal window 的 replacement，等待终态并核对水位与 scheduler 追赶；再创建 Herman 原 16:00–20:00 replacement。
- [ ] 若 Herman 失败，依据新的安全 stage 做一次范围内修复；不盲目重试。成功后确认两个来源都恢复至可调度状态。

### Task 4: August 3 input recovery and v3 replay

- [ ] 为每个来源以不跨上海日期的 history tasks 补采 2026-08-03 必要区间，并只读验证 canonical/segment 事实。
- [ ] 完成并单独评审 `2026-08-04-x-v3-verification-replay` 草稿、实现与测试；只能在输入事实完整后运行。
- [ ] 创建新的 recovery batch/Reader projection，清晰标示为非定时恢复；验证原失败 batch 与新结果并存。
- [ ] 提交至 `main`、推送、部署稳定域并在已认证 `/x` 验收。
