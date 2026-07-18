# Spike-02 Codex CLI Capacity and Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将 Spike-02 harness 的真实 Provider 从 GLM HTTP API 改为受只读沙箱约束的本机 Codex CLI，并继续验证结构化理解的容量、稳定性、可追溯性和质量。

**Architecture:** 保留现有 fixture、chunking、Schema、runner、Mock Provider、evidence 和人工质量评估边界。新增 CodexCLIProvider，每个 chunk 启动一次 codex exec，通过 stdin 传 Prompt，从 --output-last-message 读取最终回答，再交给现有 JSON/Schema 校验；真实 Provider 失败只影响当前 chunk。

**Tech Stack:** Python 3.11+ 标准库；unittest；subprocess；tempfile；JSON/JSONL 本地 evidence；不安装生产依赖，不直接调用 GLM 或其他外部模型 API。

## Global Constraints

- 当前仍处于 Discovery；Spike-02 结果不批准 V0/V1 生产架构。
- Codex CLI 是唯一真实 Provider；Mock Provider 只用于确定性测试；不保留 GLM Provider 或自动 fallback。
- 每次真实调用必须使用 codex exec --sandbox read-only --add-dir <CODEX_HOME> --ephemeral --output-last-message <file> -。
- Prompt 通过 stdin 传递，并明确要求不使用工具、不读取项目文件、不执行项目命令、只返回 JSON。
- SPIKE02_CODEX_BIN 默认为 codex；SPIKE02_CODEX_MODEL 可选，不把登录凭据写入项目。
- Codex 进程默认超时 240 秒；超时后必须终止子进程；已成功 chunk 不重复执行。实测小批次请求约 151 秒完成，120 秒会在最终输出已生成但进程尚未退出时误判为 timeout。
- Provider 必须为每次 Codex 调用创建独立进程组；stdout/stderr 不得依赖可被后代进程继承的 PIPE。超时后先终止整个进程组，再有限等待并回收诊断，不能在无界的 `communicate()` 排空阶段阻塞。
- 真实 fixture、Prompt、完整 Codex 输出和历史数据只能写入本地受保护目录，不进入 Git。
- ProviderResponse.input_tokens 和 output_tokens 在 Codex CLI 未提供时必须为 None，不得估算成精确 token 数。
- 继续沿用初始质量门槛：首次成功率 >=90%、重试后最终成功率 >=99%、JSON 可解析率 >=98%、核心事实有据率 >=95%、严重错误归因 0、媒体臆测 0。
- 每个任务完成后运行对应测试并独立提交，提交信息使用 spike: ... 或 docs: ... 前缀。

---

## File Map

修改以下代码和测试文件：

- spikes/spike_02/model.py：将 Provider 名称改为 mock|codex，补充进程退出码和本地诊断字段。
- spikes/spike_02/providers.py：删除 GLMProvider，新增 CodexCLIProvider，保留 MockProvider。
- spikes/spike_02/runner.py：使用 Codex Provider 名称，并保留失败 chunk 局部重试。
- spikes/spike_02/evidence.py：记录进程退出码和诊断是否存在，完整 stderr 只写入本地 raw evidence。
- spikes/spike_02/cli.py：将 glm 子命令替换为 codex，读取 Codex CLI 配置并传递进程超时。
- spikes/spike_02/chunking.py：传递 author ID 和 message kind，并在 Prompt 中增加“不使用工具、只返回严格 JSON”的确定性约束。
- spikes/spike_02/README.md：改写为 Codex CLI 登录、运行、超时和安全说明。
- spikes/spike_02/tests/test_providers.py：删除 GLM HTTP 测试，增加 fake Codex executable 测试。
- spikes/spike_02/tests/test_cli.py：覆盖 codex 配置和 glm 命令移除。
- spikes/spike_02/tests/test_runner.py：更新 Provider 名称和进程失败恢复断言。
- spikes/spike_02/tests/test_evidence.py：覆盖退出码和诊断字段的安全记录。

真实运行后创建或修改：

- docs/spikes/2026-07-15-spike-02-decision-report.md：记录 Codex CLI 版本、模型配置、脱敏指标、质量结论、限制和下一阶段建议。
- docs/project-status.md：仅在真实 Codex 运行和决策报告完成后更新 Spike-02 当前状态。

不新增生产代码目录，不安装依赖，不创建云端资源。

---

### Task 1: Replace GLM Provider with Codex CLI Provider

**Files:**

- Modify: spikes/spike_02/model.py
- Modify: spikes/spike_02/providers.py
- Modify: spikes/spike_02/tests/test_providers.py

**Interfaces:**

- Consumes: LLMRequest with chunk.prompt_text.
- Produces: CodexCLIProvider.complete(request) -> ProviderResponse.
- Constructor:

