# Project Status

Last updated: 2026-07-31

## Current phase

**V1 Discord 正式可用 MVP 已完成；个人 Discord 账号采集已阶段性结项，不再进入生产。V2 X 指定博主信息收集已完成生产部署、真实持久化范围闭环、X 专用本机常驻 Worker 的实际自动窗口完成，以及普通用户 `/x` 桌面/375px 阅读验收。当前结论为“受控生产试运行”：自动增量链路已验证，但真实关系类别与可恢复失败恢复仍未完整覆盖，因此不得标记为“V2 X 正式可用”或无人值守 SLA。**

**X 终态失败来源调度隔离修复（2026-07-31）：** 用户已明确批准对应 Spec/Plan、实现与线上 migration。修复目标是防止不可重试的 `opencli_contract` 终态失败窗口被调度器每个 tick 重复创建；失败来源保持审计状态和未推进 coverage，其他来源继续独立调度。该修复不改变来源标识、登录态、采集合同或历史数据，部署后仍保持 V2 受控生产试运行，不宣称无人值守 SLA。

**Discord 采集状态（2026-07-22 决定）：** 个人账号的 Page Fetch、页面 UI 自动化、直接接口和导出器路线均不再进入生产；不启用 Discord 定时或手动采集。既有 Reader 与已持久化数据保持可用，但不构成持续采集能力。未来仅在频道管理员明确授权 Bot 后，才以新的独立 Spec/Plan 评估重新启动；详见 [Discord 采集探索结论](engineering-journal/2026-07-22-v1-1-discord-collection-exploration-decision.md)。本段优先于下文历史 Browser Bridge 受限描述。

Spike-01 已完成真实网页轨验证，Spike-02 在已记录的本机 Codex CLI 条件下有条件通过；随后已按批准的 V0 Spec/Plan 完成控制面、Supabase/RLS、Python 工作节点、Active Adapter、Provider 边界、管理员调试页和脱敏 E2E harness。2026-07-19 已创建隔离 Supabase/Vercel 预览、应用远程迁移并部署新控制面；受保护预览上的合成核心工作节点链路注册 → 心跳 → 领取 → 持久化 → 回报结果已通过并回读确认检查点，普通用户管理员阻断和过期租约的检查点恢复也已远程补测。同日已完成一次用户明确授权的真实 Discord 有界单页任务：首次超时不推进安全检查点，第 2 次成功采集、结构化、远程持久化、结果回报并确认非空安全检查点。V0 因此通过；它仍不是生产发布批准。

V1 已在独立 worktree 中完成多来源来源绑定/规则、有限分页、摘要与 receipt 闭环、管理员控制、正式 `/discord` 阅读页、定时窗口幂等、离线补采和公开 fixture E2E。最终本地验证为 115 条 pgTAP、54 个控制面测试、62 个 Worker 测试和 3 个 V1 E2E 测试通过。专用 Supabase/Vercel 环境已完成真实双来源 history、两轮增量去重/checkpoint、预设 `unauthorized` 失败隔离与 A 正式恢复；同 hash 重采集的可变本地 evidence 引用冲突已由远程迁移修复。其后受邀普通用户在独立正常会话完成真实阅读、桌面/手机响应式验收；两来源真实质量抽检和 production 日志独立审阅通过。因此结论为 **V1 Discord 正式可用 MVP**。2026-07-21 已在合并后的 `main` 重跑同一套回归，并同步至 GitHub `origin/main`；核对时两端 HEAD 均为 `c493256`。

## 后续对话交接

下一次新对话应先阅读 `docs/intake.md`、本文件、[V2 Spec](superpowers/specs/2026-07-22-v2-x-information-collection-and-reader-design.md)、[V2 Plan](superpowers/plans/2026-07-22-v2-x-information-collection-and-reader.md)、[V2 工程记录](engineering-journal/2026-07-23-v2-x-local-implementation.md)、[管理员来源工作台设计](superpowers/specs/2026-07-25-admin-source-configuration-workspace-design.md)、[工作台实施计划](superpowers/plans/2026-07-25-admin-source-configuration-workspace.md)、[来源创建简化设计](superpowers/specs/2026-07-25-admin-source-creation-simplification-design.md)、[来源创建简化计划](superpowers/plans/2026-07-25-admin-source-creation-simplification.md)、[X 阅读页全量筛选设计](superpowers/specs/2026-07-26-x-reader-all-filters-design.md)、[X 阅读页全量筛选计划](superpowers/plans/2026-07-26-x-reader-all-filters.md) 与 [V2 Final Report](spikes/2026-07-22-v2-x-decision-report.md)。X 专用常驻 Worker 已完成首个自动窗口；后续仅在用户需要正式退出受控试运行时，补充真实可恢复失败恢复与关系类别覆盖。不得重新启动个人 Discord 账号采集。

