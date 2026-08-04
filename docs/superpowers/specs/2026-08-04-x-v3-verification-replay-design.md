# X v3 生产验证恢复链设计

## 目标

回刷 2026-08-03 两个已终态失败的 X 当日判断窗口，而不重新访问 X、也不新增或修改任何线上定时任务。恢复使用各自冻结批次中全部 `included` 来源的已持久化事实，依次执行 v3 单帖分析、v3 单博主窗口汇总与 v3 跨博主当日判断，并将结果安全投影到正式 `/x` Reader。

## 已确认事实

两个批次的每日判断均在旧 Worker 的 v3 输出 / v2 context 协议不匹配后终态失败；旧运行记录只保留了泛化失败分类，因此不能用分类字段替代该因果事实。各自位于 `included` 的来源只有 v2 单博主窗口结果；因此现有 `claim_next_x_daily_judgement` 无法直接重试。失败 run、v2 单帖分析、v2 segment、原 batch 和既有定时任务都不可变，也不得被更新、删除或标记为成功。

现有手动 X refresh 只创建单来源采集 range，不能形成 daily batch；直接使用它既会重新访问 X，也不能稳定验证跨博主每日判断。因此它不适用于本次验证。

## 决策

新增一条严格一次性的 `x_v3_verification_replay` 数据链，并使用现有 Worker checkout 的显式一次性命令执行；不让 `run-scheduled`、`ensure_due_x_collection_batches` 或任何新的 launchd/cron 路径领取它。该链以原 batch 为只读 seed，但拥有独立的 replay、source snapshot、v3 segment 和 daily version 行。

### 数据模型

1. `x_v3_verification_replays`：记录 `source_batch_id`、唯一 `replay_key`、`status`（`queued | running | succeeded | failed`）、创建者、开始/完成时间和安全的 failure class。`source_batch_id` 只能指向终态 `judgement_failed` 批次；每个 source batch 至多一条 replay。
2. `x_v3_verification_replay_sources`：在创建 replay 的事务中冻结原 batch 的全部 `included` 来源、原 range task、原 v2 segment 和该 range 的 canonical post 集合。它不接受排除来源、手工 post ID 或后续来源变更。
3. `x_v3_verification_segments`：保存每个冻结来源的 v3 window output、`post_analysis_refs`、`evidence_refs`、schema/prompt version 和发生时段。它不复用 `x_daily_viewpoint_segments`，从而不违反同一 source/date/range 的 v2 不可变唯一约束。
4. `x_v3_verification_versions`：保存唯一的 v3 cross-blogger output 与基于 replay sources/segments 构造的冻结 input snapshot。它不写入 `x_daily_judgement_versions`，因此不会改变原 batch 状态或历史 daily judgement 版本序列。

v3 单帖结果仍写入既有 `x_post_analyses` 的 `analysis_version = 2`，因为它们是同一 canonical post 的新、不可变版本化分析；写入在 replay 完成事务中发生，冲突即整体失败。所有新行带现有的 v3 schema/prompt version，且不更新 v2 行。

### 执行接口

管理员专用 `create_x_v3_verification_replay(source_batch_id, requested_by)` 只允许终态 `judgement_failed` 批次、当前管理员和一次创建。本次生产执行只传入已核验的两条 2026-08-03 批次 ID；接口本身不扫描、创建或重试任何其他批次。它在单一事务中冻结 source snapshot，返回 opaque replay ID；数据库拒绝任意普通用户、非终态失败 batch、重复 replay 和无 v2 输入的请求。

Worker 新增显式一次性命令 `run-x-v3-verification --replay-id <opaque id>`。该命令先原子 claim replay，再通过 service-role RPC 获得冻结的 canonical post/context 输入；逐帖调用公开 `v3_x_post_analysis.md`，按来源调用 `v3_x_window.md`，最后调用 `v3_x_cross_blogger.md`。任一 parser、Provider 或数据库契约失败时，只把 replay 标为 `failed` 并记录枚举 failure class；不启动 OpenCLI、浏览器、采集或普通 scheduler。

完成 RPC 必须在一个事务内验证：全部冻结帖子恰有一个 `@2` 分析；每个来源恰有一个 v3 segment；segment 与 daily 输出的 analysis/evidence 集合精确归属；daily 输出只引用 replay 内 source/segment；并在通过后插入 v3 分析、segments 与 daily version。失败时不得留下部分 v3 segment、daily version 或网页投影。

### Reader 投影

`/x` 在读取原定时 batch 时，再查询与该 batch 关联且 `succeeded` 的 verification replay。若存在，原有“判断失败”状态保留，紧随其后展示一个明确标记为“验证恢复（非定时任务）”的 v3 当日判断；单博主区展示 replay v3 segment 的三类观点和安全逐帖投影。它不覆盖、隐藏或重排原 v2 segment，也不泄露 replay/task/analysis/evidence ID、Prompt、原始正文或 Provider telemetry。

## 非范围

- 不创建、暂停、重启或改变 launchd、cron、正常窗口频率和已存在的 `run-scheduled` 行为。
- 不调用 OpenCLI、不读取浏览器 Cookie/Profile、不重新采集 X，也不为排除来源补写内容。
- 不修改任何既有 batch、run、version、v2/v3 历史行、coverage 或 checkpoint。
- 不把验证结果伪装为 08:00 定时判断成功；UI 必须保留验证性质。

## 验收标准

1. 数据库测试覆盖 actor/source-batch gate、一次性 claim、冻结来源/帖子完整性、任一错误的原子失败、v2 不变和 v3 证据归属。
2. Worker 测试证明一次性命令不导入 OpenCLI/Browser、不调用 scheduler，并严格按 post → window → daily 的 v3 contracts 运行。
3. Reader 测试证明失败定时卡仍可见、成功 verification 卡带非定时标识、三层 v3 信息可读且无内部字段泄露。
4. 生产执行只对两条经核验的 2026-08-03 批次各运行一次显式恢复命令；随后以只读 SQL 和已认证 `/x` 验证 replay 成功、原失败记录仍在、结果可读且不新增任何定时任务。

## 回滚与故障处置

数据库采用追加 migration，不执行 destructive rollback。若一次性运行失败，replay 保留 `failed` 及枚举原因；不自动重试、不回写原 08:00 批次、不触发正常 scheduler。若发现安全投影或契约错误，停止该显式命令、回退 Worker/Reader 代码，保留所有不可变审计事实。
