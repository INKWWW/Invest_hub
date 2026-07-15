# Spike-02 本地运行说明

本目录是一次性 Codex CLI 容量与质量验证 harness，不是生产应用代码。

## 运行时与安全边界

- 使用 Python 3.11 或更高版本的标准库；不安装生产依赖。
- `mock` 命令完全离线；`codex` 命令启动本机已登录的 Codex CLI。
- Codex CLI 每次调用使用非交互 `codex exec`、`--sandbox read-only` 和 `--ephemeral`。
- Prompt 通过 stdin 传递，并要求 Codex 不使用工具、不读取项目文件、不执行项目命令、只返回 JSON。
- Codex CLI 不得修改 worktree；超时后 harness 会终止 Codex 子进程。
- 不需要项目级 API Key、Endpoint 或 Cookie 配置。
- 真实 fixture、Prompt、完整响应和历史数据只保存在本地受保护 evidence 目录。

开始前确认：

```bash
codex --version
codex exec --help
```

## 确定性测试

```bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
```

## Mock 运行

```bash
PYTHONPATH=spikes python3 -m spike_02.cli mock \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/mock-small \
  --chunk-size 3
```

规模 fixture 只用于容量指标，可以直接生成：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli mock \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/mock-500 \
  --chunk-size 25
```

## Codex CLI 运行

Codex CLI 必须已经在本机完成登录。默认从 PATH 使用 `codex`；如需指定路径或模型，可设置：

```bash
export SPIKE02_CODEX_BIN='codex'
export SPIKE02_CODEX_MODEL='可选的 Codex 模型名称'
```

运行小批次：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-small \
  --chunk-size 3 \
  --max-attempts 3 \
  --codex-timeout-seconds 120
```

运行规模 fixture：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c25 \
  --chunk-size 25 \
  --max-attempts 3 \
  --codex-timeout-seconds 120
```

每次运行使用新的 evidence 目录，避免不同 Prompt、模型或失败状态混合。Evidence 包含 `requests.jsonl`、`results.jsonl`、`metrics.json` 和只在本地保存的 `raw_responses/`。

`requests.jsonl` 只保存 chunk、耗时、状态、退出码和诊断是否存在等遥测，不保存 Prompt 正文。完整 Codex 最终输出和诊断仅保存在本地 raw evidence。

## 人工质量复核

复核表每行需要包含 `case_id`、`claim_id`、`covered`、`grounded`、`correct_attribution`、`media_hallucination` 和 `note`，布尔字段只能使用 JSON `true`/`false`：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli evaluate \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-small \
  --review-file /private/tmp/invest-hub-spike-02-evidence/codex-review.jsonl
```

规模 fixture 只能支持容量结论；质量结论必须来自带人工标注的 fixture，并且可以回指消息 ID。

## 命令边界

- `mock`：离线确定性运行；
- `codex`：本机 Codex CLI 的非交互运行；
- `evaluate`：读取本地 evidence 和人工复核表；
- 不支持 `glm` 命令；
- Spike harness 不会自动切换 Provider，也不会把 Spike 结果直接升级为生产实现。
