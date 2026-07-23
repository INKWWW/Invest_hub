# V2 本地 OpenCLI Collection 受控采用 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不等待上游合并的前提下，将已验证的 OpenCLI `twitter collection` 候选源码锁定为本机、非全局的 V2 X 采集运行时；V2 Worker 只接受带有可验证完成回执的范围读取，并保持所有 X 水位、持久化和真实运行均需单独授权的门禁。

**Architecture:** 受版本锁定的本地 OpenCLI 运行时只复用已登录的浏览器会话，并输出 `posts + receipt`。项目侧 `OpenCLICollectionInvoker` 对命令、JSON、回执和关系事实进行严格校验；`XActiveAdapter` 将其变成单个有来源的 `RawPage`；`XWindowedRuntime` 只依据回执声明范围完成。原始/Canonical 数据、checkpoint、Codex CLI 理解和 Reader 继续沿用已批准的 V2 边界，不改共享协议，也绝不退回旧 `tweets` 读取。

**Tech Stack:** Node.js 20+、受控的 OpenCLI fork 源码、POSIX shell、Python 3/`unittest`、既有 Supabase 回归与 Codex CLI Provider。

## Global Constraints

- 本计划依赖已批准的 [本地采用 Spec](../specs/2026-07-24-v2-local-opencli-collection-adoption-design.md) 和 [V2 X Spec](../specs/2026-07-22-v2-x-information-collection-and-reader-design.md)，但 Plan 本身仍须获得用户批准后才能执行。
- 运行时只能放在 Git 忽略的 `.runtime/v2/opencli-collection/`；不得替换全局 `opencli`、写入用户的包管理器目录，或保存 Cookie、Profile、真实博主、帖子文本、URL、真实模型输出与凭据。
- 锁定来源为 `https://github.com/INKWWW/OpenCLI.git`，先决提交 `584934edf245f4ecb8e617433bdcea9c65ec23c3` 与 Collection 提交 `b8589347d4b6a3effae5fd2198115f59ab053946`；`package-lock.json` SHA-256 必须为 `e149339d464cf4f19c651fcae19471d67e1f29ad87502ae2d8e6b1e2fcf1f54e`。Apache-2.0 许可文件随本地源码保留。
- 上游监测只提醒管理员。官方版本的安装、切换、checkpoint 迁移和删除本地运行时都必须由管理员重新审阅并明确授权；不得自动执行。
- 采集成功的唯一完成条件是：请求的 `--until` 等于本窗口的 `overlap_start_at`（或 `start_at`），`receipt.completed == true`，`receipt.stop_reason` 为 `time_boundary_reached` 或 `cursor_exhausted`，并且回执结构、时间和每条关系事实均通过校验。其余任何情况均失败且不得推进 checkpoint。
- 保持 V2 排除项：X 直接 API、普通用户 token 自动化、第二套完整浏览器采集器、自动 fallback、外链正文/媒体/OCR 解析、自动定时安装/采集/部署。
- 每项实施完成后才提交一次聚焦 Git commit；不 push、不部署。所有测试 fixture 均为人工构造公开数据。

---

## Task 1: 锁定来源并提供非全局、可验证的本地运行时

**Files:**

- Create: `tools/opencli-v2-collection.lock.json`
- Create: `scripts/v2/install-local-opencli-collection.sh`
- Create: `scripts/v2/verify-local-opencli-collection.sh`
- Create: `scripts/v2/test-local-opencli-collection-contract.mjs`
- Create: `workers/v0/tests/fixtures/opencli_twitter_collection_help.txt`
- Modify: `.gitignore`
- Modify: `scripts/v2/run-v2-e2e.sh`

