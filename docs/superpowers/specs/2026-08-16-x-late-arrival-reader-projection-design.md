# X 迟到采集结果 Reader 投影设计 Spec

## 状态

- 状态：已批准设计，待实现计划与单独实现授权
- 日期：2026-08-16
- 关联设计：`docs/superpowers/specs/2026-08-16-x-minimal-nonresident-scheduling-design.md`
- 关联实现：`docs/superpowers/plans/2026-08-16-x-failed-window-skip.md`

## 1. 背景与问题

X Worker 恢复后会按每个来源的连续 coverage 水位自然追赶。历史窗口可能已经超过原定结算截止时间，或者某个来源仍停留在更早的窗口；这会让批次的跨博主日报保持 `partial`，并把来源标记为未纳入。之后某个窗口如果仍然真实采集成功并持久化，当前 Reader 不能稳定地把这部分成功内容作为对应日期的博主观点展示出来。

本 Spec 只解决“真实成功的迟到采集结果可阅读”这一投影问题。它不把历史日报改写成按时完成，不重新生成跨博主日报，也不删除连续 coverage 保护。

## 2. 目标

1. Worker 在本 Spec 开发和发布期间继续运行，不要求为开发而停止当前采集。
2. 已真实持久化的 X 窗口 segment，即使其批次来源在截止时被排除，也能在对应上海自然日期的 Reader 中展示。
3. Reader 明确标记该来源的内容为“后补采集”，同时继续显示仍然存在的 gap 或不完整覆盖。
4. 原有跨博主日报、日报 revision、失败任务、attempt 和 gap 事实保持不变；本 Spec 不触发 Provider 或日报重算。
5. 普通成功采集、迟到成功采集、仅有 gap、尚无 segment 四种情况都能被确定性区分并测试。

## 3. 非目标与明确不做

- 不删除或放宽 `source_behind_cutoff` 的连续窗口调度约束。
- 不允许 coverage 水位跨过尚未成功或尚未明确登记 gap 的窗口。
- 不把原失败任务改成 `succeeded`，不删除或关闭既有 gap。
- 不为旧失败窗口自动创建历史恢复任务，不执行历史 gap 转换。
- 不重新打开已结算 batch，不修改原有日报内容或其 `partial` 语义。
- 不重新调用跨博主判断 Provider，不新增日报流水线、队列、监控平台或第二套 scheduler。
- 不展示原始异常、Provider 输出、凭据、任务 ID 或内部排除字段。

## 4. 产品行为

### 4.1 正常成功窗口

正常窗口成功并形成 segment 时，Reader 保持当前展示方式，不显示“后补采集”。跨博主日报仍按既有 batch settlement 和 judgement version 展示。

### 4.2 迟到但成功窗口

如果窗口任务最终真实成功，且已持久化一个或多个经过现有安全校验的 `x_daily_viewpoint_segments`，Reader 必须按 segment 的 `natural_date` 展示这些博主观点，即使对应 batch source 在结算时是 `excluded`，或任务完成时间晚于该批次结算截止时间。

该博主卡片显示一条安全状态文案：

> 后补采集：该内容在当日判断结算后完成采集，未纳入原跨博主日报。

这条文案只说明展示边界，不暗示内容完整，也不改变原日报。若该日期仍有 gap，继续显示缺失的上海时间范围。

### 4.3 只有 gap、没有成功 segment

如果某来源某日期只有 gap 而没有成功 segment，Reader 只显示现有“采集缺失：`<上海时间范围>`”提示，不生成博主观点卡片，不伪造任何内容。

### 4.4 没有 segment 也没有 gap

如果某来源没有任何成功 segment 且没有 gap，Reader 沿用现有无可展示内容或批次状态，不把排队、处理中或未纳入状态转换成成功观点。

### 4.5 跨博主日报

迟到 segment 不进入原跨博主日报，不触发新的 Provider 调用，不生成新的日报 revision。原日报可以继续显示 `partial`、未纳入来源数和既有缺失说明。

## 5. 核心不变量

### 5.1 事实不可变

- 原任务和 attempts 的成功/失败事实不变。
- 原 gap 账本不可变；迟到结果展示不等于 gap 被转换为成功。
- 原 batch、batch source settlement status、日报版本和 coverage 语义不因 Reader 投影而回写。

### 5.2 连续 coverage 不变

调度器仍按来源逐窗推进。Reader 可以展示已经存在的实际 segment，但不能据此推进 `coverage_through_at`，也不能让后续窗口绕过尚未处理的前置窗口。

### 5.3 证据边界不变

只有通过现有 Worker 持久化回执、segment 与 evidence 关联校验的内容才能展示。任务排队、任务成功回报但未持久化确认、Provider 返回但未写入 segment 的内容均不可展示。