~~~python
CodexCLIProvider(
    *,
    binary: str = "codex",
    model: str | None = None,
    timeout_seconds: float = 240.0,
    cwd: str | None = None,
    codex_home: str | None = None,
)
~~~

- ProviderResponse adds process_exit_code: int | None and diagnostic: str | None; Mock responses use None for both.
- Provider statuses are exactly success, timeout, provider_failed, empty_response, invalid_provider_response.

- [ ] **Step 1: Write the failing Provider tests**

Replace GLM tests with tests that create a temporary executable script and assert:

~~~python
def test_codex_success_reads_final_message_and_sends_prompt_on_stdin():
    binary = write_fake_codex(
        """
        import pathlib, sys
        payload = sys.stdin.read()
        assert "prompt" in payload
        output_path = sys.argv[sys.argv.index("--output-last-message") + 1]
        pathlib.Path(output_path).write_text(
            '{"topics":[],"media_unparsed":false,"warnings":[]}'
        )
        """
    )
    response = CodexCLIProvider(binary=binary, cwd=temp_dir).complete(request_for())
    self.assertEqual(response.status, "success")
    self.assertEqual(response.process_exit_code, 0)
    self.assertIn('"topics"', response.content)

def test_codex_includes_read_only_ephemeral_output_flags():
    argv = capture_fake_codex_argv()
    CodexCLIProvider(binary=argv.binary, model="test-model").complete(request_for())
    self.assertEqual(argv.args[:2], ["exec", "--sandbox"])
    self.assertIn("read-only", argv.args)
    self.assertIn("--ephemeral", argv.args)
    self.assertIn("--output-last-message", argv.args)
    self.assertIn("--model", argv.args)

def test_codex_maps_nonzero_exit_to_provider_failed_without_business_output():
    response = CodexCLIProvider(binary=write_fake_exit(7)).complete(request_for())
    self.assertEqual(response.status, "provider_failed")
    self.assertEqual(response.process_exit_code, 7)
    self.assertIsNone(response.content)

def test_codex_maps_missing_final_message_to_empty_response():
    response = CodexCLIProvider(binary=write_fake_no_output()).complete(request_for())
    self.assertEqual(response.status, "empty_response")

def test_codex_timeout_terminates_process():
    response = CodexCLIProvider(
        binary=write_fake_sleep(2), timeout_seconds=0.05
    ).complete(request_for())
    self.assertEqual(response.status, "timeout")

def test_codex_does_not_expose_command_diagnostics_as_content():
    response = CodexCLIProvider(binary=write_fake_exit_with_stderr()).complete(request_for())
    self.assertIsNone(response.content)
    self.assertNotIn("secret-prompt", response.content or "")
~~~

Use a fake executable rather than a real Codex login so the tests are deterministic and offline.

- [ ] **Step 2: Run the Provider tests and verify failure**

Run:

~~~bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_providers -v
~~~

Expected: FAIL because GLMProvider still exists and CodexCLIProvider does not yet exist.

- [ ] **Step 3: Implement the process adapter**

Implement CodexCLIProvider.complete with this exact command shape:

~~~python
command = [
    self.binary,
    "exec",
    "--sandbox",
    "read-only",
    "--add-dir",
    self.codex_home,
    "--ephemeral",
    "--output-last-message",
    str(output_path),
]
if self.model:
    command.extend(["--model", self.model])
command.append("-")
~~~

Use subprocess.Popen(command, cwd=self.cwd, stdin=PIPE, stdout=PIPE, stderr=PIPE, text=True); pass request.chunk.prompt_text to communicate(input=..., timeout=...). On timeout call kill(), drain the process, and return timeout. On non-zero exit return provider_failed. On exit code 0 read the output file, classify empty output, and return its text without parsing JSON in the Provider.

Record process_exit_code; keep stderr in ProviderResponse only for local raw evidence and never use it as business content. Set token fields and finish reason to None.

- [ ] **Step 4: Run the Provider tests and verify pass**

Run:

~~~bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_providers -v
~~~

Expected: all Provider tests PASS, with no network call and no Codex login required.

- [ ] **Step 5: Commit**

~~~bash
git add spikes/spike_02/model.py spikes/spike_02/providers.py spikes/spike_02/tests/test_providers.py
git commit -m "spike: replace GLM provider with Codex CLI"
~~~

### Task 2: Align Runner and Evidence with Process Outcomes

**Files:**

- Modify: spikes/spike_02/runner.py
- Modify: spikes/spike_02/evidence.py
- Modify: spikes/spike_02/tests/test_runner.py
- Modify: spikes/spike_02/tests/test_evidence.py

**Interfaces:**

- Consumes: ProviderResponse from Task 1.
- Produces: RunReport.provider == "codex" for CodexCLIProvider, stable retry behavior for timeout, provider_failed, empty_response, invalid_json, and schema_error.

