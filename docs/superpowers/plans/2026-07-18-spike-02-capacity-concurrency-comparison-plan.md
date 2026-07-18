# Spike-02：1000 条 5/10 并发容量对比验证计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在相同 `chunk-size=100` 和 Codex CLI 安全边界下，分别运行 1000 条 synthetic fixture 的 5 并发与 10 并发，比较最终可用性、重试代价、实际并发和批次效率。

**Architecture:** 不修改现有 runner、Provider、Prompt、Schema 或 timeout 代码，只使用当前 CLI 的 `--max-concurrency` 参数执行两轮独立容量探针。允许单次请求 timeout/provider failure 后在最多 3 次尝试内恢复成功；最终结果、证据完整性、进程组清理和状态目录边界仍是硬门槛。完成后统一比较并更新治理文档。

**Tech Stack:** 已有 Python 3.11+ 标准库 harness；Codex CLI `codex exec`；本地 JSON/JSONL evidence；shell/Python 标准库校验命令；现有 `unittest` 测试套件。

## Global Constraints

- 当前仍处于 Discovery；本计划只验证 Spike-02 容量和并发差异，不授权 V0/V1 生产实现。
- 两轮均固定使用 `--synthetic-count 1000`、`--chunk-size 100`、`--max-attempts 3` 和 `--codex-timeout-seconds 240`；只改变 `--max-concurrency` 为 5 或 10。
- 每个 chunk 继续使用独立、非交互的 `codex exec`，保留 `--sandbox read-only`、`--add-dir <CODEX_HOME>`、`--ephemeral` 和 `--output-last-message`。
- 单次 timeout/provider failure 在 3 次尝试内恢复成功属于 `recoverable_failure`，必须记录但不单独判定整轮失败；最终失败、超过最大尝试、状态竞争、evidence 错配和进程清理异常仍判失败。
- 两轮使用独立 evidence 目录，不覆盖既有串行、2 并发、5 并发探针或 Repeat-2 失败 evidence；Prompt、完整响应、诊断、凭据和私有状态不进入 Git。
- synthetic fixture 只支持容量和调度结论，不支持业务事实、归因或媒体质量结论；总体 Spike-02 结论保持 `unverified`。
- 若出现硬基础设施故障（状态目录竞争、进程组无法清理、EvidenceStore 损坏），立即停止后续真实调用；若只是某一轮最终失败，保留该轮并继续另一种配置以完成对比，但不得用成功配置掩盖失败配置。

---

### Task 1: Preflight and evidence isolation

**Files:**
- Read: `docs/superpowers/specs/2026-07-18-spike-02-capacity-concurrency-comparison-design.md`
- Read: `docs/project-status.md`
- Read: `docs/spikes/2026-07-15-spike-02-decision-report.md`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-20260718`

**Interfaces:**
- Consumes: approved 1000-message 5/10 concurrency Spec and existing `spike_02.cli` command.
- Produces: clean branch state, available Codex CLI, and unused evidence paths.

- [ ] **Step 1: Verify branch state**

Run:

```bash
git status --short --branch
git -C /Users/hanyuec/Desktop/Invest_hub status --short --branch
```

Expected: current branch is `spike-02-implementation`, both the worktree and `main` are clean. Stop if unexpected changes exist.

- [ ] **Step 2: Verify Codex CLI boundary**

Run:

```bash
codex --version
codex exec --help
```

Expected: Codex is available and help includes `--sandbox`, `--add-dir`, `--ephemeral`, and `--output-last-message`.

- [ ] **Step 3: Verify fresh evidence paths**

Run:

```bash
for path in \
  /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-20260718; do
  test ! -e "$path" || { echo "evidence path already exists: $path"; exit 2; }
done
```

Expected: both paths are unused. If a path exists, choose a new suffixed path rather than deleting or overwriting evidence.

### Task 2: Run and validate 1000-message capacity with 5 concurrency

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718`
- Modify: none in the repository

**Interfaces:**
- Consumes: `PYTHONPATH=spikes python3 -m spike_02.cli codex` with `--max-concurrency 5`.
- Produces: one 1000-message capacity evidence set and run-level metrics.

- [ ] **Step 1: Run the 5-concurrency test**

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

Expected: command exits 0 and prints a JSON summary. A recoverable timeout/retry is recorded and inspected; a final failure, state conflict, evidence error, or cleanup failure stops further real calls.

- [ ] **Step 2: Validate the 5-concurrency evidence**

Run:

