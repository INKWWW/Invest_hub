# Spike-02 本地运行说明

本目录是一次性 LLM 容量与质量验证 harness，不是生产应用代码。

## 运行时与安全边界

- 使用 Python 3.11 或更高版本的标准库；不安装生产依赖。
- `mock` 命令完全离线；`glm` 命令只向用户配置的 GLM endpoint 发起请求。
- API key 只从环境变量读取，不作为命令行参数，不写入日志或安全遥测。
- 真实 fixture、Prompt、完整响应和历史数据只保存在本地受保护 evidence 目录。
- Codex CLI 不属于 Spike-02；GLM 失败不会自动切换 Codex。

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

## GLM 运行

运行前在本地设置：

```bash
export SPIKE02_GLM_API_KEY='本地密钥'
export SPIKE02_GLM_ENDPOINT='当前 GLM endpoint'
export SPIKE02_GLM_MODEL='当前 GLM model'
```

然后运行小批次或规模 fixture：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli glm \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/glm-small \
  --chunk-size 3
```

Evidence 目录包含 `requests.jsonl`、`results.jsonl`、`metrics.json` 和只在本地保存的 `raw_responses/`。

## 人工质量复核

复核表每行需要包含 `case_id`、`claim_id`、`covered`、`grounded`、`correct_attribution`、`media_hallucination` 和 `note`，布尔字段只能使用 JSON true/false：

```bash
PYTHONPATH=spikes python3 -m spike_02.cli evaluate \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/glm-small \
  --review-file /private/tmp/invest-hub-spike-02-evidence/review.jsonl
```