- [ ] **Step 1: 写出先失败的锁定合同测试。**

  `scripts/v2/test-local-opencli-collection-contract.mjs` 只读取 lock 文件和传入的本地 executable，不读取登录态。它必须断言：锁文件字段完整、两个完整 Git SHA、`package_lock_sha256`、Apache-2.0、运行时相对目录、`twitter collection` 命令名，以及成功回执的四个允许字段。传入假的 executable 或缺少 `collection` 命令时以非零退出。

  最小断言形状：

  ```js
  assert.equal(lock.command, 'twitter collection');
  assert.deepEqual(lock.success_stop_reasons, [
    'time_boundary_reached', 'cursor_exhausted',
  ]);
  assert.match(help, /twitter\s+collection/);
  assert.match(help, /--until/);
  ```

  运行：

  ```bash
  node scripts/v2/test-local-opencli-collection-contract.mjs --lock tools/opencli-v2-collection.lock.json --executable /path/to/fixture-opencli
  ```

  预期：在 lock 和 fixture 尚不存在时失败；测试不得联网、不得调用 X。

- [ ] **Step 2: 以非秘密 metadata 固化来源和验收面。**

  新建 `tools/opencli-v2-collection.lock.json`。它只包含公开 provenance 和合同，不含本机路径、账号或 URL：

  ```json
  {
    "schema_version": 1,
    "source_repository": "https://github.com/INKWWW/OpenCLI.git",
    "base_commit": "584934edf245f4ecb8e617433bdcea9c65ec23c3",
    "collection_commit": "b8589347d4b6a3effae5fd2198115f59ab053946",
    "package_lock_sha256": "e149339d464cf4f19c651fcae19471d67e1f29ad87502ae2d8e6b1e2fcf1f54e",
    "license": "Apache-2.0",
    "runtime_dir": ".runtime/v2/opencli-collection",
    "command": "twitter collection",
    "success_stop_reasons": ["time_boundary_reached", "cursor_exhausted"]
  }
  ```

  在 `.gitignore` 保持 `.runtime/` 规则有效；如需更明确注释，只添加 `.runtime/v2/opencli-collection/`，不得取消整体忽略。

- [ ] **Step 3: 实现候选构建、验证后切换的安装脚本。**

  `scripts/v2/install-local-opencli-collection.sh` 必须：

  1. 接受 `--lock <path>`、`--runtime-dir <path>` 和显式 `--approve-local-build`；缺少确认参数则退出。
  2. 在 `mktemp -d` staging 目录 clone 指定 source repository，`git checkout --detach` 精确 `collection_commit`，核对 `HEAD`、两个提交祖先关系、`package-lock.json` hash 和 `LICENSE` 的 Apache-2.0 文本。
  3. 在 staging 中执行 `npm ci` 和 `npm run build`；不使用 `npm install`、`npm link`、全局安装或修改全局 `opencli`。
  4. 为 `node dist/src/main.js` 创建专用入口 `bin/opencli-v2-collection`，并在 staging 内运行 `twitter collection --help` 与 Task 1 合同测试。
  5. 所有验证通过后才将 staging 原子移动为 `.runtime/v2/opencli-collection/current`；旧 `current` 先重命名为带时间戳的 rollback 目录，保留到管理员确认删除。任何失败保留旧 `current` 且返回非零。

  专用入口的核心必须等价于：

  ```sh
  exec node "$runtime_root/current/source/dist/src/main.js" "$@"
  ```

  运行时布局固定为 `current/source/`（受控源码）与 `current/bin/`（专用入口）；脚本先检查 `current/source/dist/src/main.js` 存在和 Node 主版本不低于 20。

- [ ] **Step 4: 实现只读验证脚本并接入确定性 V2 回归。**

  `scripts/v2/verify-local-opencli-collection.sh` 不构建、不下载、不访问 X。它接受相同 lock/runtime 参数，运行以下检查：文件哈希、`git rev-parse HEAD`、Node 版本、`--help` 的 `collection`/`--until`，以及 Node 合同测试。它打印公开版本/commit/通过项，绝不打印浏览器 profile、环境变量、命令完整 stderr 或网页内容。

  在 `scripts/v2/run-v2-e2e.sh` 中把静态合同测试作为最先执行的步骤；只有调用者显式提供已验证的专用 executable 时才运行 `verify-local-opencli-collection.sh`。普通 CI 和默认 E2E 必须仍能在没有本地构建、没有 X 登录的环境中通过。

