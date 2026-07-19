# V0 真实运行有界批次恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将真实 Discord 验收从无界历史翻页改为一次只验证一个新鲜页面的有界批次，并在管理员显式重试后完成真实的采集、结构化、持久化与 checkpoint 闭环。

**Architecture:** V0 只需要证明一个已授权来源的最小闭环，而不是完成历史回填。`DiscordActiveAdapter` 每次任务只接受第一个通过新鲜度校验的页面；该页面的最小消息 ID 仍作为候选安全 checkpoint，只有后续持久化和结果回执成功后才由控制面提交。缺失、陈旧、错误 cursor、超时和 Provider 失败继续进入失败路径，不能被空批次掩盖。

**Tech Stack:** Python 3.12 标准库 Worker、OpenCLI Browser Bridge、Codex CLI、Supabase/Vercel Preview、Python `unittest`、Shell 验收脚本。

## Global Constraints

- 真实 Discord URL、Profile、Cookie、邀请码、Vercel 绕过密钥、Prompt、正文、完整模型输出和本地 evidence 不得进入 Git、Vercel、数据库调试面或本计划。
- V0 真实验证只使用用户已授权、正常可见的 Discord 页面；不使用普通用户 Token 或直接 Discord API。
- 单页 Browser Bridge 操作仍为 90 秒硬截止；missing、stale、错误 cursor、登录失效和 timeout 仍必须失败。
- V0 真实验收只证明一页有界批次，不宣称已完成历史回填或持续增量产品能力；后两者留待 V1 Spec 单独定义。
- checkpoint 只能在 raw、Canonical、结构化输出和 evidence 关系持久化成功且控制面确认结果后推进。
- 每项代码改动先写失败测试，再实现最小修复；每项任务结束均执行对应测试。

---

## 文件结构

| 文件 | 责任 |
| --- | --- |
| `workers/v0/src/invest_hub_worker/connectors/discord_active_adapter.py` | 限定一次 V0 Worker 任务只消费一个通过新鲜度校验的 Discord 页面。 |
| `workers/v0/tests/test_discord_active_adapter.py` | 证明有界批次不会请求第二页，同时保持已有的新鲜度/错误分类行为。 |
| `docs/spikes/2026-07-18-v0-decision-report.md` | 真实验收成功后记录“有界单页”证据与结论，不写真实内容。 |
| `docs/engineering-journal/2026-07-18-v0.md` | 记录 timeout 根因、修复和脱敏验收统计。 |
| `docs/project-status.md` | 仅在真实闭环通过后，将 V0 从有条件通过更新为通过；否则保留有条件通过和失败原因。 |

### Task 1: 限定 V0 任务为单个新鲜页面

**Files:**

- Modify: `workers/v0/src/invest_hub_worker/connectors/discord_active_adapter.py:38-76`
- Modify: `workers/v0/tests/test_discord_active_adapter.py`

**Interfaces:**

- Consumes: `DiscordActiveAdapter.collect(source, checkpoint) -> Iterable[RawPage]`。
- Produces: 至多一个 `RawPage`；若该页 `cursor_after` 非空，仍由运行时作为候选 checkpoint，Adapter 不再请求下一页。

- [x] **Step 1: 写入失败测试，锁定有界行为**

在 `test_discord_active_adapter.py` 新增两条新鲜网络响应的 `FakeInvoker`。调用 `list(DiscordActiveAdapter(invoker).collect(...))` 后断言只得到第一页、`len(invoker.calls) == 1`，并断言第一页保留 `cursor_after`。

```python
def test_real_run_batch_stops_after_one_fresh_page(self) -> None:
    invoker = FakeInvoker(first_fresh_response, second_fresh_response)
    pages = list(DiscordActiveAdapter(invoker).collect(source_config(), checkpoint=None))
    self.assertEqual(len(pages), 1)
    self.assertEqual(pages[0].cursor_after, "cursor-1")
    self.assertEqual(len(invoker.calls), 1)
```

- [x] **Step 2: 运行失败测试，确认当前实现会继续请求第二页**

Run:

```bash
PYTHONPATH=workers/v0/src python3.12 -m unittest \
  workers/v0/tests/test_discord_active_adapter.py
```

Expected: 新增测试失败，且失败原因是当前 `collect` 请求了第二页。

- [x] **Step 3: 实现最小单页边界**

在 `DiscordActiveAdapter.collect` 保存第一页、构造 `RawPage` 并 `yield` 后立即 `return`。不得修改 `_fetch`、`_match`、cache-buster、90 秒 deadline 或错误分类；它们继续保障第一页面是新鲜且正确匹配的网络响应。

```python
yield RawPage(...)
return
```

- [x] **Step 4: 执行 Adapter 和运行时回归**

Run:

