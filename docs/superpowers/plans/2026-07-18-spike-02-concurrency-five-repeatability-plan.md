# Spike-02：5 并发稳定性与 1000 条容量验证计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重复验证 `chunk-size=100`、`max-concurrency=5` 的 500 条 synthetic capacity，并在重复稳定后验证 1000 条容量和公开 fixture 并发 smoke。

**Architecture:** 不修改现有 runner、Provider、Prompt 或 Schema，只调用已经实现的 bounded worker runner。先完成 3 轮 500 条重复测试，全部通过后再运行 1000 条，最后运行公开小 fixture 的 configured max5 smoke 和质量边界检查；所有结果按统一指标校验并写入治理文档。

**Tech Stack:** 已有 Python 3.11+ 标准库 harness；Codex CLI `codex exec`；本地 JSON/JSONL evidence；shell 和 Python 标准库校验命令；现有 `unittest` 测试套件。

## Global Constraints

- 当前仍处于 Discovery；本计划只验证 Spike-02 容量和并发稳定性，不授权 V0/V1 生产实现。
- 固定使用 `chunk-size=100`、`max-concurrency=5`、`--max-attempts 3` 和 `--codex-timeout-seconds 240`；不修改 Prompt、Schema、重试策略或进程清理逻辑。
- 每个 chunk 继续启动独立的非交互 `codex exec`；继续使用 `--sandbox read-only`、`--add-dir <CODEX_HOME>`、`--ephemeral` 和 `--output-last-message`。
- 依次执行：3 轮 500 条重复测试 → 1 轮 1000 条容量测试 → 1 轮公开小 fixture smoke；任一 500 条重复轮次失败则停止，不执行 1000 条。
- 每轮使用独立 evidence 目录，不覆盖既有串行、2 并发或 5 并发 evidence；Prompt、完整响应、诊断、凭据和私有状态不进入 Git。
- 每轮必须校验 request/result/raw response 数量、chunk ID、成功率、重试、Schema 率、最大活动请求数、失败分类和 worktree 状态。
- synthetic fixture 只支持容量和调度结论，不支持业务事实、归因或媒体质量结论；总体 Spike-02 结论保持 `unverified`。
- 真实 Codex 命令需要在受控环境中运行；遇到 provider failure、timeout、状态目录竞争、evidence 错配或进程清理异常时保留 evidence 并停止后续扩大测试。

---

### Task 1: Preflight and evidence isolation

**Files:**
- Read: `docs/superpowers/specs/2026-07-18-spike-02-concurrency-five-repeatability-design.md`
- Read: `docs/project-status.md`
- Read: `docs/spikes/2026-07-15-spike-02-decision-report.md`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-1-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-2-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-3-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-small-c5-20260718`

**Interfaces:**
- Consumes: approved five-way repeatability Spec and the existing `spike_02.cli` command.
- Produces: clean worktree, available Codex CLI, and unused evidence paths.

- [ ] **Step 1: Verify branch and worktree state**

Run:

```bash
git status --short --branch
git -C /Users/hanyuec/Desktop/Invest_hub status --short --branch
```

Expected: current branch is `spike-02-implementation`, both the worktree and `main` are clean. Stop if either has unexpected changes.

- [ ] **Step 2: Verify Codex CLI boundary**

Run:

```bash
codex --version
codex exec --help
```

Expected: Codex is available and help includes `--sandbox`, `--add-dir`, `--ephemeral`, and `--output-last-message`.

- [ ] **Step 3: Verify evidence paths are unused**

Run:

```bash
for path in \
  /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-1-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-2-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-3-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-small-c5-20260718; do
  test ! -e "$path" || { echo "evidence path already exists: $path"; exit 2; }
done
```

Expected: no path exists. If a path exists, select a new suffixed path before any real run; never delete or overwrite prior evidence.

### Task 2: Run and validate 500-message repeatability rounds

**Files:**
- Create locally only: the three `codex-500-c100-c5-repeat-*` evidence directories from Task 1
- Modify: none in the repository

**Interfaces:**
- Consumes: `PYTHONPATH=spikes python3 -m spike_02.cli codex` and the synthetic fixture generator.
- Produces: three independent metrics/evidence sets, each with 5 initial chunks.

- [ ] **Step 1: Run Repeat-1**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-1-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 5 \
  --codex-timeout-seconds 240
```

