# Spike-02：完整容量稳定性与质量验证计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改 Spike-02 harness 的前提下，完成 1000 条 c100/c5 与 c100/c10 的重复容量验证，以及一轮带人工标注公开 fixture 的新鲜质量复核，解除或准确保留 Spike-02 的 `unverified` 状态。

**Architecture:** 复用现有 Codex CLI Provider、chunking、Schema、runner、重试和 evidence 逻辑。已有 1000 条 c5/c10 单轮结果作为各自第一个样本，新增四个独立容量运行目录和一个公开质量运行目录；完成后只更新 decision report、project-status 和 engineering journal。

**Tech Stack:** Python 3.11+ 标准库；`codex exec`；本地 JSON/JSONL evidence；现有 `unittest` 和 `evaluate` 命令；不安装依赖、不创建生产代码。

## Global Constraints

- 当前仍处于 Discovery；不把 5/10 并发写成生产默认值，不批准 Codex CLI 为最终生产 Provider。
- 容量运行固定使用 1000 条 synthetic、`chunk-size=100`、`max-attempts=3`、`codex-timeout-seconds=240`；c5/c10 只改变 `--max-concurrency`。
- 每个 Codex 请求继续使用 `--sandbox read-only`、`--add-dir <CODEX_HOME>`、`--ephemeral` 和 `--output-last-message`，不复用 Codex 会话。
- 新增 evidence 目录必须不存在；不得覆盖已有 c5/c10 单轮、500 条 Repeat-1/Repeat-2 或早期失败 evidence。
- timeout/provider failure 在最多 3 次尝试内恢复成功时允许作为 `recoverable_failure`，但必须记录首次成功率、重试数、失败状态和 P50/P95；最终失败、超过尝试次数、状态竞争、证据错配和进程清理异常是硬失败。
- 公开质量运行使用 `spikes/spike_02/fixtures/public_small.json`，完整响应和人工 review JSONL 只保存在 `/private/tmp`，不进入 Git。
- 任何真实 Codex 运行不得修改 worktree；运行后检查 worktree 和 `main` 状态。

---

### Task 1: Preflight and evidence isolation

**Files:**
- Read: `docs/superpowers/specs/2026-07-18-spike-02-complete-verification-design.md`
- Read: `docs/project-status.md`
- Read: `docs/spikes/2026-07-15-spike-02-decision-report.md`
- Read: `docs/engineering-journal/2026-07-15-spike-02.md`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-1-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-2-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-1-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-2-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718`

**Interfaces:**
- Consumes: approved complete-verification Spec and existing `spike_02.cli` command.
- Produces: clean branch state, available Codex CLI, and five unused evidence paths.

- [ ] **Step 1: Verify branch and main state**

Run:

```bash
git status --short --branch
git -C /Users/hanyuec/Desktop/Invest_hub status --short --branch
```

Expected: current branch is `spike-02-implementation`, current worktree and `main` are clean. Stop before real calls if either contains unexpected changes.

- [ ] **Step 2: Verify Codex CLI boundary**

Run:

```bash
codex --version
codex exec --help | rg -- '--sandbox|--add-dir|--ephemeral|--output-last-message'
```

Expected: Codex is available and all four required flags are present.

- [ ] **Step 3: Verify all evidence paths are unused**

Run:

```bash
for path in \
  /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-1-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-2-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-1-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-2-20260718 \
  /private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718; do
  test ! -e "$path" || { echo "evidence path already exists: $path"; exit 2; }
done
```

Expected: all five paths are unused. If any path exists, append a unique suffix to that path and use the new path consistently; never delete or overwrite it.

### Task 2: Run and validate 1000-message c5 repeat 1

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-1-20260718`
- Modify: none in the repository

**Interfaces:**
- Consumes: current `spike_02.cli` Codex command with `--max-concurrency 5`.
- Produces: one independent c5 repeat evidence set.

- [ ] **Step 1: Run the c5 repeat 1 capacity test**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-1-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 5 \
  --codex-timeout-seconds 240
