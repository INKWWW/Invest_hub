# V0 Worker

Worker 配置和设备凭据只保存在本地 owner-only 文件中。配置文件必须是 `0600` 或更严格，包含控制面 URL、逻辑 `source_id`、本地 Discord channel URL、Profile reference、OpenCLI contract version 和参数版本；云端 contract 不携带后三项敏感路径信息。

首次运行时，管理员提供一次性 Worker enrolment code。Worker 只把返回的设备密钥写入 owner-only credential store，enrolment code 不落盘。设备密钥撤销、过期或 lease 不确定时，Worker 进入 `recovering`，不会把任务回报为成功，也不会从本地猜测 checkpoint。

V0 的默认执行顺序是：

`heartbeat → claim → preflight → execute → report`

协议响应在进入状态机前先经过 `contracts/v0` JSON Schema 校验；日志只允许脱敏状态、计数、失败分类和逻辑 ID。