```bash
PYTHONPATH=workers/v0/src:spikes python3.12 -m unittest \
  workers/v0/tests/test_discord_active_adapter.py \
  workers/v0/tests/test_authorized_runtime.py \
  workers/v0/tests/test_checkpoint_order.py
```

Expected: 全部通过；既有 missing/stale/wrong-cursor/timeout 测试仍通过。

- [x] **Step 5: 提交单页边界修复**

```bash
git add workers/v0/src/invest_hub_worker/connectors/discord_active_adapter.py \
  workers/v0/tests/test_discord_active_adapter.py
git commit -m "fix(v0): bound real discord run to one fresh page"
```

### Task 2: 重试真实任务并完成闭环验收

**Files:**

- Modify after success: `docs/spikes/2026-07-18-v0-decision-report.md`
- Modify after success: `docs/engineering-journal/2026-07-18-v0.md`
- Modify after success: `docs/project-status.md`

**Interfaces:**

- Consumes: 管理员将现有 `retryable_failed` 任务点击为 queued；本地 owner-only Worker 配置、凭据、Prompt、OpenCLI 合同和 Vercel 绕过密钥。
- Produces: 一次真实任务 `succeeded`、至少一页 raw/Canonical、至少一条结构化运行、远程 evidence 关系和非空安全 checkpoint；所有真实内容仍只存在于本地 protected evidence。

- [ ] **Step 1: 执行完整非真实回归和泄露扫描**

Run:

```bash
PYTHONPATH=spikes:workers/v0/src:. python3.12 -m unittest discover -s spikes/spike_01/tests -p 'test_*.py'
PYTHONPATH=workers/v0/src:. python3.12 -m unittest discover -s workers/v0/tests -p 'test_*.py'
PYTHONPATH=workers/v0/src:. python3.12 -m unittest discover -s tests/e2e/v0 -p 'test_*.py'
bash scripts/v0/redact-check.sh
```

Expected: 所有测试和泄露扫描通过；不得把私密目录作为扫描或提交目标。

- [ ] **Step 2: 管理员点击一次“重试任务”**

在受保护 Preview 的任务详情页确认状态为 `retryable_failed` 后，只点击一次“重试任务”。确认列表状态变为 `queued`；不得新建第二个来源或第二个任务。

- [ ] **Step 3: 启动单次真实 Worker，并将完整输出仅写入 owner-only 私密日志**

Run（所有路径为仓库外私密文件，不得贴入 Git）：

```bash
V0_REAL_DISCORD_ACK=authorized \
V0_VERCEL_PROTECTION_BYPASS="$(< /private/vercel-bypass.txt)" \
V0_PYTHON_BIN=python3.11 \
bash scripts/v0/run-e2e.sh --mode real-discord --provider codex \
  --chunk-size 100 --max-concurrency 5 --timeout-seconds 240 --max-attempts 3 \
  --worker-config /private/worker.toml \
  --credential /private/worker-credential.json \
  --opencli-contract /private/opencli-browser-bridge-contract.json \
  --prompt-path /private/prompt.md \
  --evidence-dir /private/evidence
```

Expected: Worker 输出脱敏 `succeeded`；日志、raw、Prompt 和模型完整输出只保留在 owner-only 本地目录。

- [ ] **Step 4: 在管理员详情页验证远程闭环**

确认：任务为 `succeeded`；Attempt 2 为成功；Raw、Canonical、Structured run、evidence refs 与 checkpoint 均存在；Provider 为 `codex_cli`；普通用户仍无管理员访问权限。只记录计数、状态和逻辑证据引用，不记录正文、URL、作者或秘密。

- [ ] **Step 5: 记录结论并提交文档**

仅当 Step 4 全部满足时，更新决策报告、工程日志和项目状态为“V0 通过（有界单页真实验证）”。若任一项失败，记录失败类与安全 checkpoint，保留“有条件通过”，不得写为通过。

```bash
git add docs/spikes/2026-07-18-v0-decision-report.md \
  docs/engineering-journal/2026-07-18-v0.md \
  docs/project-status.md
git commit -m "docs(v0): record bounded real discord validation"
```

## 自检

- Spec 覆盖：任务 1 保证实际采集有界且仍执行 Active Adapter 新鲜度保护；任务 2 覆盖真实页面、Provider、持久化、证据、checkpoint 和状态文档。
- 无占位符：每项代码行为、测试命令、成功条件和提交范围均已写明。
- 接口一致：`collect` 仍返回 `RawPage`；`cursor_after` 仍仅在控制面确认成功后变为安全 checkpoint；不新增云端任务字段或私密配置字段。

## 执行方式

本计划沿用已批准的当前会话逐任务执行方式：每个 Task 完成后运行其测试；真实任务只在管理员点击重试后执行，并在远程验收通过前不宣称 V0 完成。
