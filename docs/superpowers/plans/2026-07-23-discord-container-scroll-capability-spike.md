# Discord 嵌套消息容器滚动能力 Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不输出或持久化真实 Discord 内容的前提下，验证一个临时、容器定向的 OpenCLI 滚动原语能否连续触发两次更早的 Discord 历史消息响应。

**Architecture:** 不改全局 OpenCLI 或 Invest Hub。将当前本机 OpenCLI 包复制到 `/private/tmp` 的随机目录，只在副本中增加 `scroll-container` 命令；该命令接收 CSS selector、方向和像素量，返回纯数值滚动度量。用户手动打开并授权的现有 Discord Chrome 标签通过 Browser Bridge 绑定；所有真实页面/网络数据只在本机短暂处理，终端只得到脱敏布尔结果与计数。

**Tech Stack:** 已安装 OpenCLI 1.8.6、OpenCLI Browser Bridge、Node.js、macOS Chrome、临时 `/private/tmp` 目录。

## Global Constraints

- 本 Spike 只使用用户已加入且明确授权的一个频道；不发送、编辑、删除消息，不访问其他频道。
- 目标 URL、正文、作者、频道名、消息 ID、Cookie、Token、Authorization、请求头、DOM 文本、截图和 trace 不得写入仓库、工程日志或终端输出。
- 不修改 `/Users/hanyuec/.local/lib/node_modules/@jackwener/opencli` 的全局安装；临时副本和其可能的本地缓存必须在结果记录后删除。
- 一次最多进行两次容器向上滚动；任意权限、登录、selector、容器可滚动性、网络新鲜度或游标异常立即 `No-Go`。
- `Go` 只表示可提出后续独立 Spec；不授权 500 条采集、Worker、数据库写入、摘要、定时任务、部署或个人账号生产自动化。

---

### Task 1: 构建并验证临时 `scroll-container` 命令

**Files:**
- Create: `/private/tmp/investhub-discord-scroll-<random>/opencli/`（当前 OpenCLI 包的临时副本）
- Modify: `/private/tmp/investhub-discord-scroll-<random>/opencli/dist/src/cli.js`
- Test: `node /private/tmp/investhub-discord-scroll-<random>/opencli/dist/src/main.js browser --help`

**Interfaces:**
- Consumes: CSS selector、`up|down`、可选 `--amount <pixels>` 与 `--nth <zero-based index>`。
- Produces: `{ok, moved, before_scroll_top, after_scroll_top, scroll_height, client_height}`；不得返回元素文本、属性、URL 或身份信息。

- [ ] **Step 1: 创建独立临时副本并确认其含有可运行依赖**

Run:

```bash
probe_dir=$(mktemp -d /private/tmp/investhub-discord-scroll-XXXXXX)
cp -R /Users/hanyuec/.local/lib/node_modules/@jackwener/opencli "$probe_dir/opencli"
OPENCLI_CACHE_DIR="$probe_dir/cache" node "$probe_dir/opencli/dist/src/main.js" --version
```

Expected: 输出 `1.8.6`；全局 `opencli` 文件未改动。

- [ ] **Step 2: 为临时 CLI 写入受限容器滚动命令**

在 `dist/src/cli.js` 的现有 `scroll` 命令后添加一个 `scroll-container` 命令。它只接受 CSS selector，拒绝其他方向；只解析给定 `--nth` 的元素；元素必须满足 `scrollHeight > clientHeight` 以及 `overflow-y` 为 `auto`、`scroll` 或 `overlay`。将以下 IIFE 通过 `page.evaluate(...)` 执行，其中 `selector`、`nth` 和 `deltaY` 以 `JSON.stringify` 后的值内嵌，避免字符串拼接注入：

```js
(() => {
  const nodes = [...document.querySelectorAll(selector)];
  const node = nodes[nth];
  if (!node) return { ok: false, code: 'container_not_found' };
  const overflowY = getComputedStyle(node).overflowY;
  const scrollable = node.scrollHeight > node.clientHeight &&
    /^(auto|scroll|overlay)$/.test(overflowY);
  if (!scrollable) return { ok: false, code: 'not_scrollable' };
  const before = node.scrollTop;
  node.scrollBy({ top: deltaY, left: 0, behavior: 'instant' });
  const after = node.scrollTop;
  return {
    ok: true,
    moved: after !== before,
    before_scroll_top: before,
    after_scroll_top: after,
    scroll_height: node.scrollHeight,
    client_height: node.clientHeight,
  };
})()
```

命令只将上述 JSON 写入 stdout；不打印 selector、URL、DOM、文本或调试栈。

- [ ] **Step 3: 验证命令面而不连接 Discord**

Run:

