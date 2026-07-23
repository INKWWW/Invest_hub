# OpenCLI X Collection Receipt 增量 Spec

## 文档状态

- 阶段：V2 依赖的 OpenCLI 上游兼容性增强
- 书面状态：**设计已确认，待用户审阅本文并批准独立 implementation plan**
- 日期：2026-07-23
- 上游目标：[jackwener/OpenCLI](https://github.com/jackwener/OpenCLI)
- 关联：[V2 X Spec](2026-07-22-v2-x-information-collection-and-reader-design.md)、[V2 Plan](../plans/2026-07-22-v2-x-information-collection-and-reader.md)

本文只定义提交到 OpenCLI 上游的 Twitter/X Adapter 增量。它不授权修改 Invest Hub 的共享协议、远程迁移、部署、真实持续采集或发布。

## 1. 问题与目标

V2 的 X Adapter 必须证明每个不可变时间范围已经抵达下界，且必须正确区分原创、引用、回复与无附加评论的普通转发。当前 OpenCLI `twitter tweets` 已能读取基础帖子字段和引用帖摘要，但对外丢弃了回复/转发关系及分页停止事实；项目侧因此无法把成功读取固定数量帖子误判为完整时间范围。

目标是在不改变既有 `opencli twitter tweets` 默认用户体验的前提下，增加一个显式、可验证、非敏感的 collection receipt 模式，使可靠的下游采集器能判断关系归因和范围完成。

## 2. 范围与非目标

### 范围

- 修改 OpenCLI 上游的 Twitter `tweets` Adapter 及其人工测试 fixture；
- 新增 opt-in `--collection-receipt` 模式与 `--until <RFC3339>` 下界参数；
- 在该模式输出规范化的帖子关系和单次读取回执；
- 以公开人工 GraphQL fixture 验证关系、分页和失败语义；
- 在上游合并并发布可安装版本后，再由 Invest Hub 以独立变更接入并重新进行授权真实 Go/No-Go。

### 非目标

- 不调用直接 X REST API，不导出 Cookie、CSRF、Bearer token、cursor token、Profile 或完整请求头；
- 不用 DOM 抓取或第二套浏览器采集器替代现有 OpenCLI Cookie/页面会话路径；
- 不把 X 原文、账户、链接或真实响应写入任何公开 fixture、提交或工程文档；
- 不改变 `twitter tweets` 未启用 `--collection-receipt` 时的参数、返回行或排序；
- 不使 V2 在 receipt 不完整时降级为成功、无新增或 checkpoint 前进。

## 3. 设计决策

### 3.1 保持默认模式兼容

默认模式继续返回既有按时间倒序的帖子行数组。`--collection-receipt` 是显式 opt-in；只有该模式返回下列 envelope：

```json
{
  "posts": ["existing post fields plus relationship"],
  "receipt": {
    "completed": true,
    "stop_reason": "time_boundary_reached",
    "requested_until": "RFC3339 timestamp",
    "pages_fetched": 0,
    "oldest_seen_at": "RFC3339 timestamp or null"
  }
}
```

`--until` 表示可靠性下界：Adapter 只有观察到至少一条 `created_at <= until` 的帖子，或确认 timeline cursor 已耗尽，才可令 `receipt.completed=true`。它不是按页面数、滚动次数或 `limit` 计数的成功替代。

### 3.2 规范化关系事实

collection 模式中的每条帖子增加：

```json
{
  "relationship": {
    "kind": "original | quote | reply | repost",
    "target": {
      "post_id": "stable ID or null",
      "author_handle": "handle or null",
      "author_id": "stable author ID or null",
      "url": "canonical URL or null",
      "context_status": "complete | unavailable | unknown"
    }
  }
}
```

- `original` 的 `target` 为 `null`。
- `quote` 使用可见的 quoted target；若目标删除、受限或仅能取得 ID，关系仍保留，`context_status` 不得伪称 `complete`。
- `reply` 使用 X payload 的回复目标 ID、作者标识和可构造链接；若父帖正文不可见，标记 `unavailable`，不推断上下文。
- `repost` 使用 payload 中被转发原帖的稳定身份；没有可确认目标时是关系解析失败，不得只以 `RT` 前缀当作完整关系。

关系对象只表达平台返回的最小事实；不对被引用、被回复或被转发帖生成投资观点。

### 3.3 范围回执与失败

`receipt.completed` 只能为真于：

1. 已抵达 `--until` 的时间下界；或
2. timeline cursor 确认耗尽，且本次读取没有协议、时间解析或页面错误。

成功原因仅可为 `time_boundary_reached` 或 `cursor_exhausted`。`limit_reached`、`page_guard_hit`、重复 cursor、请求错误、GraphQL 形状变化、缺失/不可解析时间或关系无法确定均不得返回完成回执；应以现有 OpenCLI typed error 或明确的非完成状态结束。不得在已读取部分页面后静默返回一个看似完整的数组。

回执不回传 cursor 值、用户身份、URL、正文、Cookie、请求头或原始 payload。

### 3.4 Invest Hub 接入边界

OpenCLI 仍仅是访问层。上游 receipt 证明的是一次网页读取的关系和停止事实；Invest Hub 仍独立负责：

- 固定上海时间范围与上界排除；
- 每页持久化、稳定 ID 去重、恢复游标和失败隔离；
- 只有持久化、Canonical、逐帖 Codex CLI 结果与窗口摘要均成功后才推进 checkpoint；
- 普通读者安全投影与权限隔离。

上游 PR 合入不等同于 V2 Go，也不自动授权真实采集、Codex CLI、远程 migration 或部署。

## 4. 验收与测试

上游 PR 至少应有人工、公开的单元 fixture 覆盖：

1. 原创、引用、回复和普通转发四类关系的 ID、作者、链接与上下文状态；
2. 删除/受限引用与不可见回复上下文不被臆测；
3. 多页读取抵达时间下界时返回 `time_boundary_reached`；
4. 没有更多 cursor 时返回 `cursor_exhausted`；
5. `limit`、页数保护、重复 cursor、请求错误和时间解析错误绝不宣称完成；
6. 未启用新 flag 的既有 `tweets` 输出保持完全兼容；
7. Adapter 注册校验与上游相关测试通过。

实际 X 验证须在 PR 合入、可安装版本确认、Browser Bridge 健康并再次取得明确授权后进行；只保留脱敏计数、状态和失败类别。

## 5. 回滚与发布门禁

若上游 review 发现默认模式兼容性、关系字段准确性或 receipt 完成语义存在疑义，PR 不合并；本机仍保持 V2 的 `x_collection_unverified`。若发布后发现错误，撤销或修正 OpenCLI 版本，并使 Invest Hub 拒绝未知 receipt 版本，不得以旧输出继续运行。

只有以下条件全部满足，才可开始 Invest Hub 的后续接入 Plan：上游 PR 已合并；包含该能力的可安装 OpenCLI 版本可验证；公开测试通过；授权会话中的最小真实 Go/No-Go 证明四类关系与时间下界语义可用。任何一项不满足，V2 继续停留在安全 No-Go。

## 6. Spec 自检

- 默认输出兼容与 collection 模式的新增 envelope 已明确分离。
- 时间范围完成不依赖页数、滚动次数或单纯 limit。
- 关系事实、上下文不可见和普通转发观点归因均有保守边界。
- 未引入直接 API、普通用户 Token、第二套采集器、共享协议改动或真实数据持久化。
- 上游 Adapter 与 Invest Hub 的职责、发布门禁和回滚路径均可独立验证。