```

Expected: command exits 0 and prints a JSON summary. Preserve and inspect any recoverable timeout/retry; stop this configuration if a final failure, evidence error, state conflict or cleanup failure occurs.

- [ ] **Step 2: Validate c5 repeat 1 evidence**

Run:

```bash
EVIDENCE_DIR=/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-1-20260718 python3 -c 'import json, os; from pathlib import Path; root=Path(os.environ["EVIDENCE_DIR"]); m=json.loads((root/"metrics.json").read_text()); req=[json.loads(x) for x in (root/"requests.jsonl").read_text().splitlines() if x.strip()]; res=[json.loads(x) for x in (root/"results.jsonl").read_text().splitlines() if x.strip()]; raw=list((root/"raw_responses").glob("*.json")); final=m["results"]; assert m["chunk_size"]==100 and m["max_concurrency"]==5 and m["max_active_requests"]<=5; assert m["final_success_rate"]==1.0 and m["json_parse_rate"]==1.0; assert len(final)==len(res)==10 and len({x["chunk_id"] for x in final})==10; assert len(req)==len(raw)==m["request_count"]; assert all(x["attempt"]<=3 for x in req); assert all(x["status"]=="success" for x in final); print({k:m[k] for k in ("request_count","retry_count","first_success_rate","final_success_rate","p50_latency_ms","p95_latency_ms","batch_elapsed_ms","max_active_requests")})'
```

Expected: all assertions pass; record the printed metrics and any request status other than `success` for the aggregate comparison.

- [ ] **Step 3: Check repository state**

Run:

```bash
git status --short --branch
```

Expected: no repository changes.

### Task 3: Run and validate 1000-message c5 repeat 2

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-2-20260718`
- Modify: none in the repository

**Interfaces:**
- Consumes: same fixture, prompt, schema, timeout and retry boundary as Task 2.
- Produces: the third c5 sample when combined with the existing c5 single run and Task 2.

- [ ] **Step 1: Run c5 repeat 2**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-2-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 5 \
  --codex-timeout-seconds 240
```

Expected: command exits 0; preserve all evidence even if a retry or final failure occurs.

- [ ] **Step 2: Validate c5 repeat 2 evidence**

Run:

```bash
EVIDENCE_DIR=/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c5-complete-repeat-2-20260718 python3 -c 'import json, os; from pathlib import Path; root=Path(os.environ["EVIDENCE_DIR"]); m=json.loads((root/"metrics.json").read_text()); req=[json.loads(x) for x in (root/"requests.jsonl").read_text().splitlines() if x.strip()]; res=[json.loads(x) for x in (root/"results.jsonl").read_text().splitlines() if x.strip()]; raw=list((root/"raw_responses").glob("*.json")); final=m["results"]; assert m["chunk_size"]==100 and m["max_concurrency"]==5 and m["max_active_requests"]<=5; assert m["final_success_rate"]==1.0 and m["json_parse_rate"]==1.0; assert len(final)==len(res)==10 and len({x["chunk_id"] for x in final})==10; assert len(req)==len(raw)==m["request_count"]; assert all(x["attempt"]<=3 for x in req); assert all(x["status"]=="success" for x in final); print({k:m[k] for k in ("request_count","retry_count","first_success_rate","final_success_rate","p50_latency_ms","p95_latency_ms","batch_elapsed_ms","max_active_requests")})'
```

Expected: the same hard assertions either pass, or the failure category is recorded without deleting the evidence.

### Task 4: Run and validate 1000-message c10 repeat 1

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-1-20260718`
- Modify: none in the repository

**Interfaces:**
- Consumes: same fixture, prompt, schema, timeout and retry boundary with `--max-concurrency 10`.
- Produces: one independent c10 repeat evidence set.

- [ ] **Step 1: Run c10 repeat 1**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-1-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 10 \
  --codex-timeout-seconds 240
