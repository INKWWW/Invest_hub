# V0 Worker

Worker 配置和设备凭据只保存在本地 owner-only 文件中。配置文件必须是 `0600` 或更严格，包含控制面 URL、逻辑 `source_id`、本地 Discord channel URL、Profile reference、OpenCLI contract version 和参数版本；云端 contract 不携带后三项敏感路径信息。

首次运行时，管理员提供一次性 Worker enrolment code。Worker 只把返回的设备密钥写入 owner-only credential store，enrolment code 不落盘。设备密钥撤销、过期或 lease 不确定时，Worker 进入 `recovering`，不会把任务回报为成功，也不会从本地猜测 checkpoint。

V0 的默认执行顺序是：

`heartbeat → claim → preflight → execute → report`

协议响应在进入状态机前先经过 `contracts/v0` JSON Schema 校验；日志只允许脱敏状态、计数、失败分类和逻辑 ID。

## 本地 V0 验证

确定性 E2E 只使用公开 fixture、内存控制面和 Mock Provider：

```bash
V0_PYTHON_BIN=python3.11 bash scripts/v0/run-e2e.sh --mode deterministic --provider mock --chunk-size 100 --max-concurrency 5 --timeout-seconds 240 --max-attempts 3
```

执行真实 Discord 前，必须先用 Python 3.11+ 运行 `python3.11 scripts/v0/preflight.py`（或将同一解释器路径放入 `V0_PYTHON_BIN` 后通过 `run-e2e.sh` 调用）。真实模式要求显式设置 `V0_REAL_DISCORD_ACK=authorized`，并使用 Codex CLI；没有用户明确授权的专用 Profile 和已登录来源时，脚本会拒绝启动，不会把缺失配置当作空数据成功。

若控制面使用 Vercel Preview 的部署保护，管理员应在 Vercel 为该项目创建仅用于本次 V0 验收的自动化绕过密钥，并把它只保存到本机 owner-only 文件。运行前由本机 Shell 读取该文件并设置 `V0_VERCEL_PROTECTION_BYPASS`；Worker 和 preflight 仅将该值作为 `x-vercel-protection-bypass` 请求头发送，绝不写入 Worker 配置、设备凭据、证据、日志或 Git。不要把该值粘贴到终端历史、聊天或 Vercel 环境变量。

真实执行使用下列本地路径参数，不会把它们写入任务 payload、日志或 Git：

```bash
V0_REAL_DISCORD_ACK=authorized V0_PYTHON_BIN=python3.11 \
  bash scripts/v0/run-e2e.sh --mode real-discord --provider codex \
  --chunk-size 100 --max-concurrency 5 --timeout-seconds 240 --max-attempts 3 \
  --worker-config /private/v0-worker.toml \
  --credential /private/v0-worker-credentials.json \
  --opencli-contract /private/opencli-browser-bridge-contract.json \
  --prompt-path /private/v0-codex-prompt.md \
  --evidence-dir /private/invest-hub-v0-evidence \
  --enrolment-code-file /private/v0-worker-enrolment-code.txt
```

首次 enrolment 后可删除 `--enrolment-code-file` 参数；一次性邀请码不应长期保留。Worker 会使用已验证的 Browser Bridge 会话读取用户本来就有权限查看的 Discord 页面，先保存本地证据并写入远程持久化收据，再回报结果和推进 checkpoint。任何失败都会按失败类别回报为可重试状态；不会把本地空结果当作成功。

仓库提交前运行 `bash scripts/v0/redact-check.sh`。真实正文、Cookie、Token、Profile 路径、Prompt 和完整 Provider 响应只允许留在本地受保护 evidence 目录，不进入 Git、控制面任务 payload 或管理员调试 API。

## V1.1 本地定时 Agent

V1.1 的时间窗由控制面按上海时区的 00:00、08:00、16:00、20:50 和来源 `coverage_through_at` 计算；本地 Worker 每分钟只请求一次安全的 schedule tick，不提交时间窗、范围或页数上限。错过的窗口由控制面按覆盖水位完整补投递，Worker 按来源顺序领取。

macOS 常驻运行使用明确的 `com.investhub.discord-worker` label。先以 `--check-only` 验证 owner-only 的 runtime config、credential、private Prompt 和 evidence 目录；安装或卸载都必须由管理员在核对 label 与绝对路径后另行明确执行。脚本不接受目录通配符，卸载只会作用于该 label 对应的 plist。

```bash
bash scripts/v1/verify-launchd-worker.sh --check-only
```

`install-launchd-worker.sh` 需要显式 `--install`，并要求提供所有绝对路径；它不会默认写入 `~/Library/LaunchAgents`，避免误操作其他 Agent。真实安装前不得把路径、Prompt、凭据或 Profile 信息复制到 Git、聊天记录或日志中。
