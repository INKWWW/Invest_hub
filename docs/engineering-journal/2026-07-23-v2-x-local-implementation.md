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

## 尚未执行的外部动作

没有读取真实 X 帖子；没有应用远程 migration；没有部署；没有修改生产或共享环境。真实采集前仍需单独确认 owner-only 会话、测试博主数、是否允许有限历史范围和是否包含任何部署动作。

## 已知受限边界

实现仅调用 OpenCLI 的 `twitter tweets` 能力，不直接调用 X API。该命令的公开输出若无法提供安全的 reply/repost 关系，采集会分类失败而非推断关系；真实 Go/No-Go 验收应首先验证这些关系字段及范围下界是否可证明。
