# X 可见正文与 repost 关系修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留带有可见博主正文的 repost 记录，使其能被安全分析，同时继续排除无正文的普通 repost。

**Architecture:** `OpenCLICollectionInvoker` 原样传递已返回的可见正文；`Canonicalizer` 允许该正文与 repost 关系共存；单帖 Prompt 将“不得产生观点”的条件收窄至空正文 repost。关系 ID、上下文状态和所有持久化接口保持不变。已污染的单帖仅在独立重新读取成功后进行一次受控勘误和重分析。

**Tech Stack:** Python 3、既有 `unittest`、受控 OpenCLI Collection、本机 Codex CLI、既有 Supabase 投影。

## Global Constraints

- 只修改 `workers/v0` 内的 Adapter、Canonicalizer、公开 X Prompt 及其测试；不得增加依赖、表、共享 DTO、第二采集器或 Reader UI。
- `repost` 的关系目标和 `context_status` 必须保持；不得从目标、引用帖、媒体或不可见上下文补写博主正文。
- 只有非空的 Collection `row.text` 可作为 repost 的可见博主正文；空 repost 仍不得生成博主观点。
- 真实内容、链接、Profile、模型响应与勘误 SQL 不得进入 Git、fixture、日志或计划文件。
- 历史勘误只限 `2084067672032166381`，且仅在代码验证和实时重读身份匹配后执行；任何不匹配或失败均不写生产数据。

---

### Task 1: 为可见正文归因建立失败回归

**Files:**
- Modify: `workers/v0/tests/test_x_active_adapter.py`
- Modify: `workers/v0/tests/test_x_canonical.py`
- Modify: `workers/v0/tests/fixtures/opencli_collection_success.json`
- Modify: `workers/v0/prompts/v2_x_chunk.md`

**Interfaces:**
- Consumes: Collection 行的 `text`、`relationship.kind` 和 `relationship.target`。
- Produces: `RawPage.messages[*]` 中可与 `post_type = "repost"` 共存的非空 `text`，供 `Canonicalizer.map` 使用。

- [ ] **Step 1: 写出会捕获正文丢失的 Adapter 失败测试。**

将人工 fixture 的 repost 文本设为 `"visible repost commentary"`；在既有 Collection 集成测试中断言最后一条 `post_type` 仍为 `"repost"`、`reposted_post_id` 不变且 `text == "visible repost commentary"`。现有代码会因强制置空而失败。

- [ ] **Step 2: 写出会捕获错误拒绝的 Canonicalizer 失败测试。**

把当前“repost 不能带博主评论”的拒绝测试替换为：同一条含 `post_type="repost"`、稳定 `reposted_post_id` 和 `text="visible repost commentary"` 的输入成功映射，并断言 `message.content` 与 `metadata["x"]["reposted_post_id"]` 都保留。另保留空 repost 成功且内容为空的断言。现有代码会在前一个例子抛出 `CanonicalValidationError`。

- [ ] **Step 3: 明确公开 Prompt 的空正文边界。**

把 `v2_x_chunk.md` 的规则改为：“只有 `post_type` 为 `repost` 且 `text` 为空时，才不得生成博主观点；有非空 `text` 时，只能依据该 `text` 判断。”不改变 JSON schema 或证据要求。

- [ ] **Step 4: 运行红灯验证。**

```bash
PYTHONPATH=workers/v0/src python3 -m unittest workers/v0/tests/test_x_active_adapter.py workers/v0/tests/test_x_canonical.py -v
```

预期：Adapter 断言收到空文本，Canonicalizer 测试因拒绝非空 repost 失败；其他既有用例继续运行。

### Task 2: 以最小代码保留可见正文

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/connectors/x_active_adapter.py`
- Modify: `workers/v0/src/invest_hub_worker/canonical.py`

**Interfaces:**
- Consumes: Task 1 的非空/空 repost 断言。
- Produces: 带关系 ID 的 CanonicalMessage，`content` 精确等于 Collection 行的非空 `text` 或空字符串。

- [ ] **Step 1: 修改 Adapter 的 repost 文本映射。**

在 `_normalize_row` 的非原创分支中，把条件清空替换为 `"text": str(row.get("text") or "")`。保留 `post_type`、关系字段、目标 ID、context 状态、附件和 quote-only 上下文分支原样不动。

- [ ] **Step 2: 放宽 Canonicalizer 的错误前提。**

删除仅因 `post_type == "repost" and content` 而抛出的验证；保留所有稳定 ID、URL、关系字段唯一性、context 状态和完整上下文校验。Canonicalizer 不得新增文本来源或改变 `reposted_post_id`。

- [ ] **Step 3: 运行绿灯与相关运行时回归。**

```bash
PYTHONPATH=workers/v0/src python3 -m unittest workers/v0/tests/test_x_active_adapter.py workers/v0/tests/test_x_canonical.py workers/v0/tests/test_x_windowed_runtime.py workers/v0/tests/test_x_structured_output.py -v
git diff --check
```

预期：所有用例通过；空 repost 和 receipt 合同没有回归。

### Task 3: 真实单帖修复与页面验收

**Files:**
- Create: `docs/engineering-journal/2026-08-03-x-visible-text-repost-classification.md`

**Interfaces:**
- Consumes: 已验证的代码、已登录的 owner X 会话、生产中该单帖的稳定身份。
- Produces: 脱敏工程记录，以及仅在全部条件满足时更新后的生产投影。

- [ ] **Step 1: 以受控 Collection 只读重取。**

运行已安装的本地 Collection executable，使用覆盖该帖时间的明确 `--until`，在内存中筛选 ID `2084067672032166381`。只比较稳定 ID、作者、状态链接和“正文非空”条件；不得把正文或完整 JSON 输出到 Git/日志。

- [ ] **Step 2: 条件性勘误并重新分析。**

仅当 Step 1 四项身份检查均通过时，在一个受审计事务中更正这条 Canonical 文本、对应事实 hash/本地证据引用和 version-1 分析/窗口段投影；前后状态均以稳定 ID、hash、时间和行数记录。若任一检查失败，事务回滚且不写生产。

- [ ] **Step 3: 生产只读验收与工程记录。**

查询该稳定 ID 的 Canonical 文本是否非空、分析的 `blogger_viewpoint` 是否非空、当天窗口观点是否包含该分析，并以已登录 `/x` 页面确认它不再显示“未表达（例如普通 repost）”。工程记录只写脱敏的条件、测试命令、结果、生产部署 commit 与验收时间；不写正文、凭据或私有路径。

- [ ] **Step 4: 提交。**

```bash
git add workers/v0/src/invest_hub_worker/connectors/x_active_adapter.py workers/v0/src/invest_hub_worker/canonical.py workers/v0/prompts/v2_x_chunk.md workers/v0/tests/test_x_active_adapter.py workers/v0/tests/test_x_canonical.py workers/v0/tests/fixtures/opencli_collection_success.json docs/engineering-journal/2026-08-03-x-visible-text-repost-classification.md
git commit -m "fix(v2): preserve visible repost commentary"
```

若 Step 3 未达到条件，保留代码与测试提交，但不得把生产修复或页面验收表述为完成。

## Plan 自检

- Spec 的三种 repost 情形均有直接测试或验收步骤。
- 没有新增 schema、依赖、页面或采集器。
- 历史生产写入有稳定身份、实时重读、事务和回滚门槛，且不会把真实内容写入仓库。