- [ ] **Step 1: Write failing runner and evidence tests**

Add tests that assert:

~~~python
def test_runner_retries_codex_timeout_then_preserves_success():
    provider = MockProvider({"case-0000": [
        MockOutcome.failure("timeout"),
        MockOutcome.success(VALID_JSON),
    ]})
    report = run_case(case, provider, RunConfig(max_primary_messages=3), evidence, sleep=noop)
    self.assertEqual(report.final_success_rate, 1.0)
    self.assertEqual(report.retry_count, 1)

def test_evidence_records_exit_code_without_writing_it_to_business_output():
    response = ProviderResponse(
        status="provider_failed", content=None, latency_ms=10,
        input_tokens=None, output_tokens=None, finish_reason=None,
        error_code="provider_failed", process_exit_code=7,
        diagnostic="stderr text",
    )
    evidence.persist_request(request, response)
    request_record = json.loads(requests_file.read_text().splitlines()[0])
    self.assertEqual(request_record["process_exit_code"], 7)
    self.assertNotIn("stderr text", request_record)
~~~

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

~~~bash
PYTHONPATH=spikes python3 -m unittest \
  spikes.spike_02.tests.test_runner \
  spikes.spike_02.tests.test_evidence -v
~~~

Expected: FAIL because the model and evidence structures do not yet contain Codex process fields.

- [ ] **Step 3: Implement the smallest runner/evidence changes**

Update ProviderName detection to:

~~~python
provider_name: ProviderName = (
    "codex" if isinstance(provider, CodexCLIProvider) else "mock"
)
~~~

Add process_exit_code and stderr_present to requests.jsonl; include full diagnostic text only in the local raw_responses/ payload. Add provider_failed, empty_response, and invalid_provider_response to retryable statuses where the failure is recoverable; preserve completed chunk results and current bounded retry delays. Do not change Schema parsing or quality evaluation behavior.

- [ ] **Step 4: Run the focused tests and the complete deterministic suite**

Run:

~~~bash
PYTHONPATH=spikes python3 -m unittest \
  spikes.spike_02.tests.test_runner \
  spikes.spike_02.tests.test_evidence -v
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
~~~

Expected: focused tests PASS and the full deterministic suite remains green.

- [ ] **Step 5: Commit**

~~~bash
git add spikes/spike_02/runner.py spikes/spike_02/evidence.py spikes/spike_02/tests/test_runner.py spikes/spike_02/tests/test_evidence.py
git commit -m "spike: record Codex process outcomes"
~~~

### Task 3: Replace the CLI Surface and Local Run Documentation

**Files:**

- Modify: spikes/spike_02/cli.py
- Modify: spikes/spike_02/chunking.py
- Modify: spikes/spike_02/tests/test_cli.py
- Modify: spikes/spike_02/README.md

**Interfaces:**

- Consumes: SPIKE02_CODEX_BIN, optional SPIKE02_CODEX_MODEL, and --codex-timeout-seconds.
- Produces: mock and codex subcommands; no glm subcommand or GLM environment variables.

- [ ] **Step 1: Write failing CLI and Prompt tests**

Add tests that assert:

~~~python
def test_glm_command_is_removed():
    self.assertEqual(main(["glm", "--evidence-dir", temp_dir]), 2)

def test_codex_cli_uses_binary_and_optional_model_environment():
    os.environ["SPIKE02_CODEX_BIN"] = fake_binary
    os.environ["SPIKE02_CODEX_MODEL"] = "test-model"
    code = main(["codex", "--fixture", FIXTURE_PATH,
                 "--evidence-dir", temp_dir,
                 "--max-attempts", "1"])
    self.assertEqual(code, 0)

def test_chunk_prompt_forbids_tools_and_requires_json():
    chunk = build_chunks(case, max_primary_messages=3)[0]
    self.assertIn("Do not use tools", chunk.prompt_text)
    self.assertIn("JSON", chunk.prompt_text)
    self.assertIn("source_message_ids", chunk.prompt_text)
    self.assertIn("author_id", chunk.prompt_text)
    self.assertIn("unparsed_media", chunk.prompt_text)
~~~

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

~~~bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_02.tests.test_cli -v
~~~

Expected: FAIL because the CLI still exposes glm and does not construct a Codex Provider.

- [ ] **Step 3: Implement the CLI migration**

Change the parser loop from ("mock", "glm") to ("mock", "codex"). Add:

~~~python
 subparser.add_argument("--codex-timeout-seconds", type=float, default=240.0)
~~~

For codex, construct:

~~~python
provider = CodexCLIProvider(
    binary=os.environ.get("SPIKE02_CODEX_BIN", "codex"),
    model=os.environ.get("SPIKE02_CODEX_MODEL") or None,
    timeout_seconds=args.codex_timeout_seconds,
    cwd=os.getcwd(),
)
~~~

