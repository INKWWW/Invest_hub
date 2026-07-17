# Spike-02 Bounded Concurrency Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在保持每个 chunk 独立 Codex CLI 调用和现有安全边界的前提下，为 Spike-02 harness 增加最多 2 个并发 worker，并验证 500 条、chunk-size 100 的整批墙钟时间与失败恢复。

**Architecture:** 使用标准库 ThreadPoolExecutor 调度阻塞式 Codex CLI Provider，每个 worker 同时只处理一个 chunk，失败 chunk 在 worker 内按现有策略重试。EvidenceStore 使用 threading.Lock 保护 JSONL 追加，runner 汇总 worker 返回的统计并按 chunk index 稳定排序；默认 max_concurrency=1 保持串行兼容。Codex 会话复用、app-server、更大 chunk、Provider 更换和生产调度均不在本计划内。

**Tech Stack:** Python 3.11+ 标准库；concurrent.futures.ThreadPoolExecutor；threading.Lock；unittest；现有 subprocess CodexCLIProvider；本地 JSON/JSONL evidence。

## Global Constraints

- 当前仍处于 Discovery；并发 runner 只用于 Spike-02 验证，不授权 V0/V1 生产实现。
- 默认并发数为 1；真实并发验证使用 max-concurrency=2，硬上限不得超过 2。
- 每个 chunk 仍使用独立的非交互 codex exec 进程；继续使用 --sandbox read-only、--add-dir <CODEX_HOME>、--ephemeral 和 --output-last-message。
- 不使用 Codex 会话复用、app-server、exec resume、更大 chunk、Prompt 压缩、OpenRouter、其他 Provider 或自动 fallback。
- 只重试失败 chunk；成功 chunk 不重复调用；单个 timeout 只能终止对应进程组。
- Evidence、Prompt、完整 Codex 输出和诊断只写入本地受保护目录，不进入 Git。
- 并发模式必须记录配置并发上限、实际最大活动请求数、每个请求 latency、批次墙钟耗时和失败分类。
- ProviderResponse.input_tokens 和 output_tokens 在 Codex CLI 未提供时保持 None，不得估算。
- 每个任务完成后运行对应测试并独立提交，提交信息使用 spike: 或 docs: 前缀。

## File Map

- Modify: spikes/spike_02/model.py — 为 RunReport 增加并发和批次耗时遥测字段。
- Modify: spikes/spike_02/runner.py — 增加 RunConfig.max_concurrency、受控 worker 调度、局部重试汇总和活动请求跟踪。
- Modify: spikes/spike_02/providers.py — 让 MockProvider 的调用计数在并发测试中安全。
- Modify: spikes/spike_02/evidence.py — 为并发 JSONL/JSON evidence 写入增加进程内锁。
- Modify: spikes/spike_02/cli.py — 暴露 --max-concurrency 并传入 RunConfig。
- Modify: spikes/spike_02/tests/test_runner.py — 覆盖并发上限、重试隔离、结果排序和串行兼容。
- Modify: spikes/spike_02/tests/test_evidence.py — 覆盖并发追加不会破坏 JSONL。
- Modify: spikes/spike_02/tests/test_cli.py — 覆盖并发参数的默认值和传递。
- Modify: spikes/spike_02/tests/test_evaluation.py — 为新增 RunReport 字段补齐测试 fixture。
- Modify: spikes/spike_02/README.md — 记录并发参数、风险和验证命令。
- Modify after real evidence: docs/spikes/2026-07-15-spike-02-decision-report.md、docs/project-status.md、docs/engineering-journal/2026-07-15-spike-02.md。

---

### Task 1: Add concurrency configuration and report telemetry

Files:
- Modify: spikes/spike_02/model.py:118-133
- Modify: spikes/spike_02/runner.py:38-45
- Modify: spikes/spike_02/cli.py:34-53,68-83
- Test: spikes/spike_02/tests/test_cli.py
- Test: spikes/spike_02/tests/test_evaluation.py

Interfaces:
- RunConfig.max_concurrency: int = 1
- RunReport.batch_elapsed_ms: int
- RunReport.max_concurrency: int
- RunReport.max_active_requests: int
- CLI option: --max-concurrency, integer, default 1