- [ ] **Step 5: 运行 Task 1 验证并提交。**

  ```bash
  node scripts/v2/test-local-opencli-collection-contract.mjs --lock tools/opencli-v2-collection.lock.json --fixture-help workers/v0/tests/fixtures/opencli_twitter_collection_help.txt
  bash scripts/v2/run-v2-e2e.sh
  git diff --check
  ```

  需要新建纯文本公开 fixture `workers/v0/tests/fixtures/opencli_twitter_collection_help.txt`，内容仅为人工构造的 help 片段。确认没有 `.runtime/` 或真实数据进入 `git status` 后提交：

  ```bash
  git add .gitignore tools/opencli-v2-collection.lock.json scripts/v2 workers/v0/tests/fixtures/opencli_twitter_collection_help.txt
  git commit -m "feat(v2): lock local OpenCLI collection runtime"
  ```

## Task 2: 用 Collection 回执替换旧 tweets invoker，并保留完整关系事实

**Files:**

- Modify: `workers/v0/src/invest_hub_worker/connectors/x_active_adapter.py`
- Modify: `workers/v0/tests/test_x_active_adapter.py`
- Create: `workers/v0/tests/fixtures/opencli_collection_success.json`
- Create: `workers/v0/tests/fixtures/opencli_collection_incomplete.json`

- [ ] **Step 1: 为 Collection 命令和回执拒绝路径补充失败测试。**

  在 `test_x_active_adapter.py` 先新增下列断言：

  - 命令严格为 `twitter collection <handle> --until <overlap-start RFC3339> --limit … --page-delay 0 --site-session persistent -f json`，不得出现 `twitter tweets`；
  - `posts` 与 `receipt` 同时存在且均为预期类型才成功；
  - `receipt.completed != true`、未知 `stop_reason`、`requested_until` 与请求不等、无时区/无效时间、limit/repeated-cursor/page-guard 错误和非 JSON 都映射为 `opencli_contract`；
  - `time_boundary_reached` 的 `oldest_seen_at` 必须不晚于 requested lower bound；`cursor_exhausted` 可为 `null` 但不得伪造已到下界；
  - original、quote、reply、repost 分别输出 Canonicalizer 所需的关系 ID、`context_status` 与可见 context；缺失的 context 只能标为 `unavailable`/`unresolved`，不能编造内容；
  - 无论错误类型，均不存在旧 `tweets` 或第二采集器 fallback。

  fixture 只使用合成 ID、虚构公开 X URL、时间和短文本；不能复制真实 X 内容。

- [ ] **Step 2: 以严格的 Collection invoker 替代旧 invoker。**

  将 `OpenCLITweetsInvoker` 重命名为 `OpenCLICollectionInvoker`，并把它的 `fetch_page` 显式参数改为：

  ```python
  def fetch_page(
      self, *, source_url: str, profile_ref: str, cursor: str | None,
      cache_buster: str | None, lower_bound_at: datetime, end_at: datetime | None,
  ) -> Mapping[str, object]:
  ```

  `cursor` 非空即拒绝，防止旧分页状态被误当作 Collection 游标。命令使用 `lower_bound_at` 的 UTC RFC3339 `Z` 值作为 `--until`；`end_at` 仅作为上界过滤，不能替代回执下界。将 subprocess 非零退出转为无内容的分类错误；不要将 stderr 或 source URL 写进异常或 telemetry。

  收到的 JSON 必须精确校验其公共形状：

  ```python
  payload = {"posts": list[dict], "receipt": dict}
  receipt = {
      "completed": True,
      "stop_reason": "time_boundary_reached" | "cursor_exhausted",
      "requested_until": <same instant as lower_bound_at>,
      "pages_fetched": <positive int>,
      "oldest_seen_at": <RFC3339 or null>,
  }
  ```

  归一化 `relationship.kind`：`original` 不带关系；`quote` → `quoted_post_id`；`reply` → `reply_to_post_id`；`repost` → `reposted_post_id` 且当前博主 `text == ""`。关系 target 不完整时保留关系 ID（若存在）并设置 `unavailable` 或 `unresolved`，只有 `context_status == complete` 才可写入 `context_post`。让既有 `Canonicalizer._map_x` 成为第二道验证，不放宽其规则。

