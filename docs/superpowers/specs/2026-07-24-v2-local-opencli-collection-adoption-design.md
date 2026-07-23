# V2：本地受控 OpenCLI Collection 采用设计

## 文档状态

- 阶段：V2 / 上游能力未发布时的本地依赖采用
- 书面状态：方向已获用户确认（2026-07-24）；**待用户复核本文后，才可编写 implementation plan**
- 前置事实：[V2 X Spec](2026-07-22-v2-x-information-collection-and-reader-design.md)、[V2 本地实现记录](../../engineering-journal/2026-07-23-v2-x-local-implementation.md)、OpenCLI PR #2173
- 本文不授权：应用代码、生产依赖安装、全局 OpenCLI 替换、项目数据库写入、checkpoint 推进、远程 migration、部署或定时采集。

## 1. 问题与决策

V2 的连续增量采集需要一个可证明的范围完成事实。已安装的 `opencli twitter tweets` 只能返回帖子行：它不能证明已经抵达时间下界，也不能安全表达回复与普通转发的必要关系。因此，项目不能把一次固定数量的读取当作完成，也不能安全推进 checkpoint。

OpenCLI PR #2173 提供独立、只读的 `twitter collection <username> --until <RFC3339> -f json` 命令。它返回 `posts` 与 `receipt`，只在抵达时间下界或确认 cursor 耗尽时声明完成；同时保留原创、引用、回复、转发的关系事实或明确的不可用状态。该 PR 尚未被上游合并或发布。

决策：在上游发布前，Invest Hub 可采用经验证的 PR 源码作为**本地受控工具依赖**，而不是等待不确定的上游合并时间。此路径是临时维护责任转移，不是将候选源码宣称为官方 OpenCLI 版本。

## 2. 范围与非目标

本设计仅覆盖：本地版本锁定、受控构建/调用、Collection 回执接入、失败与回滚边界、测试和未来人工切回官方版本。

不包含：直接 X API、普通用户 Token 自动化、第二套浏览器采集器、全局替换 `opencli`、自动更新/自动切回、自动部署、自动开启定时采集、媒体或外链正文解析、Provider fallback、V3 范围或 Discord 改动。

## 3. 本地依赖边界

### 3.1 不可变来源

本地工具必须锁定到 OpenCLI PR #2173 的两个提交：`584934edf245f4ecb8e617433bdcea9c65ec23c3`（共享时间线读取重构）与 `b8589347d4b6a3effae5fd2198115f59ab053946`（独立 Collection 命令）。锁定记录必须包含来源仓库、上游基线、构建时使用的依赖锁文件指纹和许可证信息；不得仅依赖临时目录、浮动分支或“最新”标签。

OpenCLI 当前声明 Apache-2.0。任何本地再分发或打包都必须保留适用许可证、版权与 notice；本项目不应把本地构建命名、展示或报告为官方发布版本。

### 3.2 专用运行时

本地构建必须位于 owner-only、Git 忽略的运行时目录，并以 V2 专用可执行入口调用。不得覆盖全局 `opencli`，不得修改既有 Discord 运行时，也不得复用未锁定的临时源码路径。

Worker 配置必须显式指向该专用入口。运行时只能复用用户已登录的 X 网页会话；不得读取、导出、打印或持久化 Cookie、CSRF、Bearer Token、浏览器 Profile、cursor 或原始网络响应。

## 4. Collection 合同与项目适配

V2 X Adapter 必须从每个不可变范围的重叠下界构造 `--until`，并把任务固定 `end_at` 作为上界过滤条件。它只接受以下成功条件：

- 返回对象恰含 `posts` 与 `receipt`；
- `receipt.completed` 为真；
- `receipt.requested_until` 与本任务请求的规范化下界相同；
- `receipt.stop_reason` 仅为 `time_boundary_reached` 或 `cursor_exhausted`；
- 所有帖子具有稳定 ID、时区明确的时间、HTTPS 原帖链接、配置作者身份和可验证的关系事实。

达到 Collection 的 limit、页数保护、重复 cursor、无效时间、未解决转发关系、命令缺失、版本/manifest 不匹配、非 JSON 输出或任何 receipt 不一致，均为分类失败。失败任务保留原 checkpoint、范围与诊断摘要；不得回退到旧 `tweets`、固定数量读取、手写 HTTP 或 DOM 采集器。

Collection 是一个范围读取而非项目侧无限分页协议。项目可将其作为一个已证明完成的采集段处理；中断后重跑相同不可变范围，并依靠稳定 ID 与既有持久化幂等性去重。只有原始、Canonical、关系、逐帖分析、窗口观点与控制面回执都成功后，才能移动该来源的连续水位。

## 5. 维护、升级与回滚

本地依赖更新必须是显式维护操作：记录候选来源与 diff，重建专用运行时，运行 OpenCLI 聚焦测试、项目 Adapter/Worker/数据库/Reader 回归，并在新的明确授权下进行最小真实验证。任何失败均保留现有已确认水位并停止新范围。

上游版本监测仅用于提醒。出现包含同等 `collection + receipt` 合同的官方可安装版本时，系统向管理员报告版本、合同核对与建议；**管理员人工复核并明确决定后**，才可在独立变更中切换。不得自动安装、自动替换专用入口、自动迁移 checkpoint 或删除本地构建。

回滚只允许停用 V2 本地 Collection 运行时并保留最后安全 checkpoint。不得将来源静默改回旧 `tweets`，也不得删除已确认的 V2 事实、分析、摘要版本或工程证据。

## 6. 验收与证据

implementation plan 至少必须覆盖：

1. 锁定来源和专用入口的缺失、SHA/manifest 不匹配、命令不可用时安全失败；
2. `posts + receipt` 的结构、下界、cursor 耗尽、limit/页数/重复 cursor/时间错误和四类帖子 fixture；
3. Collection 完成回执到 X 范围完成、持久化确认和 checkpoint 的完整链路；
4. 旧 `tweets` 不得成为自动 fallback，且 Discord 路径不受影响；
5. 逐帖 Codex CLI 输出、窗口观点和追加式每日阅读的既有 V2 回归；
6. 在用户再次明确授权后，一次可持久化的 owner-only 本地真实端到端验收；真实样本须尽可能覆盖引用、回复、转发，未覆盖的类别必须保持未验证状态；
7. 许可证/版本记录、`git diff --check`、脱敏检查与不含真实内容的工程日志。

本地源码级的 2026-07-24 验证已经证明一次有界读取、13 条逐帖 Codex CLI 分析和每日聚合可通过；它是本设计的访问与理解前置证据，不替代上述可持久化运行、关系类别和官方切换验收。

## 7. 实施门禁

在用户复核并批准本设计、再批准独立 implementation plan 前，不得安装或构建本地替代版本，不得修改 X Adapter/Worker/共享协议，不得写入真实数据、推进 checkpoint、部署或开启定时采集。

该 Plan 必须保持为一个窄范围的 V2 依赖采用与激活计划；它不得借机扩展到 X API、浏览器第二采集器、跨来源阅读、自动回退或长期无人值守运维。

## 8. Spec 自检

- 版本锁定、许可证、专用运行时、Collection 完成合同、失败不前移、人工切回官方版本均有明确所有者和边界。
- 不以临时源码、固定数量读取或旧 `tweets` 作为范围完成替代。
- 本地真实验证、可持久化验收、部署与定时采集互相独立，均保留授权门禁。
- 不包含 V2 之外的采集路线、Provider、阅读范围或 Discord 改动。