**V2 状态更正（2026-07-23）：** 上述 V2 “真实 X 待办”仅指完整采集与验收；最小、非持久化的真实 Go/No-Go 已在明确授权后完成，并因 OpenCLI 缺少 reply/repost 关系与范围完成证明而判定 `x_collection_unverified` / `opencli_contract`。未创建云端任务、未调用 Codex CLI、未推进水位、未远程迁移或部署。

**V2 OpenCLI 上游提议（2026-07-23）：** 为补齐上述合同缺口，已创建 [OpenCLI PR #2173](https://github.com/jackwener/OpenCLI/pull/2173)，状态仅为 `proposed`。它新增独立 `twitter collection` 命令，保持 `twitter tweets` 的公开契约不变，并以人工 fixture 覆盖关系与完成回执。上游 PR 合并、可安装版本验证及新的明确授权真实 Go/No-Go 是后续三道独立门禁；在此之前官方/生产路径的 V2 仍为 `x_collection_unverified`，不得持续真实采集、推进水位、远程 migration 或部署。经用户明确授权的受保护、隔离源码级探针须单独记录，且不改变这些门禁。

**V2 源码级真实验证（2026-07-24）：** 在明确授权下，已使用 PR #2173 的受保护本地源码副本完成一次隔离测试：有界读取返回 14 条帖子和 `time_boundary_reached` 回执；其中 13 条在测试窗口内，13/13 完成单帖 Codex CLI 结构化分析并通过单帖 ID、原始链接和证据范围校验，随后完成上海自然日的综合观点校验。样本均为原创帖，未覆盖真实引用帖/回复/转发。原始帖子和模型输出已删除，未创建任务、写入项目数据库、推进水位、远程迁移或部署。该结果仅证明候选源码的读取与理解链路；当时 Invest Hub 仍调用旧 `tweets`，故当时生产状态保持 No-Go。

**V2 本地 Collection 受控采用（2026-07-24）：** 已在隔离 feature branch 锁定 PR #2173 的两个提交，构建 Git 忽略、非全局的专用 OpenCLI runtime，并将 V2 X Adapter/Worker 改为只接受 `twitter collection` 的 `posts + receipt`。完成回执必须精确对应窗口 `overlap_start_at`，且只允许 `time_boundary_reached` 或 `cursor_exhausted`；任何命令、回执、时间、关系或 cursor 异常都会失败且不前移水位，不会静默回退到 `tweets`。本次确定性验证通过：本地 runtime contract、100 个 Worker 测试、3 个 V2 fixture E2E、5 个 V1.1 fixture 回归、11 个窗口/调度回归、51 个控制面聚焦测试、额外 40 个 API/contract 测试，以及 17 个 pgTAP 文件/240 项；脱敏检查通过。真实持久化 E2E runner 已实现但未运行，仍需管理员之后单独明确授权。专用 runtime 构建时上游依赖审计报告 1 个 low、2 个 moderate、3 个 high 风险；未执行会改变依赖锁的自动修复，须在后续本地依赖维护中人工处理。

**V2 X 来源身份解析本地门禁（2026-07-24）：** 已完成待验证来源到 `resolved` 的原子数据库契约、仅限已绑定 Worker 的控制面端点、本机 `twitter profile` 身份核验 CLI，以及一次性本地 runner。runner 必须使用专用本地 OpenCLI、Git 忽略且 owner-only 的配置/设备凭据/evidence、`V2_REAL_X_ACK=authorized` 和独立显式批准；静态拒绝门禁确认其不会领取任务、运行采集、调用 Codex CLI 或安装调度。当前本地回归为 18 个 pgTAP 文件/259 项、116 个 Worker 测试、103 个控制面测试及 lint/production build 通过。**尚未**执行远程 migration、部署、真实 profile 身份解析、coverage 初始化、任务创建或真实持久化 E2E。

**V2 生产激活与试运行（2026-07-24，后续授权）：** 上述“尚未执行”是当时本地门禁阶段的历史状态。后续已逐项完成远程 migration、生产部署、身份解析、coverage 初始化和一次真实持久化 E2E；最新任务完整成功，原始、Canonical、逐帖分析各为 `8`，并生成 `1` 个每日观点段。生产部署与 Worker 使用的数据库绑定已实测一致。新增 X 专用 `com.investhub.x-worker` 常驻服务已通过 owner-only/受控 OpenCLI 安装前检查并实际加载运行；它只处理 X，到期窗口为 `08:00 / 12:00 / 16:00 / 20:00 / 次日00:00`。真实普通用户已完成生产 `/x` 的桌面/375px 阅读和管理员隔离验收；首个由该服务自动完成的窗口仍为 conditional，完整矩阵见 [V2 Final Report](spikes/2026-07-22-v2-x-decision-report.md)。

**Discord 交接更正（2026-07-22）：** 下文 V1.1 的历史时间窗与 Browser Bridge 说明仅保留为已完成探索记录；当前不得据此继续个人账号采集、安装任务或推进 Discord coverage。下一步是管理员授权的 Bot 路线，其余范围不变。

## Approval status

- Approved specification：
  - [模块 1 总体设计](superpowers/specs/2026-07-15-invest-hub-module-1-project-design.md)
  - [Spike-01 Discord 增量采集设计](superpowers/specs/2026-07-15-spike-01-opencli-discord-incremental-design.md)
  - [Spike-02 Codex CLI 容量与质量设计](superpowers/specs/2026-07-15-spike-02-free-llm-capacity-quality-design.md)
  - [Spike-02 有界并发设计](superpowers/specs/2026-07-18-spike-02-bounded-concurrency-design.md)
  - [Spike-02 未解析媒体来源链路设计](superpowers/specs/2026-07-18-spike-02-media-source-linkage-design.md)
  - [V0 基础设施与技术验证设计](superpowers/specs/2026-07-18-v0-infrastructure-technical-validation-design.md)
  - [V1 Discord 正式可用 MVP 设计](superpowers/specs/2026-07-19-v1-discord-mvp-design.md)
  - [V1.1 Discord 完整时间窗采集与观点阅读设计](superpowers/specs/2026-07-22-v1.1-discord-windowed-collection-and-insight-design.md)
  - [V2 X 指定博主信息收集与阅读设计](superpowers/specs/2026-07-22-v2-x-information-collection-and-reader-design.md)
  - [管理员信息来源配置工作台与 X 博主安全移除设计](superpowers/specs/2026-07-25-admin-source-configuration-workspace-design.md)
  - [管理员来源创建简化设计](superpowers/specs/2026-07-25-admin-source-creation-simplification-design.md)
  - [X 阅读页全量筛选与管理员入口设计](superpowers/specs/2026-07-26-x-reader-all-filters-design.md)
- Approved implementation plan：
  - [Spike-01 Discord 增量采集计划](superpowers/plans/2026-07-15-spike-01-opencli-discord-implementation-plan.md)
  - [Spike-02 Codex CLI 容量与质量计划](superpowers/plans/2026-07-15-spike-02-free-llm-capacity-quality.md)
  - [Spike-02 有界并发计划](superpowers/plans/2026-07-18-spike-02-bounded-concurrency-plan.md)
  - [Spike-02 未解析媒体来源链路计划](superpowers/plans/2026-07-18-spike-02-media-source-linkage-plan.md)
  - [V0 基础设施与技术验证计划](superpowers/plans/2026-07-18-v0-infrastructure-technical-validation.md)
  - [V0 收口与远程验收实施计划](superpowers/plans/2026-07-19-v0-closure-remote-validation.md)
  - [V0 真实运行有界批次恢复计划](superpowers/plans/2026-07-19-v0-real-run-bounded-batch-recovery.md)
  - [V1 Discord 正式可用 MVP 计划](superpowers/plans/2026-07-19-v1-discord-mvp.md)
  - [V2 X 指定博主信息收集与阅读计划](superpowers/plans/2026-07-22-v2-x-information-collection-and-reader.md)
  - [管理员信息来源配置工作台与 X 博主安全移除计划](superpowers/plans/2026-07-25-admin-source-configuration-workspace.md)
  - [管理员来源创建简化计划](superpowers/plans/2026-07-25-admin-source-creation-simplification.md)
  - [X 阅读页全量筛选与管理员入口计划](superpowers/plans/2026-07-26-x-reader-all-filters.md)
- V0 implementation status：已完成确定性实现、远程持久化、隔离预览部署、核心工作节点 HTTPS、远程角色/恢复和真实有界单页验收，结论为通过；真实内容仍只保留在仓库外受保护目录。
- V1 implementation status：代码、本地确定性验收、专用部署、真实双来源 history/增量/checkpoint、失败隔离/恢复、普通用户阅读与视觉、真实质量抽检和部署日志审阅均已完成；结论为 V1 Discord 正式可用 MVP。
- V1.1 implementation status：Spec 及其[独立 implementation plan](superpowers/plans/2026-07-22-v1.1-discord-windowed-collection-and-insight.md) 已于 2026-07-22 获用户批准。Task 1（完整时间窗、覆盖水位与数据库契约）完成于 `58df9ae`；Task 2（控制面初始化、作者配置与手动更新）完成于 `2541229`；Task 3（Worker 逐页持久化与范围回执）完成于 `e5079dc`；Task 4（按时间边界、无页数成功条件的 Active Adapter/runtime）完成于 `6903897`；Task 5（00:00、08:00、16:00、20:50 上海窗口、无限制补窗与 launchd 模板）完成于 `facba3d`；Task 6（两层事实/日累计作者与话题摘要）完成于 `3346889`，并由 `605ae87` 修复日累计输出只能引用已验证事实单元的证据边界；Task 7（安全作者配置界面、管理员手动更新入口、内容优先 `/discord` 阅读页）完成于 `55ad3fe`；Task 8 的本地确定性验收完成。其后用户批准作者 selector 修订：管理员可直接输入显示名/用户名，已观察作者仅作快捷建议；任务逐页持久化后，受租约保护的服务端解析唯一 stable ID，零候选 pending、多候选 ambiguous，且绝不返回原文。该修订已应用专用 V1 数据库并部署到专用 V1 生产项目（Vercel Ready、正式域名已关联）；本地验证为 11 个 pgTAP 文件/186 项、18 个控制面测试文件/79 项、Worker 82 项以及 lint/production build 全部通过。随后管理员可录入已确认的重点作者，再进行真实 Discord 正常窗口/手动范围、作者配置生效、普通用户真实生产审阅和 launchd 安装。真实内容、来源身份、凭据与私有 Prompt 继续不进入 Git。
- V2 implementation status：已完成受控本地 Collection runtime、远程 migration、生产控制面部署、来源身份解析、连续覆盖初始化、真实持久化范围闭环，以及 `com.investhub.x-worker` 常驻安装与首个自动完成窗口。最近一次受控真实范围持久化了 `2` 条逐帖分析和 `1` 段每日观点；自动轮询随后成功完成一个到期窗口，当前水位无待重试窗口。X Worker 与生产控制面数据库绑定已实测一致，生产 `/x` 路由 HTTP 可达。最新回归为 22 个 pgTAP 文件/291 项、Worker 133 项、控制面 135 项、lint、production build 和脱敏检查通过。V2 当前是受控生产试运行；正式退出门槛及限制见 [V2 Final Report](spikes/2026-07-22-v2-x-decision-report.md)。
- 管理员来源配置工作台 implementation status：Discord/X 独立工作区、来源档案卡、X 来源删除/归档生命周期与管理员 DELETE API 已完成并部署。远程 `20260725090000_admin_x_source_lifecycle.sql` 已应用，未对真实 X 来源执行删除或归档。来源创建简化已合并并部署：管理员不再填写内部来源标识或参数版本；服务端生成新来源的技术身份与默认采集契约。当前本地控制面回归为 30 个测试文件/131 项，lint、production build、脱敏检查与 `git diff --check` 通过；稳定生产入口已验证仍受登录保护。详见 [工作台工程记录](engineering-journal/2026-07-25-admin-source-configuration-workspace.md) 和 [创建简化工程记录](engineering-journal/2026-07-25-admin-source-creation-simplification.md)。
- X 阅读页全量筛选与管理员入口 implementation status：已合并并部署。管理员账户区新增 `/admin` 配置管理入口；`/x` 默认“全部博主 / 全部日期”，并逐张展示独立的博主 × 日期观点卡。指定筛选可由 URL 恢复，Reader API 将 `all` 视为未筛选。本地控制面为 32 个测试文件/139 项、lint 与 production build 通过；Vercel production `dpl_FB5jLcR7tneBu58PzBEgNywj7jPS` 为 Ready，稳定入口匿名访问仍重定向登录页。详见 [工程记录](engineering-journal/2026-07-26-x-reader-all-filters.md)。
- V0 validation stack：Next.js + Supabase/RLS、Python 3.11+ Worker、OpenCLI Active Adapter 边界、Mock/Codex CLI Provider；这些是 V0 验证选择，不等于最终生产架构批准。

`intake.md` 中的技术方向、版本范围和实现建议属于前期讨论输入；其中标注为建议或待 Spike/Spec 确认的事项，尚未自动成为生产实现决策。Spike-01 和 Spike-02 的结论只作为后续设计输入。

当前 Provider 路线决策：后续路线使用 Codex CLI 作为唯一真实 LLM Provider 候选，Mock 仅用于确定性测试；不实现 GLM API 和自动 fallback。intake 中早期的 GLM 相关内容保留为历史输入，不直接作为当前实现授权。

## Current scope

当前只处理模块 1「投资信息收集」。模块 2「选股研判」、模块 3「策略和复盘」和模块 4「投资体系」暂不进入实现范围。

模块 1 的前期目标是建立从 Discord/X 信息采集，到原始内容持久化、规则清洗、LLM 结构化理解、批次总结、日累计总结，再到网页阅读和证据回溯的可持续流水线。

## Repository state

当前仓库包含项目治理文档、Spike harness、V0 控制面/Worker 验证实现，以及 V1 多来源/摘要/阅读/调度的确定性 E2E harness。真实内容、Codex Prompt、完整响应和本地 evidence 不进入 Git；V1 的专用远程数据库迁移、部署、真实双来源有界 history 及两轮真实增量验收已执行，真实 evidence 留在仓库外 owner-only 目录。V2 的本地管理入口可登记待验证 X 博主、初始化固定覆盖水位、创建手动连续更新与同一上海自然日的有界历史回填；非连续历史完成不会移动连续水位。

## Spike-01 result

- 确定性测试：32/32 通过；
- bounded soak：202 条原始消息成功采集；
- 两轮 evidence 合计：1504 条唯一 Canonical 消息；
- checkpoint 恢复、network 空窗和逐页 telemetry 验证通过；
- 决策结论：OpenCLI-first 可作为后续设计输入，但生产采用必须保留 freshness、有限重试、失败恢复和逐页 telemetry。

## Spike-01 Active Adapter 后续方向

- Active Adapter 不是第二套完整浏览器采集框架，而是基于 OpenCLI Browser Bridge，由项目侧主动控制 Discord 频道规范化、分页、响应匹配、freshness、有限重试和失败分类的采集适配层；Canonical Schema、Evidence Store 和 checkpoint 仍沿用项目边界。
- 后续验证结果：Active Adapter 确定性测试 24/24 通过，原始 Spike-01 回归测试 32/32 通过；完成 1008 条原始/Canonical 消息处理，其中 969 条接受、39 条标记为未解决关系，重复和无效消息均为 0，并验证了 checkpoint 恢复；缺失/陈旧响应降为 0，平均每页尝试次数由 20 降至 1.13。
- 证据边界：原始 Connector 对照运行使用了错误会话，首屏未成功，因此不能据此宣称严格的同条件性能提升；长期无人值守稳定性、长尾 P95、跨日期运行、网络变化和浏览器升级后的行为仍需在 V0 设计中继续验证。
- 当前决策：Active Adapter 作为 V0 Discord 抓取的候选主路径；原始 OpenCLI Connector 保留为诊断基线和必要时的回退候选。V0 已实现该边界，但真实页面稳定性和长期生产采用仍需补证据。

## Spike-02 result

- 确定性测试：46/46 通过；
- Codex CLI：`codex-cli 0.144.3`，当前运行时报告模型为 `gpt-5.6-luna`；
- 12 条公开 fixture 的一次真实 Codex CLI 运行：最终成功率 100%、JSON/Schema 率 100%，P50/P95 均为 150,956 ms；
- 6/6 人工质量 claims grounded 且正确归因，严重归因错误和媒体臆测均为 0；
- 120 秒窗口出现超时，默认窗口已调整为 240 秒；
- `chunk-size 500` 和前一轮 `chunk-size 250` 的 500 条真实运行首个 chunk 均在约 240 秒超时；2026-07-17 重跑 `chunk-size 250` 时首个 chunk 约 77 秒成功，第二个 chunk 三次均在约 240 秒超时，最终成功率 50%，进程组均正常回收；因此 250 仍不是安全配置，当前建议降至 `chunk-size 100` 或更小；
- 2026-07-18 使用 `chunk-size 100` 完成 500 条 synthetic capacity run：5/5 chunk 首次及最终成功，0 次重试，JSON/Schema 率 100%，P50/P95 为 123,354/157,740 ms，进程退出码均为 0；该结果支持 100 作为当前容量候选，但重复运行稳定性、业务质量和生产边界仍未验证；
- 在不复用 Codex 会话的前提下增加最多 2 并发：公开小 fixture smoke 为 4/4 成功、批次耗时 39,884 ms、`max_active_requests=2`；500 条 `chunk-size 100` synthetic run 为 5/5 成功、0 次重试、批次墙钟 321,965 ms、P50/P95 为 127,935/129,800 ms，较串行请求延迟总和 645,827 ms 约快 2.006x；该证据只支持容量吞吐改善，不支持业务质量或生产限流结论；
- 追加一次 5 并发探针：500 条 `chunk-size 100` synthetic run 为 5/5 成功、0 次重试、批次墙钟 129,814 ms、P50/P95 为 112,947/129,807 ms，较串行约快 4.975x、较 2 并发约快 2.480x；该结果只有一次运行，暂不把 5 并发列为安全或生产配置；
- 5 并发重复验证已执行两轮：Repeat-1 通过；Repeat-2 有 1 个 chunk 在 240,018 ms timeout 后重试成功，最终成功率 100% 但首次成功率 80%、重试数 1；按门槛停止 Repeat-3 和 1000 条测试，5 并发稳定性仍未验证；
- 在接受“最多 3 次尝试内恢复成功属于可恢复事件”的增量口径后，完成 1000 条、`chunk-size 100` 的单轮容量对比：5 并发为 10/10 最终成功、0 重试、JSON/Schema 率 100%、P50/P95 为 119,898/129,648 ms、批次墙钟 253,921 ms；10 并发为 10/10 最终成功、0 重试、JSON/Schema 率 100%、P50/P95 为 123,711/132,231 ms、批次墙钟 132,241 ms；实际最大并发分别为 5 和 10，evidence 均完整，按增量 Spec 两档均为 `capacity_probe_pass`，但只代表单轮 synthetic 容量证据；
- 完整验证追加 1000 条 c100 重复运行：5 并发三轮批次墙钟为 253,921/304,162/264,062 ms，10 并发三轮为 132,241/139,351/144,374 ms；六轮均 10/10 最终成功、首次成功率和 JSON/Schema 率均为 100%、重试数均为 0、实际最大并发符合配置，容量重复稳定性通过；
- 完整验证的首轮公开 fixture 质量运行曾为 5/6 covered/grounded，缺口是 `public-008` 没有来源链路；该缺口随后按已批准的方案 1 修复：新增必填 `media_source_message_ids`，由 Schema 校验当前 chunk 的全部未解析媒体 ID，评估器使用该字段判断 grounding；确定性回归为 46/46 通过；
- 修复后的新鲜公开质量 evidence：`/private/tmp/invest-hub-spike-02-evidence/codex-public-small-media-linkage-20260718-luna`。1/1 chunk 首次及最终成功，JSON/Schema 率 100%，请求数 1、重试数 0、P50/P95 为 46,938/46,938 ms；Codex CLI 运行时报告模型为 `gpt-5.6-luna`；`public-008` 出现在 `media_source_message_ids`，6/6 claims covered、grounded、correct attribution，严重归因错误 0，媒体臆测 0；
- 综合结论：Spike-02 为**有条件通过**。1000 条、chunk size 100 的 5/10 并发各 3 轮容量重复稳定性通过，质量门槛也通过；但此前 500 条、chunk size 100 的 5 个并发请求 Repeat-2 曾出现一次可恢复 timeout/retry，且 chunk size 250/500 已实测不稳定。因此，未来生产试运行的初始候选配置为 chunk size 100、5 个并发请求；10 个并发请求暂作为后续扩容候选，不把 Codex CLI 写成最终生产 Provider；
- Codex timeout 清理回归测试、EvidenceStore 并发写入保护和 runner 并发/重试隔离测试已加入，完整确定性测试为 46/46；
- 脱敏决策报告：[Spike-02 决策报告](spikes/2026-07-15-spike-02-decision-report.md)。

小批次成功不等同于容量通过，也不批准 V0/V1 生产实现或自动 fallback。

## V0 result

- 确定性验收：通过。控制面 30 个测试、Worker 46 个测试、Spike-01 回归 35 个测试、V0 E2E 8 个测试和 Supabase pgTAP 55 条断言均通过。
- 持久化收据：通过。Worker 必须先写入远程持久化收据；结果中的消息计数和结构化运行 ID 与收据不一致、或只有伪造的 `persisted` 标记时，数据库拒绝推进 checkpoint。
- 隔离远程部署：核心链路通过。已将第 002 号迁移应用至隔离 Supabase，最新 Vercel 预览为 Ready；通过受保护部署通道完成合成注册 → 心跳 → 领取 → 持久化 → 回报结果，并确认回执与检查点已落库。
- 安全与恢复：通过。邀请码单次消费、普通用户 403、lease 竞争、raw/Canonical/structured 持久化失败、Provider timeout、媒体来源精确链路和 checkpoint 不前移均有证据。
- 管理调试面：通过。状态区分 `no_new_data`、`retryable_failed`、`failed`、`succeeded_with_unresolved`、`succeeded`；Credential、Prompt、Profile reference 和完整模型响应不进入调试视图。
- 真实页面：通过。用户明确授权的专用浏览器配置档在第 2 次尝试完成一页真实 Discord 采集、Codex 结构化、远程持久化、证据关联和安全检查点回报；第 1 次超时被保留为可恢复失败。该证据只覆盖有界单页，不外推为历史回填或持续运营能力。
- 远程部署：通过。核心工作节点 HTTP、普通用户管理员阻断和租约/检查点恢复均已验收；不含真实 Discord 内容。

完整证据见 [V0 Engineering Journal](engineering-journal/2026-07-18-v0.md) 和 [V0 Final Report](spikes/2026-07-18-v0-decision-report.md)。

## V1 result

- 确定性实现：通过。多来源绑定/规则、有限分页、批次与日累计摘要、收据闭环、正式阅读页、定时窗口幂等和公开 fixture E2E 已完成。
- 本地验证：通过。6 个 pgTAP 文件共 115 条断言、控制面 54 个测试、Worker 62 个测试、V1 E2E 3 个测试和 V0 E2E 8 个测试均通过；脱敏检查通过。
- 发布结论：通过。专用 V1 部署、真实双来源 history/增量/checkpoint、失败隔离/正式恢复、普通用户真实阅读与视觉、两来源质量抽检及部署日志独立审阅均已完成；V1 Discord 正式可用 MVP 已达成。

完整证据见 [V1 Engineering Journal](engineering-journal/2026-07-19-v1.md) 和 [V1 Final Report](spikes/2026-07-19-v1-decision-report.md)。

## Next gate

V1 MVP 退出门槛已通过。V1.1 的 Task 1–7、Task 8 本地确定性验收、远程 migration、控制面部署和双来源初始 coverage 已完成。此时仍不能将 V1.1 标记为“已验收”或“正式可用”：尚缺管理员重点作者选择后的真实 Discord 正常窗口与手动范围验收、作者配置生效、普通用户真实页面审阅和明确 label/config 的 launchd 安装。每项真实或外部状态变更都必须在授权后按 Plan 的顺序执行并记录。V2 X Spec 与 Plan 均已批准；本地实现与公开 fixture 验收已完成，但已授权的最小真实 X Go/No-Go 因 OpenCLI 合同字段不足而为 No-Go，故不得继续真实采集、创建云端任务、推进水位、远程 migration 或部署。媒体/OCR/外部正文解析、独立用户来源、自动 fallback 或其他长期稳定性工作仍须分别完成 Spec/Plan 批准；本次结论不构成生产 SLA。

**V2 当前状态更正（2026-07-26）：** 上述 X Go/No-Go 为早期历史记录。此后已采用受控本地 Collection runtime，完成生产持久化闭环并由 `com.investhub.x-worker` 实际自动完成首个窗口；持续自动增量已启用。真实引用/回复/转发类别与可恢复失败恢复仍未完整覆盖，故 V2 保持受控生产试运行，而非正式 SLA。
