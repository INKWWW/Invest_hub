# X v3 验证回放 completion 修复与独立验收设计

## 目标

修复已上线 X v3 verification replay 在 completion 边界的确定性契约冲突，并以一个独立、一次性的 acceptance run 验证真实的 Worker → Control Plane → 数据库 → `/x` Reader 链路。该工作不得重试、改写或伪装为成功既有的失败 replay，也不得重新采集 X 或改变任何定时任务。

## 已确认事实与根因

2026-08-04 的一次 v3 replay 已成功完成所有 v3 单帖、单博主窗口和跨博主每日 Prompt 的结构化解析，但在最终 completion 时终态失败。原失败 replay 保持 `failed`，没有生成 replay segment、replay daily version 或 Reader 投影。

根因是三层 completion 契约不一致：Worker 的真实 payload 将 `daily.schema_version` 与 `daily.prompt_version` 作为 v3 输出身份的一部分传递；Control Plane HTTP 校验同样要求这两个字段；数据库 `complete_x_v3_verification_replay` 却将完整 `daily` 直接传给只允许纯 output 字段的 `validate_x_daily_judgement_output_v3`。后者因此必然拒绝含这两个元数据字段的有效 Worker payload。既有 pgTAP 成功 fixture 构造的是不含这两个字段的简化 payload，未覆盖真实 wire contract。

## 决策

### completion 契约规范化

Worker 与 HTTP payload 的 `daily` 保持现状，继续包含：`schema_version`、`prompt_version`、三个 viewpoints 数组及 `uncertainties`。这是运行时完整 v3 输出的规范形式。

完成 RPC 在验证与持久化前从 `daily` 派生 `daily_output`：仅保留三个 viewpoints 数组和 `uncertainties`。RPC 以 `daily_output` 调用既有 v3 output validator，并将其写入 `x_v3_verification_versions.output`；schema/prompt version 继续写入该表的独立列。它不放宽任何证据、来源、帖子、原子性、lease 或唯一性校验。

这是一条追加 migration 的 `create or replace function` 修复，不修改历史表行、不回写旧失败 replay，也不修改旧 migration 文件。

### 独立 acceptance run

既有 replay 的 `source_batch_id` 具有唯一约束，且其 `failed` 终态不得被重试。为验证修复后的真实链路，新增独立的 acceptance-run lifecycle，它只能以一个终态失败的 v3 replay 为父记录，并只读取该父 replay 已冻结的 source/post snapshot。

acceptance run 在创建时记录父 replay、请求者、状态、一次 claim、lease、枚举 failure class 与审计时间。每个父 replay 至多有一个 acceptance run；它拥有独立的 v3 segments 与 daily version 行，并在同一原子 completion 中写入 `analysis_version = 2`、acceptance segments 和 acceptance version。旧 replay、原 batch、原 daily run、v2 行和任何已存在的 checkpoint 均不被更新。

acceptance run 的 Worker 命令是显式一次性入口，不接入 `run-scheduled`、launchd、cron、scheduler、OpenCLI 或浏览器。它仅使用已冻结输入重新运行 `v3 post → v3 window → v3 cross-blogger`，任一失败即将 acceptance run 终态标记为 `failed`，不自动重试。

`/x` 只展示成功 acceptance run 的结果，标签为“验证恢复（非定时任务）”。原定时 batch 的“判断失败”状态与原 failed replay 的审计事实保持可见；UI 不显示内部 ID、Prompt、原始正文、本地路径或 Provider telemetry。

## 非范围

- 不修改旧 failed replay、原 08:00 batch、daily run、v2/v3 历史行、coverage 或 checkpoint。
- 不放宽既有 `x_v3_verification_replays.source_batch_id` 的唯一约束。
- 不执行 X 采集，不新增或修改任何 launchd、cron、scheduler 或正常 Worker 流程。
- 不新增面向普通用户的管理入口，也不扩展到其他 failed batch。

## 验收标准

1. pgTAP 首先以真实 Worker wire payload 证明当前 completion RPC 会失败；修复后同一 payload 成功，`output` 不含 schema/prompt 元数据而版本列正确，且任一失败仍无部分写入。
2. Control Plane 与 Worker 测试覆盖完整 payload 不被 HTTP 拒绝，并将 completion API 的已知拒绝原因映射为可审计的 failure class，而不误称 Provider 失败。
3. acceptance run 测试证明它只能从目标 failed replay 创建、每父 replay 只能创建一次、不能调用 scheduler/OpenCLI/Browser，且不修改父 replay 或原 batch。
4. 生产验收只运行一个新的显式 acceptance run；只读核验旧 replay 仍为 `failed`、未新增 scheduled work、acceptance 生成完整 v3 artifacts；已认证 `/x` 展示“验证恢复（非定时任务）”且无内部字段泄露。

## 回滚与故障处置

采用追加 migration，不执行 destructive rollback。若 acceptance run 失败，保留其独立失败审计并停止，不创建第二条 acceptance run、不触发原 replay 或任何定时任务。若生产 UI 或契约校验失败，回退 Control Plane/Worker 代码部署；已经写入的不可变审计事实保持原样。
