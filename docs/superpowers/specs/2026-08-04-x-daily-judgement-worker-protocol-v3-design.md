# X 当日判断 Worker Protocol v3 修复设计

## 目标

修复跨博主当日判断 Prompt v3 已在控制面与 Runtime 生效、但本机 Worker HTTP Protocol 仍按 v2 校验的版本断层。此修复应让一次新的 v3 judgement 能从控制面上下文被读取、经现有 v3 Runtime 生成，并被 Worker 安全提交回控制面。

## 已确认事实

当前 Runtime 固定使用 `prompt_version = "v3-x-cross-blogger-1"`，生成 `schema_version = "v3-x-cross-blogger"`，包含 `security_industry_viewpoints`、`market_structure_viewpoints`、`strategy_mindset_viewpoints` 和 `uncertainties`。控制面、数据库和 Reader 已支持该合同。

`WorkerProtocol._parse_x_daily_judgement_context` 仍只接受 `v2-x-cross-blogger-1`；`_validate_x_daily_judgement_completion` 仍只接受 `v2-x-cross-blogger` 及两类旧字段。因此 v3 judgement 会在调用 Provider 前被拒绝；即使绕过读取阶段，也会在完成回执前被拒绝。没有明确 `failure_class` 的 `ProtocolError` 当前会被误报为 `persistence_failure`。

## 范围

1. 仅改 Worker Protocol 对 X 当日判断 context 和 completion 的本地严格校验，使其匹配已发布的 v3 合同。
2. 将 X 当日判断路径中的 `ProtocolError` 归类为 `schema_error`。
3. 增加一条经过真实 Protocol 本地解析与提交的 v3 跨边界回归测试，并保留针对非法 v3 completion 的拒绝测试。
4. 完成后仅允许正常调度产生新的 judgement；不重采集、不手工调用 Provider、不改写历史 judgement、不创建失败批次恢复入口，也不回刷任何日期。

## 非范围

本次不改 `v2_x_chunk.md`、`v2_x_window.md`、单帖/单博主窗口的 structured schema、数据库 migration、控制面 HTTP 路由、Reader、调度、采集、来源、checkpoint 或现有 v2 历史记录。三份 Prompt 的端到端 v3 对齐是独立后续项目，不能借本次故障修复绕过其 Spec/Plan。

## 合同与安全边界

- context 必须精确匹配当前既有字段集合，并且 `prompt_version` 必须为 `v3-x-cross-blogger-1`。
- completion 必须精确匹配 v3 字段集合和 `schema_version = "v3-x-cross-blogger"`；三类观点数组与顶层不确定性均为数组。
- 每个观点条目继续执行既有 v3 字段、安全 telemetry、来源/analysis/证据 ID、行动倾向、适用范围、条件和不确定性校验；不得放宽成透传 JSON。
- Protocol 本地拒绝属于 schema 契约失败，必须报告 `schema_error`，不得被描述为数据库持久化失败。
- 不在日志、测试 fixture 或文档中加入真实博主内容、私有 Prompt、Cookie、Profile、内部生产 ID 或原始证据。

## 验收标准

1. Worker Protocol 能读取有效 v3 context，并能提交有效的完整 v3 completion；请求 URL、认证和现有 endpoint 不变。
2. v2 context 或 v2 completion 会在 Worker 本地被拒绝，且不会发出 completion HTTP 请求。
3. 少字段、未知字段、非法行动倾向、缺失 `action_scope`、不安全 `model_reported` 或不满足同源证据关系的 v3 completion 均在本地被拒绝。
4. `ProtocolError` 在 X 当日判断失败回执中映射为 `schema_error`；其他既有 failure class 不改变。
5. 聚焦 Worker 单元测试与完整 Worker 回归通过；`git diff --check` 与 `bash scripts/v0/redact-check.sh` 通过。

## 发布与回滚

代码合入并部署控制面后，更新本机 Worker 到同一 `main` 提交并重启 `com.investhub.x-worker`，再以只读方式确认后续正常 judgement 的状态和 Reader 投影。若出现新的 protocol 拒绝，停止 Worker 的 judgement 领取、回退 Worker 代码到当前已验证版本；不删除、不改写任何 batch、run、version、证据或采集数据。
