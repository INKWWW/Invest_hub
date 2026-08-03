# X 当日判断 Worker Protocol v3 修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本机 Worker 能以严格的 v3 合同读取并提交 X 跨博主当日判断，且将本地 Protocol 拒绝准确报告为 `schema_error`。

**Architecture:** 不改变已上线的 Runtime、控制面、数据库和 Reader。仅在 Worker 的 HTTP 边界将 context 与 completion 的 local validator 从 v2 切换到当前 Runtime 已产生的 v3 结构，并在 Worker 调度层为 `ProtocolError` 增加确定性 failure-class 映射。

**Tech Stack:** Python 3.12、unittest、现有 Worker HTTP Protocol。

## Global Constraints

- 只接受 `prompt_version = "v3-x-cross-blogger-1"` 与 `schema_version = "v3-x-cross-blogger"`。
- 不改变 `v2_x_chunk.md`、`v2_x_window.md`、数据库、控制面、Reader、调度或采集。
- 不创建或回刷 judgement，不改写历史记录，也不调用 Provider 进行验收。
- 保持 endpoint、认证、请求超时与安全 telemetry 规则不变；不记录真实原文、Prompt 或生产 ID。
- 提交前运行 `git diff --check` 和 `bash scripts/v0/redact-check.sh`。

---

### Task 1: 先建立 v3 Worker Protocol 与失败归类的失败测试

**Files:**
- Modify: `workers/v0/tests/test_protocol.py:326-395`
- Modify: `workers/v0/tests/test_worker_recovery.py:325-347`

**Interfaces:**
- Consumes: Worker HTTP context `{run_id, batch_id, attempt, prompt_version, sources, excluded_sources}`。
- Produces: 仅可被 `WorkerProtocol.get_x_daily_judgement_context()` 接受的 `prompt_version="v3-x-cross-blogger-1"`。
- Consumes: v3 completion 的三类观点数组。
- Produces: `WorkerProtocol.complete_x_daily_judgement()` 只在本地检查通过后请求现有 `/complete` endpoint。

- [x] **Step 1: 将现有安全 endpoint 测试的 fixture 改成完整 v3 合同。**

  在 `test_x_daily_judgement_protocol_uses_only_safe_worker_endpoints` 中，将 context 的 `prompt_version` 改为 `v3-x-cross-blogger-1`。将 completion 替换为：

  ```python
  {
      "run_id": "judgement-run-1", "attempt": 1,
      "schema_version": "v3-x-cross-blogger", "provider": "codex_cli",
      "model_reported": None, "prompt_version": "v3-x-cross-blogger-1",
      "security_industry_viewpoints": [],
      "market_structure_viewpoints": [],
      "strategy_mindset_viewpoints": [],
      "uncertainties": ["公开 fixture 的覆盖限制"],
  }
  ```

  保留对 claim、context、complete 与 failure endpoint URL 和 body 的断言。

- [x] **Step 2: 增加不完整和旧版本的本地拒绝测试。**

  在同一测试文件中增加：一条 `prompt_version="v2-x-cross-blogger-1"` context 被 `get_x_daily_judgement_context()` 拒绝的测试；一条 v2 completion 被 `complete_x_daily_judgement()` 拒绝且 transport 只有 enrol 调用的测试；并将现有不安全 telemetry fixture 改为 v3，使它继续证明本地不会把路径状 telemetry 发往网络。

- [x] **Step 3: 增加 ProtocolError 的 judgement failure-class 测试。**

  在 `test_worker_recovery.py` 使用现有 `FakeProtocol`：令 `get_x_daily_judgement_context()` 抛出 `ProtocolError("invalid x daily judgement context")`，调用 `run_x_daily_judgement_once`，并断言唯一的 `judgement_failures` 为：

  ```python
  [{"run_id": "judgement-run-1", "attempt": 1, "failure_class": "schema_error"}]
  ```

- [x] **Step 4: 运行失败测试。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_protocol.py' -v && PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_worker_recovery.py' -v`

  Expected: `test_x_daily_judgement_protocol_uses_only_safe_worker_endpoints` 在读取 v3 context 时失败；ProtocolError failure-class 测试显示当前值为 `persistence_failure`。

### Task 2: 实现最小 v3 Protocol validator 与准确 failure-class 映射

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/protocol.py:390-425`
- Modify: `workers/v0/src/invest_hub_worker/worker.py:299-305`
- Test: `workers/v0/tests/test_protocol.py`
- Test: `workers/v0/tests/test_worker_recovery.py`