- [ ] **Step 3: 简化 Adapter 为一份带来源的完成页面。**

  将 `XActiveAdapter.fetch_page`、`_fetch` 接受并转传 `lower_bound_at`。Collection 是本地子进程读取，不再伪装为浏览器 Network 响应：移除 `_match` / `cache_buster` 重试的依赖，改为以 `receipt` 验证的 `match_state: "collection_receipt_verified"` telemetry。`RawPage.cursor_after` 固定为 `None`，telemetry 至少写入：

  ```python
  {
      "collection_receipt_verified": True,
      "collection_stop_reason": receipt["stop_reason"],
      "collection_requested_until": receipt["requested_until"],
      "collection_oldest_seen_at": receipt["oldest_seen_at"],
      "history_exhausted": receipt["stop_reason"] == "cursor_exhausted",
  }
  ```

  telemetry 只保存时间和枚举，不保存 posts、handle 或 URL。page ID 继续为本地随机 ID；原始内容仍只能由 Evidence Store 在真实运行时写入。

- [ ] **Step 4: 跑针对性单测并提交。**

  ```bash
  PYTHONPATH=workers/v0/src python3 -m unittest workers/v0/tests/test_x_active_adapter.py workers/v0/tests/test_x_canonical.py -v
  git diff --check
  git add workers/v0/src/invest_hub_worker/connectors/x_active_adapter.py workers/v0/tests/test_x_active_adapter.py workers/v0/tests/fixtures/opencli_collection_success.json workers/v0/tests/fixtures/opencli_collection_incomplete.json
  git commit -m "feat(v2): require OpenCLI collection receipts"
  ```

## Task 3: 将窗口完成、持久化和 checkpoint 与回执原子绑定

**Files:**

- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Modify: `workers/v0/tests/test_x_windowed_runtime.py`
- Modify: `workers/v0/tests/test_authorized_runtime.py`
- Modify: `workers/v0/tests/test_cli.py`

- [ ] **Step 1: 先写范围完成失败测试。**

  在 `test_x_windowed_runtime.py` 覆盖：

  - `overlap_start_at` 优先于 `start_at` 并作为 connector 的 `lower_bound_at`；`end_at` 在同一任务内固定；
  - `time_boundary_reached` 产出 `oldest_at_or_before_start`，`cursor_exhausted` 产出 `history_exhausted`；
  - 缺失/假回执、`completed == false`、不匹配 lower boundary、未知 stop reason、非空 `cursor_after`、和回执宣称完成但最老时间仍晚于下界，均不调用 range completion，且不产生可推进水位；
  - 空 `posts + cursor_exhausted` 是有效的 `no_new_data`；空 `posts + time_boundary_reached` 只有回执提供不晚于下界的 `oldest_seen_at` 时才有效；
  - 先成功持久化 raw/canonical/capture segment，后写 range completion；任一持久化失败均不产出成功 completion；
  - 失败重试从上一个成功 checkpoint 重放相同不可变窗口，不接受旧 `resume_cursor`。