```

Expected: command exits 0; preserve all evidence and inspect retries before proceeding.

- [ ] **Step 2: Validate c10 repeat 1 evidence**

Run:

```bash
EVIDENCE_DIR=/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-1-20260718 python3 -c 'import json, os; from pathlib import Path; root=Path(os.environ["EVIDENCE_DIR"]); m=json.loads((root/"metrics.json").read_text()); req=[json.loads(x) for x in (root/"requests.jsonl").read_text().splitlines() if x.strip()]; res=[json.loads(x) for x in (root/"results.jsonl").read_text().splitlines() if x.strip()]; raw=list((root/"raw_responses").glob("*.json")); final=m["results"]; assert m["chunk_size"]==100 and m["max_concurrency"]==10 and m["max_active_requests"]<=10; assert m["final_success_rate"]==1.0 and m["json_parse_rate"]==1.0; assert len(final)==len(res)==10 and len({x["chunk_id"] for x in final})==10; assert len(req)==len(raw)==m["request_count"]; assert all(x["attempt"]<=3 for x in req); assert all(x["status"]=="success" for x in final); print({k:m[k] for k in ("request_count","retry_count","first_success_rate","final_success_rate","p50_latency_ms","p95_latency_ms","batch_elapsed_ms","max_active_requests")})'
```

Expected: all assertions pass; record metrics and request status categories.

### Task 5: Run and validate 1000-message c10 repeat 2

**Files:**
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-2-20260718`
- Modify: none in the repository

**Interfaces:**
- Consumes: same fixture, prompt, schema, timeout and retry boundary as Task 4.
- Produces: the third c10 sample when combined with the existing c10 single run and Task 4.

- [ ] **Step 1: Run c10 repeat 2**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-2-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 10 \
  --codex-timeout-seconds 240
```

Expected: command exits 0; preserve all evidence even if a retry or final failure occurs.

- [ ] **Step 2: Validate c10 repeat 2 evidence**

Run:

```bash
EVIDENCE_DIR=/private/tmp/invest-hub-spike-02-evidence/codex-1000-c100-c10-complete-repeat-2-20260718 python3 -c 'import json, os; from pathlib import Path; root=Path(os.environ["EVIDENCE_DIR"]); m=json.loads((root/"metrics.json").read_text()); req=[json.loads(x) for x in (root/"requests.jsonl").read_text().splitlines() if x.strip()]; res=[json.loads(x) for x in (root/"results.jsonl").read_text().splitlines() if x.strip()]; raw=list((root/"raw_responses").glob("*.json")); final=m["results"]; assert m["chunk_size"]==100 and m["max_concurrency"]==10 and m["max_active_requests"]<=10; assert m["final_success_rate"]==1.0 and m["json_parse_rate"]==1.0; assert len(final)==len(res)==10 and len({x["chunk_id"] for x in final})==10; assert len(req)==len(raw)==m["request_count"]; assert all(x["attempt"]<=3 for x in req); assert all(x["status"]=="success" for x in final); print({k:m[k] for k in ("request_count","retry_count","first_success_rate","final_success_rate","p50_latency_ms","p95_latency_ms","batch_elapsed_ms","max_active_requests")})'
```

Expected: the same hard assertions either pass, or the failure category is recorded without deleting the evidence.

### Task 6: Run and review fresh public quality evidence

**Files:**
- Read: `spikes/spike_02/fixtures/public_small.json`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718`
- Create locally only: `/private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718/review.jsonl`
- Modify: none in the repository

**Interfaces:**
- Consumes: public fixture with six human-labelled claims and current Codex CLI Provider.
- Produces: fresh structured output, validated metrics, and a local six-row manual review file.

- [ ] **Step 1: Run the fresh public quality case**

Run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718 \
  --chunk-size 100 \
  --max-attempts 3 \
  --max-concurrency 1 \
  --codex-timeout-seconds 240
```

Expected: one final successful result with JSON/Schema rate 100%; if the run has a final failure, retain evidence and mark the quality gate failed.

- [ ] **Step 2: Print the six claims and fresh result for manual comparison**

Run:

```bash
python3 -c 'import json; from pathlib import Path; fixture=json.loads(Path("spikes/spike_02/fixtures/public_small.json").read_text()); result=[json.loads(x) for x in Path("/private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718/results.jsonl").read_text().splitlines() if x.strip()][0]; print(json.dumps({"claims":fixture["claims"],"result":result},ensure_ascii=False,indent=2))'
```

Expected: inspect each claim against its declared source message IDs and the fresh result. Confirm coverage, grounding, attribution, ticker/price/tendency handling, reply context and `media_unparsed` behavior; do not infer any unparsed media.

- [ ] **Step 3: Write and validate the local review file**

Write exactly one JSON object for each of `claim-001` through `claim-006` to `review.jsonl`. Every object must contain the keys `case_id`, `claim_id`, `covered`, `grounded`, `correct_attribution`, `media_hallucination` and `note`; use `public-small-001` for `case_id`. Set booleans only from the manual comparison; do not default them to `true`. Then run:

```bash
PYTHONPATH=spikes python3 -m spike_02.cli evaluate \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718 \
  --review-file /private/tmp/invest-hub-spike-02-evidence/codex-public-small-quality-complete-20260718/review.jsonl
