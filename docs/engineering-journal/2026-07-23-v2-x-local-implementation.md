# V2 X 本地实现记录

日期：2026-07-23

## 已完成的本地实现

- 增加 X 来源、帖子上下文、逐帖不可变分析与窗口观点段的加性数据模型；X 任务与 Discord 任务保持严格类型隔离。
- 每个 X 来源按上海时间的 `08:00 / 12:00 / 16:00 / 20:00 / 次日 00:00` 创建连续范围；范围从最后成功覆盖水位开始，并带 30 分钟重叠复查。
- X 页面须先获得持久化确认才可继续；固定 `end_at` 以后的帖子、未证明下界的结果、身份不一致与缺失关系字段都安全失败，不推进水位。
- 对每一条新帖子独立调用 Codex CLI 的受限结构化操作；窗口观点只接收本窗口新生成的已验证逐帖分析。此前窗口的模型文字不作为输入，数据库以追加段保存结果。
- 增加 `/x` 安全阅读页、`/api/reader/x` 和顶部来源导航。阅读页默认显示每日综合观点，逐帖观点、论据、引用帖观点与原始 X 链接折叠在证据明细中；不返回原文、内部 ID、本地引用、Prompt、Provider 或凭据。
- 增加管理员 X 来源登记、待验证身份提示、覆盖水位初始化、手动更新与有界历史回填。历史范围要求已过去、同一上海自然日且不与该博主活动范围重叠；历史完成复用严格逐帖证据校验，只有恰好与连续水位相接时才可推进水位。

## 本地验证

- `SUPABASE_DISABLE_TELEMETRY=1 supabase db reset`
- `SUPABASE_DISABLE_TELEMETRY=1 supabase test db`：17 个文件、240 项断言通过。
- `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v`：100 项通过。
- `cd apps/control-plane && npm test && npm run lint && npm run build`：84 项 Vitest 通过，lint 和 production build 通过。
- `bash scripts/v2/run-v2-e2e.sh`：3 项 V2 公开 fixture E2E、5 项 V1.1 fixture 回归、11 项窗口/调度 Worker 回归和 51 项控制面聚焦测试通过；脚本不读取浏览器 Profile、真实 URL、凭据或私有 Prompt。

## 已授权的最小真实 X Go/No-Go

在用户明确授权后，已对一名指定测试博主执行一次 owner-only、最多 20 条、非持久化的 OpenCLI 读取诊断。仅输出并保留了聚合字段覆盖结果：登录态、稳定 ID、时间、链接和基础类型字段均可用，并观察到引用帖；回复/转发关系字段及可证明的分页下界均不可用。结果分类为 `x_collection_unverified` / `opencli_contract`，受保护的仓库外本地证据不含账户、正文、链接、Cookie、Profile 或完整响应。

没有创建云端任务；没有调用 Codex CLI；没有应用远程 migration；没有部署；没有修改生产或共享环境。真实采集、远程 migration、部署和真实普通用户验收仍须逐项单独明确授权。

## 2026-07-24 源码级真实抓取与总结验证

在用户明确授权后，使用 OpenCLI PR #2173 的受保护本地源码副本（不是已安装的官方 OpenCLI）进行了一次隔离、非持久化的真实验证。验证范围仅为一名已配置测试博主、固定的 RFC3339 时间下界和最多 100 条的只读读取；不创建项目任务、不写项目数据库、不推进 coverage/checkpoint、不执行远程 migration 或部署。

- 登录态复核通过；有界命令返回 14 条帖子、1 页，并给出 `time_boundary_reached` 的完成回执。
- 其中 13 条位于测试时间窗内。每条均由本机 Codex CLI 单独产生 V2 结构化分析，并通过精确的单帖 ID、原始 HTTPS 帖子链接与证据范围校验；随后按上海自然日完成一条每日综合观点，并校验其仅引用本窗口逐帖分析和帖子证据。
- 本次真实样本均为原创帖；引用帖、回复、转发仍只有公开 fixture 覆盖，尚未获得真实样本验证。
- 原始帖子、模型原始输出和临时诊断均在测试结束后删除；日志只保留聚合计数、完成回执类别、验证范围和结论，不保留账户、正文、链接、Cookie、Profile 或完整响应。

该结果证明 PR 源码可在已登录会话中完成一次有界读取与 Codex CLI 结构化理解；它**不**构成 V2 生产 Go。PR 仍须由 OpenCLI 上游维护者合并并发布可安装版本；Invest Hub 仍须以官方 `twitter collection` 命令及完成回执替换当前旧 `twitter tweets` 调用，并在新的批准 Plan 下完成可持久化的真实端到端验收。

## OpenCLI 上游能力提议

- 状态：`proposed`。已创建 [OpenCLI PR #2173](https://github.com/jackwener/OpenCLI/pull/2173)，新增独立的 `opencli twitter collection <username> --until <RFC3339> -f json`；既有 `twitter tweets` 的参数、columns 与行数组输出保持不变。
- PR 基线为 OpenCLI `1.8.6` 的 `5256711a25458e537c5a63d2a6f9c7fd36d0d1eb`，提议提交为 `584934ed` 与 `b8589347`。公开人工 fixture 覆盖原创、引用、回复、转发、时间下界、cursor 耗尽、重复 cursor、limit、页数保护、时间错误与命令 envelope。
- 上游验证：Twitter 聚焦 27 项测试、完整 Adapter 474 个文件/4,977 项测试、TypeScript typecheck、manifest build、两个命令的单独注册校验、silent-column-drop 与 typed-error gate 均通过。
- 这不是 V2 Go。只有 PR 合并、包含能力的可安装版本可验证，并在新的明确授权下完成最小真实 Go/No-Go 后，才可考虑 V2 的后续接入；此前仍不得真实采集、调用 Codex CLI、推进水位、远程 migration 或部署。

## 已知受限边界

当前 Invest Hub 实现仍仅调用已安装的 OpenCLI `twitter tweets` 能力，不直接调用 X API。该命令的公开输出若无法提供安全的 reply/repost 关系，采集会分类失败而非推断关系；待上游提议合并、发布并获授权后，真实 Go/No-Go 应首先验证 collection 命令的关系字段及范围下界是否可证明。
