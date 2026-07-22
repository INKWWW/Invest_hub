# V1.1 Discord Page Fetch 定时采集修订 Plan

> 仅在用户批准本 Plan 后实施。该 Plan 将 Page Fetch 接入既有四窗口任务；不创建独立的额外定时器。

**Plan status:** 已批准（用户确认 2026-07-22）。

**Spec:** [V1.1 Discord Page Fetch 定时采集修订 Spec](../specs/2026-07-22-v1-1-discord-page-fetch-scheduled-collection-amendment.md)

## Task 1：定义可替换的消息页传输契约并先写测试

**Files:**

- Modify: `workers/v0/src/invest_hub_worker/connectors/discord_active_adapter.py`
- Create/Modify: 相关 Page Fetch transport 模块与公开人工 fixture 测试
- Modify: `workers/v0/tests/test_discord_active_adapter.py`、`workers/v0/tests/test_windowed_runtime.py`

**工作：**

1. 将“读取一页消息”的输入/输出明确为目标来源、任务 `end_at`、请求 cursor 和已验证页；输出下一 cursor、页时间边界、匹配/新鲜 telemetry 与安全错误类别。
2. 先写跨 7、25、100+ 页、晚到消息、空窗、重启恢复、cursor 异常和认证/限流失败的 fixture 测试。
3. 保持现有 capture segment、resume、range complete 和 coverage 事务不变；传输实现不能绕过持久化或边界验证。

## Task 2：实现页面上下文 Page Fetch transport

**Files:**

- Create: Page Fetch transport 实现及对应单元测试
- Modify: Worker owner-only runtime 配置解析与安全遥测

**工作：**

1. 通过既有 OpenCLI Browser Bridge 的已绑定页面上下文读取目标频道消息页；不得读取、导出或落盘认证材料。
2. 先验证目标路由与响应形状；只接受与当前任务来源匹配的新鲜页。
3. 归一化后立即进入既有 raw/Canonical 持久化链路；日志只保留安全 telemetry。
4. 只遵循服务端返回的失败/等待语义；遇到 401、403、429、挑战、错配或 cursor 异常即停止该任务，不使用伪装、代理或规避性重试。

## Task 3：接入既有四窗口与手动任务

**Files:**

- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Modify: 相关 Worker、runtime 和 scheduler 测试

**工作：**

1. 既有 00:00、08:00、16:00、20:50 的任务和管理员手动任务自动使用 Page Fetch transport；不新建 cron、不改变任务范围。
2. 各来源保持串行；故障任务恢复优先，较晚窗口不得越过缺口完成。
3. 删除任何仍假设“UI 滚动已成功触发历史页”的生产分支；保留无 max-pages、lease、resume、边界证据和失败不推进 coverage 的不变量。

## Task 4：全量验证与受控真实验收

本地验证依次运行 Worker 测试、数据库测试、控制面测试/lint/build、V1.1 E2E、redaction 检查与 Git diff 检查。

真实验收顺序：

1. 用户确认第一个既有来源和一次正常窗口；
2. 观察完整范围、持久化、作者解析和 Reader 更新，不输出真实内容；
3. 用户确认后测试一次管理员手动更新；
4. 用户确认后扩展到第二来源；
5. 任何认证、限流、挑战或异常立即停止，记录安全诊断，不继续重试。

通过所有确定性验证和真实验收后，更新 engineering journal、`docs/project-status.md` 与 V1.1 原 Spec/Plan 的批准状态；运行 redaction 检查后再提交和部署。不得把未通过的真实验收标记为正式可用。