```bash
EVIDENCE_DIR=/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718 python3 -c 'import json, os; from pathlib import Path; root=Path(os.environ["EVIDENCE_DIR"]); m=json.loads((root/"metrics.json").read_text()); req=[json.loads(x) for x in (root/"requests.jsonl").read_text().splitlines() if x.strip()]; res=[json.loads(x) for x in (root/"results.jsonl").read_text().splitlines() if x.strip()]; raw=list((root/"raw_responses").glob("*.json")); final_results=m["results"]; assert m["chunk_size"] == 100 and m["max_concurrency"] == 5 and m["max_active_requests"] <= 5; assert m["final_success_rate"] == 1.0 and m["json_parse_rate"] == 1.0; assert len(final_results) == len(res) == 10 and len({row["chunk_id"] for row in final_results}) == 10; assert len(req) == len(raw) == m["request_count"]; assert all(row["attempt"] <= 3 for row in req); assert all(row["status"] == "success" for row in final_results); print({"request_count":m["request_count"],"retry_count":m["retry_count"],"first_success_rate":m["first_success_rate"],"final_success_rate":m["final_success_rate"],"p50_latency_ms":m["p50_latency_ms"],"p95_latency_ms":m["p95_latency_ms"],"batch_elapsed_ms":m["batch_elapsed_ms"],"max_active_requests":m["max_active_requests"],"request_statuses":sorted({row["provider_response_status"] for row in req})})'
```

Expected: 10 final successful chunk results, request/raw counts match, every attempt is at most 3, and the printed status distribution identifies any recoverable timeout or provider failure.

- [ ] **Step 3: Check repository state after the run**

Run:

```bash
git status --short --branch
```

Expected: no repository changes; evidence remains outside Git.

### Task 3: Run and validate 1000-message capacity with 10 concurrency

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-20260718`
- Modify: none in the repository

**Interfaces:**
- Consumes: the same fixture, prompt, Provider and timeout boundary with `--max-concurrency 10`.
- Produces: one independent 1000-message capacity evidence set for comparison.

- [ ] **Step 1: Run the 10-concurrency test**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 10 \
  --codex-timeout-seconds 240
```

Expected: command exits 0 and prints a JSON summary. Treat final failures, state conflicts, evidence errors, or process cleanup failures as hard failures for the 10-concurrency configuration.

- [ ] **Step 2: Validate the 10-concurrency evidence**

Run the Task 2 Step 2 validation command with these exact substitutions:

```text
EVIDENCE_DIR=/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-20260718
m["max_concurrency"] == 10
m["max_active_requests"] <= 10
```

Keep the remaining assertions unchanged: 10 final successful results, JSON/Schema rate 100%, request/raw counts matching, and attempts no greater than 3.

- [ ] **Step 3: Check repository state after the run**

Run:

```bash
git status --short --branch
```

Expected: no repository changes; both evidence sets remain local-only.

### Task 4: Compare and classify the two configurations

**Files:**
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-20260718/metrics.json`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-20260718/metrics.json`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-20260718/metrics.json`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c2-20260718/metrics.json`
- Read: `/private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c5-20260718/metrics.json`
- Modify after both runs: `docs/spikes/2026-07-15-spike-02-decision-report.md`
- Modify after both runs: `docs/project-status.md`
- Modify after both runs: `docs/engineering-journal/2026-07-15-spike-02.md`

**Interfaces:**
- Consumes: both 1000-message evidence sets and prior serial/2/5 concurrency baselines.
- Produces: de-identified comparison, per-configuration classification, and updated next gate.

- [ ] **Step 1: Build the comparison table**

For serial c100, 2 concurrency c100, prior 5 concurrency c100, 1000 c100/c5 and 1000 c100/c10, record: input size, request count, result count, retry count, first/final success rate, JSON/Schema rate, P50/P95, batch wall-clock, configured/observed concurrency, and failure categories. Compute speedup using batch wall-clock where available; do not compare only per-request averages.

- [ ] **Step 2: Assign per-configuration outcomes**

Use exactly one label per 1000-message configuration:

```text
capacity_probe_pass: final success and evidence/process boundaries complete, with any retries explicitly recorded
capacity_probe_recoverable: final success but timeout/provider retry occurred; requires repeat validation
capacity_probe_failed: final failure, exceeded attempts, state conflict, evidence mismatch, or cleanup failure
unverified: evidence missing or validation incomplete
```

Do not let a successful 5-concurrency run mask a failed 10-concurrency run, or vice versa. Keep the overall Spike-02 conclusion `unverified`.

- [ ] **Step 3: Update the engineering journal**

Add a dated entry with de-identified metrics, evidence directory names, recoverable failure categories, and the two classifications. Do not add Prompt text, complete model output, credentials or private fixture data.

- [ ] **Step 4: Update project status and decision report**

Record whether 5 and 10 concurrency are viable Spike candidates, whether retries were recoverable, and the next gate. Do not describe either value as a production default or SLA.

### Task 5: Final verification and commit

**Files:**
- Verify: existing deterministic tests and intended governance documents
- Modify: none after the Task 4 documentation review

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

Expected: only intended governance-document changes are present; local evidence is outside Git; `main` remains clean.

- [ ] **Step 3: Commit the recorded comparison**

Run:

```bash
git add docs/spikes/2026-07-15-spike-02-decision-report.md docs/project-status.md docs/engineering-journal/2026-07-15-spike-02.md
git commit -m "docs: record Spike-02 five-ten concurrency comparison"
```

Expected: commit succeeds and the worktree is clean.
