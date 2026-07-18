# Spike-02 本地运行说明

本目录是一次性 Codex CLI 容量与质量验证 harness，不是生产应用代码。

## 运行时与安全边界

- 使用 Python 3.11 或更高版本的标准库；不安装生产依赖。
- `mock` 命令完全离线；`codex` 命令启动本机已登录的 Codex CLI。
- Codex CLI 每次调用使用非交互 `codex exec`、`--sandbox read-only` 和 `--ephemeral`。
- 仅通过 `--add-dir` 允许 Codex 写入自己的 `CODEX_HOME` 状态目录；项目 worktree 仍保持 read-only。
- Prompt 通过 stdin 传递，并要求 Codex 不使用工具、不读取项目文件、不执行项目命令、只返回 JSON。
- Codex CLI 不得修改 worktree；超时后 harness 会终止 Codex 子进程。
- 不需要项目级 API Key、Endpoint 或 Cookie 配置。
- 真实 fixture、Prompt、完整响应和历史数据只保存在本地受保护 evidence 目录。

开始前确认：

```bash
codex --version
codex exec --help
```

## 结构化输出契约

Codex 每个 chunk 必须返回 `topics`、`media_unparsed`、`media_source_message_ids` 和 `warnings`。当输入包含 `kind=unparsed_media` 的消息时，`media_source_message_ids` 必须列出当前 chunk 中全部这类消息的原始 ID；没有未解析媒体时必须为 `[]`。该字段只用于来源追溯，不表示 harness 会读取或推断媒体内容。

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
  --codex-timeout-seconds 240
```

### 有界并发

`--max-concurrency` 控制同时运行的独立 `codex exec` 请求数，默认值为 `1`，即串行兼容模式。容量 Spike 可以显式使用 `2`：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c2 \
  --chunk-size 100 \
  --max-concurrency 2 \
  --max-attempts 3 \
  --codex-timeout-seconds 240
```

并发只发生在不同 chunk 的 Provider 请求之间；单个 chunk 的重试仍由同一个 worker 独立完成。EvidenceStore 会串行化本地 JSONL/JSON 写入，并发上限和实际活动请求数会写入 `metrics.json` 的 `max_concurrency` 与 `max_active_requests`。

此前并发设计先验证了 `max-concurrency=2`；后续完整验证也覆盖了 `5` 和 `10` 并发的 1000 条 synthetic 重复运行。不复用 Codex 会话，也不引入 app-server、生产任务调度或更大的 chunk。规模 fixture 仍只用于容量与耗时观察，不能据此宣称真实业务质量通过。

运行规模 fixture：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c25 \
  --chunk-size 25 \
  --max-attempts 3 \
  --codex-timeout-seconds 240
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