```

Expected: six reviewed claims; `covered=6`, `grounded=6`, `correct_attribution=6`, severe attribution errors `0`, media hallucinations `0`. Any severe attribution error or media hallucination fails the quality gate.

### Task 7: Aggregate complete verification and update governance documents

**Files:**
- Read: existing 1000 c5 metrics and the two new c5 repeat metrics
- Read: existing 1000 c10 metrics and the two new c10 repeat metrics
- Read: fresh public quality metrics and local `review.jsonl`
- Modify: `docs/project-status.md`
- Modify: `docs/spikes/2026-07-15-spike-02-decision-report.md`
- Modify: `docs/engineering-journal/2026-07-15-spike-02.md`

**Interfaces:**
- Consumes: four repeat evidence sets, two existing single-run capacity baselines and one fresh quality review.
- Produces: final de-identified conclusion, limitations and next gate.

- [ ] **Step 1: Build the comparison table**

Record for each of the six capacity samples: input count, chunk size, request count, result count, retry count, first/final success rate, JSON/Schema rate, P50/P95, batch wall-clock, configured/observed concurrency and failure categories. Compute c10-versus-c5 wall-clock speedup per matching run; do not compare only per-request latency.

- [ ] **Step 2: Apply the Spec conclusion rules**

Use exactly one outcome per concurrency configuration:

```text
capacity_stable_pass: all three runs pass hard gates with no retry or hard infrastructure error
capacity_stable_conditional: all three runs final-success and complete, but timeout/provider retry occurred
capacity_failed: any final failure, evidence mismatch, state conflict or cleanup failure
unverified: any required run or validation is missing
```

For the overall Spike-02 conclusion, combine both capacity outcomes and the fresh quality outcome exactly as defined in the Spec: `通过`, `有条件通过`, `不通过` or `未验证`. Preserve the known 500-message Repeat-2 timeout as a limitation; do not erase it because the 1000-message runs recover.

- [ ] **Step 3: Update the engineering journal**

Add a dated entry with the five new evidence directory names, de-identified capacity metrics, quality counts, retry categories and the final classification. Do not add Prompt text, complete Codex output, credentials, private fixture data or sensitive local review notes.

- [ ] **Step 4: Update project status and decision report**

Record the six capacity samples, fresh quality result, overall conclusion and next gate. If the gates pass, state the operational constraints explicitly; do not label 5/10 as production defaults or claim real-world business quality beyond the reviewed public fixture.

### Task 8: Final verification and commit

**Files:**
- Verify: `spikes/spike_02/tests/`
- Verify: the three governance documents from Task 7
- Modify: none after the document review

**Interfaces:**
- Consumes: completed evidence and governance updates.
- Produces: clean worktree with committed final verification record.

- [ ] **Step 1: Run deterministic tests**

Run:

```bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
```

Expected: all tests pass, currently 40/40.

- [ ] **Step 2: Check diff and both repository states**

Run:

```bash
git diff --check
git status --short --branch
git -C /Users/hanyuec/Desktop/Invest_hub status --short --branch
```

Expected: only the three intended governance documents changed in the worktree; `main` remains clean; all evidence stays outside Git.

- [ ] **Step 3: Commit the final verification record**

Run:

```bash
git add docs/project-status.md docs/spikes/2026-07-15-spike-02-decision-report.md docs/engineering-journal/2026-07-15-spike-02.md
git commit -m "docs: record Spike-02 complete verification"
```

Expected: commit succeeds and the worktree is clean.