**Interfaces:**
- Consumes: Task 1 的 v3 context 与 completion fixtures。
- Produces: context 严格接受 v3 版本；completion 严格接受三类 v3 viewpoints；`ProtocolError` 映射为 `schema_error`。

- [x] **Step 1: 修改 context 版本门禁。**

  在 `_parse_x_daily_judgement_context` 保留当前精确字段、来源、segment、analysis 与 excluded-source 校验，将唯一允许的 `prompt_version` 从 `v2-x-cross-blogger-1` 改为 `v3-x-cross-blogger-1`。

- [x] **Step 2: 修改 completion 版本和字段门禁。**

  在 `_validate_x_daily_judgement_completion` 将 required set 改为：

  ```python
  {
      "run_id", "attempt", "schema_version", "provider", "model_reported", "prompt_version",
      "security_industry_viewpoints", "market_structure_viewpoints",
      "strategy_mindset_viewpoints", "uncertainties",
  }
  ```

  仅接受 `v3-x-cross-blogger` / `v3-x-cross-blogger-1`，验证三类字段均为 list，遍历三类数组。每个 item 必须精确拥有 `statement`、`action_intent`、`action_scope`、`conditions`、`supporting_source_ids`、`dissenting_source_ids`、`analysis_ids`、`evidence_post_ids`、`uncertainties`；复用当前非空字符串数组和安全 telemetry 校验。Runtime 的冻结来源归属、证据闭包、opaque ID 与系统建议校验保持其现有权威位置，不在 Protocol 重复实现。

- [x] **Step 3: 映射 ProtocolError。**

  在 `_report_x_daily_judgement_failure` 先判断 `isinstance(error, ProtocolError)`，此时设置 `failure_class = "schema_error"`；其他异常仍优先使用其 `failure_class` 属性，并保持现有 allow-list 与默认 `persistence_failure` 行为。

- [x] **Step 4: 运行聚焦测试。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_protocol.py' -v && PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_worker_recovery.py' -v`

  Expected: PASS；合法 v3 context/completion 仅请求现有 worker endpoint，v2 与不安全 v3 payload 在 transport 前失败，ProtocolError 回执为 `schema_error`。

### Task 3: 完成回归、发布和只读验收记录

**Files:**
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`
- Modify: `docs/project-status.md`
- Test: `workers/v0/tests/test_x_cross_blogger_judgements.py`
- Test: `workers/v0/tests/test_cli.py`

**Interfaces:**
- Consumes: Task 2 的已通过 v3 Protocol。
- Produces: 记录可复核的本地测试、commit、部署、Worker reload 和只读生产验收，不记录私有输入或历史数据内容。

- [x] **Step 1: 执行 Worker 回归。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v`

  Expected: PASS；特别确认 `test_x_cross_blogger_judgements.py` 的 v3 Runtime 路径与 `test_cli.py` 的 scheduled judgement 调用保持通过。

- [x] **Step 2: 执行提交前完整性检查。**

  Run: `git diff --check && bash scripts/v0/redact-check.sh && git status --short`

  Expected: 差异检查与脱敏检查通过；只包含本 Plan 允许的 Worker、测试和治理记录文件。

- [x] **Step 3: 提交并推送经过验证的代码。**

  Run: `git add workers/v0/src/invest_hub_worker/protocol.py workers/v0/src/invest_hub_worker/worker.py workers/v0/tests/test_protocol.py workers/v0/tests/test_worker_recovery.py docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md docs/project-status.md docs/superpowers/plans/2026-08-04-x-daily-judgement-worker-protocol-v3.md && git commit -m "fix: align X daily judgement worker protocol with v3" && git push origin main`

  Expected: `main` 与 `origin/main` 指向同一已验证提交；不使用强推。

- [x] **Step 4: 更新本机 Worker 并进行只读生产验收。**

  在确认本地 checkout 与 `origin/main` 完全一致后，已重启 `com.investhub.x-worker` 并查询 launchd/进程、近期 run 的 status/failure_class。此次修复不改控制面或 Reader，且没有正常新 run 可投影，因此不以旧 Reader 页面伪造 v3 验收；不手工创建任务、不回刷 2026-08-03、不开启 regeneration、不调用 Provider。实际结果已写入工程记录和项目状态。
