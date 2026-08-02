# X 当日判断延迟结算宽限期设计

**状态：** 已批准（用户于 2026-08-03 授权全流程执行）

## 背景与问题

X Worker 运行在本机。电脑休眠或关机时，已到期窗口只能在设备恢复后补跑。当前每个批次的结算截止固定为该窗口结束后两小时；若 Worker 在此后恢复，来源会被不可变地标记为 `settlement_deadline_exceeded`。当没有任何来源被纳入时，系统安全地写入空的 partial judgement version，因此 Reader 会出现“已更新 / 本窗口没有形成新的跨博主判断”，但实际含义是未曾调用模型。

本次修复的目标是在不降低事实完整性要求的前提下，为当日内的本机恢复留出确定的补采空间，并让 Reader 清楚地区分“没有可判断的新信息”和“采集超时而未生成判断”。

## 决策

由正常 X 调度器新建的 collection batch，其 `settlement_deadline_at` 固定为上海 `natural_date` 的次日 01:00。上海次日 00:00 cutoff 仍归属于前一天，因此它与同一自然日的 08:00、12:00、16:00、20:00 窗口共享同一个 01:00 截止。批次在这个截止前只要完成既有的 posts、逐帖分析、日观点段和持久化收据，就按原有规则纳入 judgement；截止后仍未满足的来源才标记为 `settlement_deadline_exceeded`。

已有 batch、source settlement、judgement version、run、coverage 与 checkpoint 全部保持不可变。已经在旧两小时规则下结算的历史空记录不回填、不重写，也不触发模型。它们的事实输入已在当时冻结，事后塞入后续采集结果会破坏判断可追溯性。

## Reader 行为

Reader 对新旧数据均保持安全展示。当一个 judgement batch 的最新 version 为 partial、没有任何观点，且该 batch 存在 `settlement_deadline_exceeded` 来源时：

- 摘要折叠标题显示“采集超时，未形成判断”，而不是“已更新”；
- 摘要正文说明未纳入博主数量，并说明其中因采集未在结算截止前完成的数量；
- 对应博主卡显示“采集超时：本机未在结算时间前完成采集。”，而不是泛化的“覆盖不完整”。

其他 partial 原因（例如 `source_behind_cutoff`、`coverage_not_initialized`、terminal failure）继续沿用现有“覆盖不完整”安全提示，不把它们误称为超时。筛选、日期排序、博主分块、判断版本历史和原始内容回溯均不变。

## 数据与安全边界

新增一个数据库 helper，根据不可变的 `natural_date` 计算上海次日 01:00 的 timestamptz。调度器调用以 transaction-local 标记触发的 batch 插入时，将 helper 的结果写入既有的不可变 `settlement_deadline_at` 字段；手工或历史写入保持其显式值，不改表结构、RLS、RPC 权限、Worker 协议、OpenCLI 合同、Provider、Prompt 或来源配置。

只有已有 `settle_x_collection_batch` 仍可决定来源是否 included/no-new/excluded。宽限期不将失败、未初始化或落后来源变为成功，也不允许没有日观点段的成功任务进入模型。模型只会在至少一个来源实际 included 时被排队，保持现有证据校验和不可变 version 规则。

## 验收标准

1. 对任意当日 08:00、12:00、16:00、20:00 新 batch，`settlement_deadline_at` 均为上海次日 01:00；次日 00:00 cutoff 归属前一自然日，截止同样为该自然日后的 01:00。
2. 在次日 01:00 前完成并已持久化日观点段的来源会被 included，partial batch 创建 judgement run；在 01:00 或之后仍未完成的来源才获得 `settlement_deadline_exceeded`。
3. 无 included 来源的 batch 不创建 Provider run；已有空 version 的事实含义和 immutable 规则不变。
4. Reader 仅在实际存在超时排除原因时显示“采集超时，未形成判断”与对应博主说明；其他 partial 情形不改变文案。
5. 现有 X judgement、Reader、Worker、pgTAP 与脱敏回归保持通过；新增 migration 在空本地数据库可重放。

## 非目标

本次不实现云端常驻 Worker、唤醒休眠电脑、跨日无限补采、历史 batch 回填/再生成、来源排序变更、管理员操作入口、通知、监控或新的任务状态。它不构成无人值守 SLA；本机、X 登录态和 OpenCLI 仍是受控生产试运行的前提。