- [ ] Step 1: Add failing CLI and report-shape tests

Add a CLI test that runs the existing fake Codex command with --max-concurrency 2, reads metrics.json, and asserts the report contains the three new telemetry keys. Add a test that passes --max-concurrency 0 and asserts main(...) returns 2 after runner validation is wired.

Update the RunReport fixture in test_evaluation.py to name the new fields; use initial values 0, 1, and 0 so quality assertions remain focused on evaluation.

- [ ] Step 2: Run focused tests and verify failure

Run:

    PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_cli spikes.spike_02.tests.test_evaluation -v

Expected: FAIL because the CLI does not accept --max-concurrency and RunReport has no new fields.

- [ ] Step 3: Add configuration and telemetry fields

Extend RunReport at the end of the dataclass:

    batch_elapsed_ms: int
    max_concurrency: int
    max_active_requests: int

Extend RunConfig with:

    max_concurrency: int = 1

Add the CLI option and pass it through:

    subparser.add_argument("--max-concurrency", type=int, default=1)

    config = RunConfig(
        max_primary_messages=args.chunk_size,
        max_attempts=args.max_attempts,
        prompt_version=args.prompt_version,
        max_concurrency=args.max_concurrency,
    )

Do not implement scheduling in this task. The runner will populate telemetry in Task 3; use temporary values only in test fixtures, not in production reports.

- [ ] Step 4: Run focused tests

Run the same focused command. Expected: report-shape tests pass; invalid-value and runtime telemetry assertions remain pending until Task 3 adds validation and metrics population.

- [ ] Step 5: Commit

    git add spikes/spike_02/model.py spikes/spike_02/runner.py spikes/spike_02/cli.py spikes/spike_02/tests/test_cli.py spikes/spike_02/tests/test_evaluation.py
    git commit -m "spike: add concurrency configuration telemetry"

### Task 2: Make local evidence writes concurrency-safe

Files:
- Modify: spikes/spike_02/evidence.py:16-71
- Test: spikes/spike_02/tests/test_evidence.py

Interfaces:
- EvidenceStore remains the public evidence interface.
- persist_request, persist_result, persist_raw_response, and persist_metrics remain callable from worker threads.
- One threading.Lock per EvidenceStore instance serializes writes.

- [ ] Step 1: Write a concurrent JSONL integrity test

Create one EvidenceStore and temporarily wrap its _append_jsonl method with a test helper that increments an active counter, sleeps briefly, calls the original method, and decrements the counter. Call persist_request for 40 distinct LLMRequest/ProviderResponse pairs from a ThreadPoolExecutor(max_workers=4), then assert the helper observed max_active == 1. After all futures complete, parse every line of requests.jsonl with json.loads and assert there are 40 valid rows with 40 distinct chunk IDs. Also assert no row contains prompt_text or diagnostic text.

- [ ] Step 2: Run the evidence tests and verify failure

Run:

    PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_evidence -v

Expected: FAIL because the current EvidenceStore has no per-instance lock and the wrapped write helper observes overlapping calls.

- [ ] Step 3: Add the per-store lock

Initialize one lock in EvidenceStore.__init__:

    self._lock = threading.Lock()

Wrap each public persistence operation that writes a file:

    with self._lock:
        self._append_jsonl(target, payload)

Keep raw responses as separate files. Do not put a lock around the Codex subprocess; only evidence file mutation is serialized.

- [ ] Step 4: Run evidence and full deterministic tests

Run:

    PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_evidence -v
    PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v

Expected: focused tests and all existing tests pass.

- [ ] Step 5: Commit

    git add spikes/spike_02/evidence.py spikes/spike_02/tests/test_evidence.py
    git commit -m "spike: serialize concurrent evidence writes"

### Task 3: Refactor runner to bounded worker scheduling

Files:
- Modify: spikes/spike_02/runner.py:47-208
- Modify: spikes/spike_02/providers.py:39-63
- Test: spikes/spike_02/tests/test_runner.py

Interfaces:

Introduce this internal worker result:

    @dataclass(frozen=True)
    class _ChunkWorkResult:
        chunk_index: int
        chunk_id: str
        result: ChunkResult | None
        follow_up_chunks: tuple[Chunk, ...]
        first_response_success: bool
        request_count: int
        retry_count: int
        json_attempts: int
        json_successes: int
        latencies: tuple[int, ...]