### 5.4 来源隔离

一个来源迟到或失败只影响该来源的 Reader 卡片和覆盖提示；其他来源的成功 segment、日报和窗口状态不受影响。

## 6. 最小实现设计

### 6.1 Worker 与数据库

本 Spec 不修改 Worker 采集协议、重试上限、gap 事务或 coverage transition。Worker 可以继续运行，现有任务按当前规则完成；成功 segment 仍使用现有持久化路径。

本 Spec 优先复用现有 `x_daily_viewpoint_segments`、`x_collection_batches`、`x_collection_batch_sources` 和 `x_collection_gaps`。除非实现验证证明无法安全识别迟到状态，不新增迟到账本或生产表。

### 6.2 安全 Reader 投影

Control Plane Reader 服务端在构造 `XReaderDate` 时：

1. 按现有权限和来源筛选读取有效 segment、batch source 与 gap；
2. 不再因为 batch source 是 `excluded` 就丢弃一个已经存在且校验通过的 segment；
3. 对每个博主日期卡片计算安全的 `lateArrival` 标记：segment 已存在，且其对应采集窗口的 batch source 在结算时被排除，或 segment 持久化时间晚于该批次结算截止时间；
4. 只向 Reader DTO 暴露 `lateArrival: boolean` 和现有 gap 时间范围，不暴露内部排除代码、原始错误或任务身份；
5. 保持现有日期、博主筛选和无内容文案语义。

如果既有数据无法为某个 segment 建立可靠的批次截止时间关联，默认 `lateArrival = false`，但仍可展示该真实 segment；不得根据不完整关联猜测“后补采集”。

### 6.3 UI

在对应博主卡片中增加简短、稳定的状态提示“后补采集：该内容未纳入原跨博主日报”。提示必须与“覆盖不完整”和具体 gap 范围同时可见，不能覆盖或替换已有内容。

## 7. 兼容发布与运行策略

### 7.1 开发期间

- 不停止当前生产 Worker。
- 本地只在隔离 worktree 修改和测试。
- 生产中的旧 Worker 与旧 Control Plane 继续按旧语义运行；在新版本发布前，迟到结果仍可能只保留在数据库而不显示。

### 7.2 发布顺序

1. 先完成本地 RED/GREEN、全量回归、独立复核和 release handoff。
2. 采用只读兼容的 Control Plane 发布；不需要远程 migration 时，不执行 migration。
3. 发布后用现有生产数据只读验证：至少覆盖一个已有迟到成功 segment、一个仍有 gap 的来源和一个正常成功来源。
4. 不为验证而重跑采集、不手工入队、不修改生产 batch/gap/coverage。

如果实现最终证明必须新增数据库字段或索引，必须回到本 Spec/Plan 增补 additive migration、回滚边界和单独 Release Authorization；不能在实现阶段临时扩大范围。

### 7.3 旧数据行为

已经成功并持久化的迟到 segment，发布新 Reader 后应能被投影展示。仅有失败任务、仅有排队任务或没有 segment 的旧窗口，不会因发布而自动产生内容。

## 8. 验收标准

1. 正常成功 segment 继续展示，`lateArrival` 为 false。
2. 已持久化且对应批次已排除的 segment 展示在正确上海自然日期，并显示“后补采集”。
3. 迟到 segment 同时存在 gap 时，两者都展示；gap 时间范围准确，不能被成功 segment 清除或覆盖。
4. 只有 gap 没有 segment 时，不出现虚构博主观点。
5. 任务仍在 queued/running、没有 segment 时，不出现成功内容。
6. 跨博主日报的原有 revision、coverage status 和文本不发生变化，不调用 Provider。
7. 日期筛选、博主筛选和“全部博主”视图均遵守上述规则。
8. 一个来源的迟到结果不会改变其他来源的卡片和日报输入。
9. 现有数据库、Worker、Control Plane 全量测试继续通过；新增 Reader/Repository 回归覆盖上述矩阵。
10. 独立复核确认无 Critical/Important finding，且 diff、redaction 和 production build gate 通过。

## 9. 风险与保留意见

- 当前生产数据中并非每个“任务成功”都代表已经生成可读 segment；Reader 只能展示实际持久化的 segment。
- 迟到 segment 的批次关联如果缺失，系统宁可不显示“后补采集”标签，也不能错误推断时间语义。
- 本 Spec 只改善可见性，不提高 X Provider、浏览器登录态或 Worker 本身的成功率；采集失败仍会以 gap/partial 方式呈现。
- 如果未来要求迟到内容重新进入跨博主日报，需要另行创建 Spec/Plan，不能在本方案中隐式扩展。