Do not validate a Codex login during argument parsing; a missing binary or failed login must become a Provider failure in the run evidence. Add the exact top-level fields topics, media_unparsed, and warnings; require each topic to include title, summary, source_message_ids, author_scope, author_id, tickers, operation_tendency, and uncertainty. Include author ID and message kind in every input line, and require media_unparsed=true whenever kind=unparsed_media appears.

- [ ] **Step 4: Rewrite README and run tests**

Document:

~~~bash
export SPIKE02_CODEX_BIN='codex'
export SPIKE02_CODEX_MODEL='optional-model-name'

PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-small \
  --chunk-size 3 \
  --codex-timeout-seconds 240
~~~

State that Codex must already be logged in locally, the process is non-interactive, the sandbox is read-only, evidence is local-only, mock is offline, and glm is no longer supported.

Run:

~~~bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
git diff --check
~~~

Expected: all deterministic tests PASS and no GLM environment names remain under spikes/spike_02/.

- [ ] **Step 5: Commit**

~~~bash
git add spikes/spike_02/cli.py spikes/spike_02/chunking.py spikes/spike_02/tests/test_cli.py spikes/spike_02/README.md
git commit -m "docs: expose Codex CLI Spike-02 runner"
~~~

### Task 4: Run Codex Evidence and Update the Decision Report

**Files:**

- Modify: docs/spikes/2026-07-15-spike-02-decision-report.md
- Modify: docs/project-status.md only after the evidence is complete

**Interfaces:**

- Consumes: Task 3 CLI, a local Codex login, public fixture, synthetic scale fixtures, and a local review sheet.
- Produces: redacted Codex evidence, metrics, manual quality review, and one of passed, conditional, failed, or unverified.

- [x] **Step 1: Verify the local Codex CLI without project mutation**

Run:

~~~bash
codex --version
codex exec --help
git status --short
~~~

Expected: the CLI is available, exec documents --sandbox, --ephemeral, and --output-last-message, and the worktree has no unrelated changes.

- [x] **Step 2: Run the annotated small fixture**

Use a new evidence directory. Because the 120-second window produced false timeouts after valid JSON generation, the verified run used a 240-second timeout and a separate evidence directory:

~~~bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-single-long \
  --chunk-size 3 \
  --max-attempts 3 \
  --codex-timeout-seconds 240

Observed result: 1/1 final success, JSON/Schema rate 100%, P50/P95 150,956 ms. The 120-second run is retained separately as timeout evidence.
~~~

Verify the terminal summary, metrics.json, requests.jsonl, results.jsonl, and local raw_responses/. Confirm that the worktree is unchanged and no secret appears in tracked files.

- [ ] **Step 3: Run the two capacity scales**

Run sequentially with separate evidence directories:

~~~bash
PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 500 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-500-c25 \
  --chunk-size 25 \
  --max-attempts 3 \
  --codex-timeout-seconds 240

PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c25 \
  --chunk-size 25 \
  --max-attempts 3 \
  --codex-timeout-seconds 240

PYTHONPATH=spikes python3 -m spike_02.cli codex \
  --synthetic-count 1000 \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-1000-c100 \
  --chunk-size 100 \
  --max-attempts 3 \
  --codex-timeout-seconds 240
~~~

Treat synthetic fixtures as capacity evidence only; do not use them for quality conclusions. This step remains outstanding after the observed approximately 151-second latency per small real request; the decision report therefore remains `unverified`.

- [x] **Step 4: Complete the manual quality review**

Create a local JSONL review file with case_id, claim_id, covered, grounded, correct_attribution, media_hallucination, and note. Run:

~~~bash
PYTHONPATH=spikes python3 -m spike_02.cli evaluate \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/codex-single-long \
  --review-file /private/tmp/invest-hub-spike-02-evidence/codex-review.jsonl
~~~

Every quality conclusion must cite fixture message IDs; severe attribution errors and media hallucinations cannot be averaged away.

- [x] **Step 5: Update the decision report without secrets**

Replace GLM-specific wording with Codex CLI wording. Record CLI version, configured model if known, input scale, chunk size, process count, retry count, success rates, JSON/Schema rates, P50/P95, total time, failure categories, quality review, limitations, and the final conclusion. Leave token fields as unavailable when the CLI did not provide them.

Keep the report unverified if login, model configuration, or any required scale/quality evidence is missing. Do not update project status to completed until all required evidence and the report are present.

- [ ] **Step 6: Run final verification and commit**

Run:

~~~bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
git diff --check
git status --short
~~~

Expected: the full deterministic suite passes, only intended documentation/evidence references are changed, and no API key, private fixture, or full response is tracked.

~~~bash
git add docs/spikes/2026-07-15-spike-02-decision-report.md docs/project-status.md
git commit -m "docs: record Codex CLI Spike-02 result"
~~~