Introduce an internal activity tracker:

    class _ActiveRequestTracker:
        def enter(self) -> None: """Increment active count and update max_seen."""
        def exit(self) -> None: """Decrement active count."""
        @property
        def max_seen(self) -> int: """Return the highest observed active count."""

The tracker is lock-protected and wraps only provider.complete(request), so max_seen measures active Codex requests rather than finished futures.

- [ ] Step 1: Write failing runner tests

Add a test-only provider that sleeps briefly inside complete, tracks active calls under a lock, and returns VALID_JSON. Run a public fixture with four chunks and RunConfig(max_primary_messages=3, max_concurrency=2). Assert provider.max_active is at least 2, report.max_active_requests is at most 2, report.max_concurrency is 2, request_count is 4, and final_success_rate is 1.0.

Add a second test with one chunk scripted as timeout then success and another chunk successful. Run with max_concurrency=2 and assert the failed chunk has two calls while the completed chunk has one call. Assert report.results has stable chunk ordering independent of completion order.

- [ ] Step 2: Run runner tests and verify failure

Run:

    PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_runner -v

Expected: FAIL because the current runner is serial and does not populate concurrency telemetry.

- [ ] Step 3: Extract one-chunk attempt processing

Move the existing inner attempt/parse/validation logic into:

    def _process_chunk(
        case: FixtureCase,
        provider: LLMProvider,
        config: RunConfig,
        evidence: EvidenceStore,
        run_id: str,
        chunk: Chunk,
        is_initial_chunk: bool,
        active_requests: _ActiveRequestTracker,
        sleep: Callable[[float], None],
    ) -> _ChunkWorkResult:
        """Process one chunk, including local retries and schema validation."""

Preserve existing behavior: construct LLMRequest, call provider.complete inside active_requests.enter()/exit(), persist request/raw response, validate JSON/Schema, retry retryable failures, and return split follow-up chunks for a truncated response. Return counters instead of mutating shared request_count, retry_count, latencies, or result lists.

- [ ] Step 4: Add bounded scheduling

Use ThreadPoolExecutor(max_workers=config.max_concurrency) and submit at most max_concurrency chunks at a time. When a future completes, collect counters/results, enqueue follow_up_chunks at the front of pending work, and submit the next pending chunk. Use wait(pending_futures, return_when=FIRST_COMPLETED) so a fast worker can receive another chunk without waiting for the slowest worker.

Validate before scheduling:

    if config.max_concurrency < 1:
        raise ValueError("max_concurrency must be positive")

Start batch_started = time.monotonic_ns() before scheduling and populate:

    batch_elapsed_ms=_elapsed_ms(batch_started)
    max_concurrency=config.max_concurrency
    max_active_requests=active_requests.max_seen

Aggregate counters after futures complete. Store results as (chunk_index, chunk_id, result) tuples and sort by (chunk_index, chunk_id) before constructing RunReport; never use future completion order as report order.

- [ ] Step 5: Make MockProvider call accounting thread-safe

Add a threading.Lock around _calls lookup/update in MockProvider.complete. Keep scripted outcome semantics unchanged.

- [ ] Step 6: Run runner and full deterministic tests

Run:

    PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_runner -v
    PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v

Expected: bounded concurrency, retry isolation, truncated split handling, serial compatibility, evidence safety, and all deterministic tests pass.

- [ ] Step 7: Commit

    git add spikes/spike_02/runner.py spikes/spike_02/providers.py spikes/spike_02/tests/test_runner.py
    git commit -m "spike: add bounded Codex chunk concurrency"

### Task 4: Expose and document the concurrency mode

Files:
- Modify: spikes/spike_02/README.md
- Modify: spikes/spike_02/tests/test_cli.py

Interfaces:
- CLI usage: --max-concurrency 2
- Default behavior: omitted option means serial execution with max_concurrency=1.

- [ ] Step 1: Add CLI regression coverage

Extend the fake Codex CLI test to pass --max-concurrency 2 and assert metrics contains max_concurrency == 2. Add a second invocation without the flag and assert max_concurrency == 1.