Expected: command exits 0 and prints a JSON summary. If it reports any provider failure, timeout, malformed result, or state conflict, stop before Repeat-2.

- [ ] **Step 2: Validate Repeat-1 evidence**

Run:

```bash
python3 -c 'import json; from pathlib import Path; root=Path("/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-1-20260718"); m=json.loads((root/"metrics.json").read_text()); req=[json.loads(x) for x in (root/"requests.jsonl").read_text().splitlines() if x.strip()]; res=[json.loads(x) for x in (root/"results.jsonl").read_text().splitlines() if x.strip()]; raw=list((root/"raw_responses").glob("*.json")); assert m["chunk_size"] == 100 and m["max_concurrency"] == 5 and m["max_active_requests"] <= 5; assert m["request_count"] == 5 and m["retry_count"] == 0 and m["first_success_rate"] == 1.0 and m["final_success_rate"] == 1.0 and m["json_parse_rate"] == 1.0; assert len(req) == len(res) == len(raw) == 5; assert len({row["chunk_id"] for row in req}) == 5; assert all(row["provider_response_status"] == "success" for row in req); print({k:m[k] for k in ("batch_elapsed_ms","p50_latency_ms","p95_latency_ms","max_active_requests")})'
```

Expected: all assertions pass, five evidence rows/files exist, and no request status is outside `success`.

- [ ] **Step 3: Run and validate Repeat-2**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-2-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 5 \
  --codex-timeout-seconds 240
```

Then run the Task 2 Step 2 validation command with `root` set to `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-2-20260718`. Expected: all assertions pass. Stop before Repeat-3 on any unexplained failure.

- [ ] **Step 4: Run and validate Repeat-3**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-3-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 5 \
  --codex-timeout-seconds 240
```

Then run the Task 2 Step 2 validation command with `root` set to `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-repeat-3-20260718`. Expected: all assertions pass. Only continue to Task 3 if all three rounds pass.

### Task 3: Run and validate 1000-message capacity

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718`
- Modify: none in the repository

**Interfaces:**
- Consumes: three successful 500-message repeatability evidence sets and the same CLI boundary.
- Produces: one 1000-message synthetic capacity evidence set.

- [ ] **Step 1: Run the 1000-message test**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 5 \
  --codex-timeout-seconds 240
```

Expected: command exits 0 and prints a JSON summary. Any timeout, provider failure, state conflict, or malformed evidence makes the 1000-message gate fail; do not silently rerun with a lower concurrency in the same task.

- [ ] **Step 2: Validate the 1000-message evidence**

Run:

```bash
EVIDENCE_DIR=/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718 python3 -c 'import json, os; from pathlib import Path; root=Path(os.environ["EVIDENCE_DIR"]); m=json.loads((root/"metrics.json").read_text()); req=[json.loads(x) for x in (root/"requests.jsonl").read_text().splitlines() if x.strip()]; res=[json.loads(x) for x in (root/"results.jsonl").read_text().splitlines() if x.strip()]; raw=list((root/"raw_responses").glob("*.json")); assert m["chunk_size"] == 100 and m["max_concurrency"] == 5 and m["max_active_requests"] <= 5; assert m["request_count"] == 10 and m["retry_count"] == 0 and m["first_success_rate"] == 1.0 and m["final_success_rate"] == 1.0 and m["json_parse_rate"] == 1.0; assert len(req) == len(res) == len(raw) == 10; assert len({row["chunk_id"] for row in req}) == 10; assert all(row["provider_response_status"] == "success" for row in req); print({k:m[k] for k in ("batch_elapsed_ms","p50_latency_ms","p95_latency_ms","max_active_requests")})'
```

Expected: all assertions pass, with 10 request rows, 10 result rows, 10 raw response files, and 10 unique chunk IDs.

- [ ] **Step 3: Check the worktree gate**

Run:

```bash
git status --short --branch
```

Expected: no repository changes from the real run. Evidence must remain outside Git.