- [ ] **Step 2: 将 `XWindowedRuntime` 改为 receipt-first 的单次有界读取。**

  `execute_windowed` 每个窗口只调用一次 Collection connector，并将 `overlap_start = overlap_start_at or start_at` 传入 `lower_bound_at`。完成边界只从已验证 telemetry 得出：

  ```python
  if receipt_stop_reason == "time_boundary_reached":
      boundary = {"kind": "oldest_at_or_before_start", "observed_at": receipt_oldest_seen_at}
  elif receipt_stop_reason == "cursor_exhausted":
      boundary = {"kind": "history_exhausted", "observed_at": receipt_oldest_seen_at or capture_range.end_at}
  else:
      raise RuntimeExecutionError("opencli_contract", "Collection cannot prove the requested range")
  ```

  `_validate_window_page` 必须验证 `collection_receipt_verified is True`、requested lower bound 与 `overlap_start` 相同、`cursor_before is None`、`cursor_after is None`。不要再用“行数小于 limit”“page 最老时间”“cursor 耗尽”推断完成；只有 receipt 才有该语义。

  `build_authorized_x_runtime` 使用 `OpenCLICollectionInvoker(opencli_executable or "opencli")`。既有 `--opencli-executable` CLI 参数保持为唯一显式注入点，以便管理员将其指向 `.runtime/v2/opencli-collection/current/bin/opencli-v2-collection`；不得写死本机绝对路径。

- [ ] **Step 3: 保证任务/协议边界没有被扩张。**

  不修改 Supabase SQL、共享 RPC/DTO 或 scheduler 协议。仅在 Python 局部运行时把 Collection receipt 放入已有 capture segment / range completion 的内部 evidence：时间、stop reason、pages count 和 receipt schema version 可留存；不得持久化命令行、handle、原始 JSON 或浏览器会话信息。更新授权运行时/CLI 测试，证明：

  - 未显式给 `--opencli-executable` 时仍不会隐式安装或切换本地 runtime；
  - `V2_REAL_X_ACK=authorized` 门禁维持不变；
  - X 失败不会阻塞其他 source，且不进入 `tweets` 路径。

- [ ] **Step 4: 跑范围与协议回归并提交。**

  ```bash
  PYTHONPATH=workers/v0/src python3 -m unittest workers/v0/tests/test_x_windowed_runtime.py workers/v0/tests/test_authorized_runtime.py workers/v0/tests/test_cli.py workers/v0/tests/test_windowed_runtime.py -v
  git diff --check
  git add workers/v0/src/invest_hub_worker/runtime.py workers/v0/tests/test_x_windowed_runtime.py workers/v0/tests/test_authorized_runtime.py workers/v0/tests/test_cli.py
  git commit -m "feat(v2): complete X windows from collection receipts"
  ```

## Task 4: 做全量确定性回归与人工可重复的真实验收入口

**Files:**