- [ ] Step 2: Update README

Add this concurrent smoke command:

    PYTHONPATH=spikes python3 -m spike_02.cli codex --fixture spikes/spike_02/fixtures/public_small.json --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-small-c2 --chunk-size 3 --max-attempts 3 --max-concurrency 2 --codex-timeout-seconds 240

Document that concurrency is capped at 2 for this Spike, each chunk launches an independent Codex CLI process, evidence is local-only, and a shared CODEX_HOME state conflict is a failed validation result rather than something to ignore.

- [ ] Step 3: Run CLI and full deterministic verification

Run:

    PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_cli -v
    PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
    git diff --check

Expected: all tests pass and the README contains no unsupported session-reuse or production-concurrency claim.

- [ ] Step 4: Commit

    git add spikes/spike_02/README.md spikes/spike_02/tests/test_cli.py
    git commit -m "docs: document Spike-02 bounded concurrency"

### Task 5: Run evidence, compare wall-clock time, and update Spike records

Files:
- Create locally only: /private/tmp/invest-hub-spike-02-evidence/codex-small-c2-20260718
- Create locally only: /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c2-20260718
- Modify after real evidence: docs/spikes/2026-07-15-spike-02-decision-report.md
- Modify after real evidence: docs/project-status.md
- Modify after real evidence: docs/engineering-journal/2026-07-15-spike-02.md

Interfaces:
- Consumes the approved concurrency runner with --max-concurrency 2.
- Produces local evidence and a comparison against the serial codex-500-c100-20260718 baseline.
- Does not change the existing Spike-02 conclusion to passed solely because synthetic capacity improves.

- [ ] Step 1: Verify worktree and CLI before real calls

Run:

    git status --short --branch
    codex --version
    codex exec --help

Expected: clean worktree, available CLI, and help documents --sandbox, --ephemeral, and --output-last-message.

- [ ] Step 2: Run public-fixture concurrency smoke test

Run:

    PYTHONPATH=spikes python3 -m spike_02.cli codex --fixture spikes/spike_02/fixtures/public_small.json --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-small-c2-20260718 --chunk-size 3 --max-attempts 3 --max-concurrency 2 --codex-timeout-seconds 240

Verify metrics.json, requests.jsonl, results.jsonl, and raw_responses/. Stop before the scale run if the smoke test reports provider failures, state-directory conflicts, malformed evidence, max_active_requests > 2, or a worktree change.

- [ ] Step 3: Run 500-message concurrent capacity test

Run only after the smoke test passes:

    PYTHONPATH=spikes python3 -m spike_02.cli codex --synthetic-count 500 --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-c2-20260718 --chunk-size 100 --max-attempts 3 --max-concurrency 2 --codex-timeout-seconds 240

Expected shape: 5 initial chunks, configured concurrency 2, observed concurrency no greater than 2, and a batch wall-clock time materially below the serial baseline of about 645827 ms. Treat any timeout, provider failure, evidence mismatch, or state conflict as a failed concurrency validation even if other chunks succeed.

- [ ] Step 4: Compare and classify result

Compare concurrent metrics with /private/tmp/invest-hub-spike-02-evidence/codex-500-c100-20260718/metrics.json. Report actual batch elapsed time, speedup ratio, P50/P95, request/retry counts, max_active_requests, and failure categories. Synthetic output must not be used to claim business-quality accuracy.

- [ ] Step 5: Update durable records

If evidence is complete, add a dated entry to the engineering journal and update the decision report and project status with actual concurrent results. Keep the overall Spike-02 conclusion unverified unless all previously required quality and capacity gates are separately satisfied. Do not add Prompt text, full responses, credentials, or private fixture data to Git.

- [ ] Step 6: Run final verification

Run:

    PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
    git diff --check
    git status --short --branch

Expected: full deterministic suite passes, only intended docs are modified, and the worktree contains no evidence or secrets.

- [ ] Step 7: Commit recorded result

    git add docs/spikes/2026-07-15-spike-02-decision-report.md docs/project-status.md docs/engineering-journal/2026-07-15-spike-02.md
    git commit -m "docs: record Spike-02 bounded concurrency result"
