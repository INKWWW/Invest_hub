# V0 Control Plane / Worker Contracts

这些 JSON Schema 是 TypeScript 控制面和 Python Worker 之间的唯一协议来源。Schema 采用 JSON Schema draft 2020-12，新增字段必须保持向后兼容并提升 `contract_version` 或 `parameter_version`。

协议只传逻辑来源 ID、任务状态、计数、失败分类、时间、checkpoint 和 evidence 引用。Discord URL、Chrome Profile reference、Cookie、Token、Prompt 正文、完整模型响应和真实消息正文不得进入云端任务 payload 或事件。

`task-result.safe_checkpoint` 通过 Schema 做类型约束，再由 Worker 和控制面根据本次输入范围、持久化确认和 lease owner 做语义校验。Schema 通过不等于 checkpoint 可以推进。