- Modify: `scripts/v2/run-v2-e2e.sh`
- Create: `scripts/v2/run-local-collection-real-e2e.sh`
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-07-23-v2-x-local-implementation.md`

- [ ] **Step 1: 先为真实验收脚本写安全门禁测试/检查。**

  新脚本必须拒绝执行，除非同时传入：

  ```text
  --opencli-executable <dedicated-local-path>
  --source-config <owner-local-ignored-config>
  --approve-real-persistence
  ```

  它还必须先运行 Task 1 verify，检查 `V2_REAL_X_ACK=authorized`，并拒绝 global `opencli` 或 runtime 目录外的 executable。测试/静态检查应证明没有这些参数时不调用 `invest_hub_worker.cli`、不创建任务、无数据库写入。

- [ ] **Step 2: 实现最小、一次性的真实持久化验收 runner。**

  runner 只执行一个管理员选定的、固定 `end_at` 的单博主窗口，并通过既有 Worker/控制平面路径完成：专用 runtime 验证 → 有界 Collection → raw/canonical 持久化 → 单帖 Codex CLI 结构化理解 → append-only daily segment → Reader DTO。它不得创建 scheduler、launchd、cron、自动重试循环或跨源执行。

  控制台只输出匿名计数、范围边界、receipt stop reason、阶段通过/失败与 redacted error code。任何失败立刻退出，保留最后安全 checkpoint；不通过 shell history、日志或 Git 记录真实 source/post/model 内容。

- [ ] **Step 3: 完成完整确定性回归。**

  ```bash
  bash scripts/v2/run-v2-e2e.sh
  (cd workers/v0 && PYTHONPATH=src python3 -m unittest discover -s tests -p 'test_*.py' -v)
  (cd apps/control-plane && npm test -- --run api integration contracts)
  supabase test db
  bash scripts/v0/redact-check.sh
  git diff --check
  ```

  若任一步失败，按分类修复后从对应 Task 的失败测试重跑；不得以跳过真实 receipt 测试或降级为 `tweets` 取得通过。

- [ ] **Step 4: 记录结果但保持真实运行二次授权。**

  确定性测试通过后，在 `docs/project-status.md` 记录“本地 Collection 代码/确定性验证通过，真实持久化 E2E 待管理员单独授权”；在工程日志只记录版本 SHA、测试计数、回执枚举和 redacted 结果。真实命令只在用户之后明确授权“执行真实持久化 E2E”时运行，且运行前再次展示精确命令和写入范围。

  提交：

  ```bash
  git add scripts/v2/run-v2-e2e.sh scripts/v2/run-local-collection-real-e2e.sh docs/project-status.md docs/engineering-journal/2026-07-23-v2-x-local-implementation.md
  git commit -m "test(v2): add controlled local collection acceptance"
  ```

## Task 5: 完成后复核与官方版本人工切回流程

**Files:**

- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-07-23-v2-x-local-implementation.md`
- Modify: `docs/superpowers/specs/2026-07-24-v2-local-opencli-collection-adoption-design.md`

- [ ] **Step 1: 对已实现差异做 completion review。**

  逐项比对本计划和 Spec：来源 lock、非全局性、receipt 校验、关系完整性、失败不推进、无 fallback、隐私、回归、真实验收授权。运行：

  ```bash
  git status --short
  git diff --check
  bash scripts/v0/redact-check.sh
  git log --oneline --decorate -10
  ```

  确认 `.runtime/`、真实 fixture、数据库转储、cookies、profile 和真实 stderr 都未被追踪。发现任意越界即停止发布，并在工程日志记录 redacted 原因。

- [ ] **Step 2: 形成官方版本提醒后的人工切换 checklist。**

  在 Spec/状态中保留以下固定流程：上游提醒 → 管理员查看 release/PR diff 和许可 → 在隔离 staging 构建官方版本 → 运行 Task 1–4 的确定性测试 → 管理员再次批准 → 用新的专用 executable 做一次真实最小验证 → 仅随后切换；失败则继续使用已确认本地 runtime。不得自动执行以上任一步，也不得删除 rollback runtime。

- [ ] **Step 3: 提交收尾文档。**

  ```bash
  git add docs/project-status.md docs/engineering-journal/2026-07-23-v2-x-local-implementation.md docs/superpowers/specs/2026-07-24-v2-local-opencli-collection-adoption-design.md
  git commit -m "docs(v2): record local collection adoption review"
  ```

## Acceptance Criteria

1. 专用本地 runtime 可由 lock 从指定提交可重复构建，且全局 `opencli` 未改变。
2. Worker 的唯一 X 读取命令为 `twitter collection`，并带精确 `--until`；仓库内无可达的 `twitter tweets` X 采集 fallback。
3. 每个成功窗口有真实、经过严格校验的 completed receipt；异常、limit、cursor、时间或关系不完整均不推进 checkpoint。
4. original/quote/reply/repost 关系被保留或明确标记不可用，绝不补写不存在的博主评论或引用内容。
5. V2 既有单帖 Codex CLI 分析、append-only 每日综合观点、折叠证据和 `/discord`/`/x` 阅读切换未回归。
6. 全部确定性回归、redact check 和 Git 检查通过；真实持久化 E2E 只在额外明确授权后执行并留下脱敏记录。