```bash
OPENCLI_CACHE_DIR="$probe_dir/cache" node "$probe_dir/opencli/dist/src/main.js" browser --help
OPENCLI_CACHE_DIR="$probe_dir/cache" node "$probe_dir/opencli/dist/src/main.js" browser probe scroll-container --help
```

Expected: 帮助包含 `scroll-container <selector> <direction>`、`--amount`、`--nth`；不创建 Browser Bridge session，不读取网页。

### Task 2: 进行最多两次的本机只读容器滚动探针

**Files:**
- Create: `/private/tmp/investhub-discord-scroll-<random>/result.json`（仅脱敏结果）
- Modify: none
- Test: 临时 CLI 的 `doctor`、`bind`、`scroll-container`、`network` 命令

**Interfaces:**
- Consumes: 用户已手动打开且保持最新位置的一个 Discord Chrome 标签。
- Produces: `{bridge_ready, container_moved_first, fresh_history_first, container_moved_second, fresh_history_second, oldest_boundary_advanced, verdict}`。

- [ ] **Step 1: 验证 Browser Bridge 并绑定既有标签**

Run:

```bash
OPENCLI_CACHE_DIR="$probe_dir/cache" node "$probe_dir/opencli/dist/src/main.js" doctor
OPENCLI_CACHE_DIR="$probe_dir/cache" node "$probe_dir/opencli/dist/src/main.js" browser discord-scroll-spike bind
```

Expected: doctor 报告 Browser Bridge 可连接；bind 只绑定当前用户打开的标签，不新建、导航或关闭标签。

- [ ] **Step 2: 仅在内存中识别候选消息滚动容器**

使用 `browser discord-scroll-spike eval` 执行只读 IIFE，筛选 `scrollHeight > clientHeight` 且 `overflow-y` 可滚动的元素。它只返回每个候选的零基 `nth`、数值滚动度量和是否位于当前 viewport；不返回 tag、class、aria、文本、属性或 URL。若无法唯一选择消息列表候选，停止并输出 `No-Go: container_not_identified`。

- [ ] **Step 3: 第一次向历史方向滚动并验证新鲜响应**

Run `scroll-container <approved selector> up --amount 500 --nth <candidate>`，随后短暂等待页面稳定。将 `network` 原始输出通过本机 JSON 过滤器直接缩减为 `{fresh_history_first: boolean, response_count_delta: number, oldest_boundary_relation: 'older'|'same_or_newer'|'unknown'}`；过滤器不得打印 URL、请求体、响应体、ID 或文本。若容器未移动，或没有一条新鲜且向历史方向推进的响应，立即 `No-Go`。

- [ ] **Step 4: 第二次重复并作 Go / No-Go 判定**

仅当第一次成功时重复 Step 3 一次。第二次响应必须仍然比第一次更早；否则 `No-Go: history_not_monotonic`。两次均通过才为 `Go`。

### Task 3: 清理与记录脱敏结果

**Files:**
- Create: `docs/engineering-journal/2026-07-23-discord-container-scroll-capability-spike.md`
- Delete: `/private/tmp/investhub-discord-scroll-<random>/`
- Test: `git diff --check` 与 `bash scripts/v0/redact-check.sh`

**Interfaces:**
- Consumes: `result.json` 的脱敏布尔值与计数。
- Produces: 只记录 Go/No-Go、是否两次移动、是否两次观察到新响应、是否边界单调推进、清理是否完成；不记录任何真实 Discord 数据。

- [ ] **Step 1: 写入工程日志**

日志必须明确本轮只验证容器滚动能力；列出已执行的最多两次动作及其脱敏结果；说明它不代表持续采集、500 条增量、账号合规批准或生产可用性。

- [ ] **Step 2: 删除临时运行时并关闭 Browser Bridge session**

Run:

```bash
OPENCLI_CACHE_DIR="$probe_dir/cache" node "$probe_dir/opencli/dist/src/main.js" browser discord-scroll-spike unbind
rm -rf "$probe_dir"
```

Expected: 用户原有标签保持打开；临时 CLI、副本、可能的本地探针结果和缓存均不存在。

- [ ] **Step 3: 验证仓库安全并提交日志**

Run:

```bash
bash scripts/v0/redact-check.sh
git diff --check
git add docs/engineering-journal/2026-07-23-discord-container-scroll-capability-spike.md
git commit -m "docs: record discord container scroll spike"
```

Expected: redaction 与 diff 检查通过；只提交脱敏工程日志。

## Plan Self-Review

- Spec coverage: Task 1 隔离新原语；Task 2 覆盖绑定、两次滚动、响应新鲜度与单调性；Task 3 覆盖清理、脱敏记录与 Git 检查。
- Placeholder scan: 无 `TODO`、`TBD` 或未定义的成功条件。
- Scope check: 不修改 Invest Hub 应用、Worker、数据库、调度或全局 OpenCLI；临时工具改动和一次性验证构成单一、可拒绝的 Spike。