### Task 4: Run public-fixture concurrency and quality smoke

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-small-c5-20260718`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-small-c5-20260718/metrics.json`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-small-c5-20260718/results.jsonl`
- Modify: none in the repository

**Interfaces:**
- Consumes: public fixture, configured `max-concurrency=5`, and existing manual quality criteria.
- Produces: structural smoke evidence and a fresh quality-review decision.

- [ ] **Step 1: Run public-fixture smoke**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-small-c5-20260718 \
  --chunk-size 3 \
  --max-attempts 3 \
  --max-concurrency 5 \
  --codex-timeout-seconds 240
```

Expected: command exits 0, all four expected chunks produce valid results, `max_active_requests <= 4` because the fixture has four chunks, and evidence files are complete.

- [ ] **Step 2: Inspect fresh structural output**

For every result in `results.jsonl`, verify against `spikes/spike_02/fixtures/public_small.json` that every `source_message_id` is an input message ID, target topics retain the exact target author ID, and any unparsed media remains marked without inferred content. Use the existing Schema and evaluation tests as the interpretation reference; do not copy full responses into Git.

- [ ] **Step 3: Perform or explicitly scope the manual quality review**

If fresh output is manually reviewed, record whether all 6 claims are covered, grounded, and correctly attributed, with zero severe attribution errors and zero media hallucinations. If no fresh manual review is performed, record exactly: `并发 Schema smoke 通过、质量复核未新增`.

### Task 5: Compare, classify, and update durable records

**Files:**
- Modify: `docs/spikes/2026-07-15-spike-02-decision-report.md`
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-07-15-spike-02.md`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-20260718/metrics.json`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-20260718/metrics.json`

**Interfaces:**
- Consumes: all completed repeatability, 1000-message, and quality-smoke evidence.
- Produces: a dated, de-identified record of actual results and the next gate.

- [ ] **Step 1: Compute the comparison table**

Report for each completed run: initial chunk count, request/result/raw counts, first/final success rate, JSON/Schema rate, retry count, P50/P95, batch wall-clock, configured/observed concurrency, and failure categories. Compare the 5-concurrency runs with the serial c100 baseline of 645,827 ms and the prior 2-concurrency run of 321,965 ms. Include the full run-level range, not only averages.

- [ ] **Step 2: Classify the validation result**

Use exactly one of these descriptions:

```text
repeatability_pass: all three 500-message rounds pass the Spec gates
capacity_1000_pass: repeatability_pass plus the 1000-message run passes
quality_review_pass: fresh public-fixture manual review meets the 6/6 criteria
unverified: any required gate is missing, failed, or only structurally checked
```

Even if all three labels are achieved, keep the overall Spike-02 production conclusion `unverified` unless the previously approved upper-level quality and capacity gates are separately satisfied.

- [ ] **Step 3: Update the engineering journal**

Add a dated entry with only de-identified counts, timings, statuses, evidence directory names, and the classification. Do not include Prompt text, full model output, credentials, or private fixture content.

- [ ] **Step 4: Update project status and decision report**

Record whether 5 concurrency is a repeatable Spike candidate, whether 1000-message capacity passed, and whether fresh quality review was completed. Keep the next gate explicit and do not describe 5 concurrency as a production default.

### Task 6: Final verification and commit

**Files:**
- Verify: all intended governance documents and existing test files
- Modify: none after the Task 5 documentation review

- [ ] **Step 1: Run deterministic tests**

Run:

```bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
```

Expected: all deterministic tests pass.

- [ ] **Step 2: Check diff and repository state**

Run:

```bash
git diff --check
git status --short --branch
git -C /Users/hanyuec/Desktop/Invest_hub status --short --branch
```

Expected: only intended governance-document changes are present in the worktree; all local evidence remains outside Git; `main` remains clean.

- [ ] **Step 3: Commit the recorded result**

Run:

```bash
git add docs/spikes/2026-07-15-spike-02-decision-report.md docs/project-status.md docs/engineering-journal/2026-07-15-spike-02.md
git commit -m "docs: record Spike-02 five-way repeatability result"
```

Expected: commit succeeds and the worktree is clean.
