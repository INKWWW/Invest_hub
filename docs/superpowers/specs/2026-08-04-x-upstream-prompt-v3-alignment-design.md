# X 单帖与单博主窗口 Prompt v3 对齐设计

## 目标

将 X 信息链路的单帖分析和单博主窗口汇总从 v2 升级为与已发布跨博主当日判断一致的 v3 合同，使一条新的当日判断只消费 v3 单帖事实与 v3 单博主窗口观点。新旧结果并存、证据关系可追溯；不得改写、伪造或重新解释任何历史 v2 记录。

## 已确认事实

当前 X 采集 Runtime 仍读取 `v2_x_chunk.md` 与 `v2_x_window.md`，分别经 `parse_v2_x_chunk_output`、`parse_v2_x_window_output` 验证后，写入 `x_post_analyses.analysis_version = 1` 和 `x_daily_viewpoint_segments.window_viewpoints`。已发布的跨博主 Runtime 虽然使用 `v3-x-cross-blogger-1` 和三类 v3 judgement 输出，但其数据库 context 仍由这些 v2 单帖和窗口字段构造。因此现状并不是三份 Prompt 均已端到端对齐的 v3 证据链。

`x_post_analyses` 与 `x_daily_viewpoint_segments` 均由不可变触发器保护。它们不能原地替换历史内容；同一帖子的新分析必须作为新的 `analysis_version` 保存，新的采集任务则保留自身的独立窗口 segment。当前跨博主 context、证据权威校验和 Reader 都读取 v2 平铺字段，Reader 还强制读取 `analysis_version = 1`。

## 范围

1. 将公开、可版本化的 Prompt 新增为 `v3_x_post_analysis.md` 和 `v3_x_window.md`；保留 v2 Prompt 文件供历史合同与回退的在途任务使用。
2. 为单帖与单博主窗口新增严格 v3 structured parser、Runtime 调用路径和本地 failure 分类；新建 X 采集窗口默认只生成 v3 上游结果。
3. 在现有不可变表上增加 v3 输出及其 schema/prompt version 的持久化字段，并以新的 `analysis_version = 2` 保存每个 v3 单帖分析。不得更新或删除 v2 行。
4. 扩展 range completion、跨博主 judgement context 与权威校验，使 v3 当日判断仅基于同一冻结 batch 中 v3 segment 与 v3 analysis 的直接证据构造。
5. 更新 Reader 的安全投影和 `/x` 展示：单博主窗口按三类栏目展示；逐帖记录展示 v3 归因、行动倾向、范围、条件、论据、不确定性和原帖链接。v2 历史继续按当前布局投影。
6. 补齐数据库、Worker、控制面及组件测试，完成 migration、控制面部署、Worker reload 和已认证生产 `/x` 只读验收。

## 非范围

- 不更改 X 采集、来源配置、OpenCLI 合同、checkpoint、批次结算、调度频率或真实历史数据。
- 不重采集历史帖子，不为历史 v2 segment 或 judgement 补写 v3 内容，不手工创建 Provider 输入、任务、batch 或 judgement。
- 不引入系统交易建议、价格目标、仓位、止损或任何不由博主明确表达的行动倾向。
- 不引入新的数据表或第二套 Reader；本次以现有不可变事实链的增量版本字段完成升级。

## v3 合同

### 单帖分析

Prompt version 为 `v3-x-post-analysis-1`，输出 schema 为 `v3-x-post-analysis`。每个输入帖子必须且只能产生一条分析：

```json
{
  "schema_version": "v3-x-post-analysis",
  "analyses": [{
    "post_id": "输入 post.id",
    "investment_relevance": "investment_related | not_investment_related",
    "investment_categories": ["security_industry | market_structure | strategy_mindset"],
    "blogger_viewpoint": "string | null",
    "action_intent": "build_position | buy | add | hold | reduce | sell | watch | avoid | none",
    "action_scope": "string",
    "conditions": ["string"],
    "arguments": ["string"],
    "quoted_post_viewpoint": "string | null",
    "uncertainties": ["string"],
    "evidence_post_ids": ["post id"],
    "post_link": "https URL"
  }]
}
```

`evidence_post_ids` 必须包含本帖，只能额外引用该帖显式提供的 context post。无博主文字的 repost 不能把转帖内容归因于博主。非投资相关帖必须输出空类别、空条件/论据/不确定性、`blogger_viewpoint = null`、`quoted_post_viewpoint = null`、`action_intent = none` 和空 `action_scope`。只有博主明确表达行动倾向时才可使用非 `none` 枚举，且其范围必须非空。

### 单博主窗口汇总

Prompt version 为 `v3-x-window-1`，输出 schema 为 `v3-x-window`：

```json
{
  "schema_version": "v3-x-window",
  "natural_date": "YYYY-MM-DD",
  "range_task_id": "task id",
  "occurred_from_at": "RFC3339 instant",
  "occurred_through_at": "RFC3339 instant",
  "security_industry_viewpoints": ["v3 window item"],
  "market_structure_viewpoints": ["v3 window item"],
  "strategy_mindset_viewpoints": ["v3 window item"],
  "analysis_ids": ["all input analysis ids"],
  "evidence_post_ids": ["all input evidence ids"],
  "uncertainties": ["string"]
}
```

三类数组中的每个 `v3 window item` 恰有 `statement`、`action_intent`、`action_scope`、`conditions`、`analysis_ids`、`evidence_post_ids` 与 `uncertainties`。它必须有至少一个直接分析和帖子证据；`analysis_ids` 仅能指向当前窗口输入的 v3 分析，`evidence_post_ids` 必须是这些分析的真实证据并与之精确对应。顶层 `analysis_ids` 与 `evidence_post_ids` 必须分别完整覆盖当前窗口所有输入 v3 分析及其证据。单博主窗口不得使用跨来源共识措辞。

### 跨博主当日判断输入

`v3_x_cross_blogger.md` 保持输出合同 `v3-x-cross-blogger` 和 Prompt version `v3-x-cross-blogger-1`，但输入说明与数据库 context 同步升级：每个 `window_segment` 必须包含 v3 schema/prompt version、三类窗口观点、窗口覆盖 ID 与完整 v3 单帖分析。它只能引用同一冻结 batch 中 `settlement_status = included` 的来源及其 v3 analysis/证据；`excluded_sources` 和无新增来源仍仅能用于覆盖限制说明。

跨博主输出中的 `analysis_ids` 继续采用 `post_id@analysis_version`。新 v3 结果因此使用 `@2`，并由数据库以实际 `post_analysis_refs` 和 `evidence_refs` 验证来源归属、证据精确集合、自然语言不泄露内部 ID、行动倾向/范围一致性及强共识条件。任何 v2 segment、v2 analysis、未知 schema/prompt version、缺字段、跨帖证据或不安全 telemetry 均 fail closed，分类为 `schema_error`，不得调用完成接口或持久化部分结果。

## 不可变持久化与兼容性

在 `x_post_analyses` 增加 `schema_version`、`prompt_version` 与 `analysis_output jsonb`；在 `x_daily_viewpoint_segments` 增加 `schema_version`、`prompt_version` 与 `segment_output jsonb`。新增字段必须带类型与 JSON shape 约束，并延续既有 RLS、immutability 与 source/task 约束。历史 v2 行明确标记为其原有 v2 version，新增 v3 行标记为上述 v3 schema/prompt version。

v3 单帖持久化使用 `analysis_version = 2`。为保持旧数据库边界与证据索引可用，行中既有 `blogger_viewpoint`、`arguments`、`quoted_post_viewpoint`、`uncertainties`、`evidence_refs` 由已验证的 v3 单帖输出进行无损投影；v3 特有字段以 `analysis_output` 作为权威表示。v3 窗口同样以 `segment_output` 作为权威表示；既有 `window_viewpoints` 只保留与旧列约束兼容的空数组，不能作为 v3 阅读或 v3 当日判断输入。

range completion 根据 payload 的精确 v2/v3 合同分派到各自的验证与持久化路径。v2 仍可完成已在途任务；新的 Runtime 只提交 v3。重复的同一 `(canonical_message_id, 2)` 或同一 range task 必须仅在内容完全相同的情况下幂等成功，内容不同则报冲突；不得以更新覆盖。

## Reader 投影

Reader 查询须按每个 segment 的 `post_analysis_refs` 精确读取相同 `analysis_version`，不得再固定为 version 1。v3 segment 的三类窗口观点以独立标题和卡片展示，每项展示 statement、博主明确行动倾向（仅非 `none`）、范围、条件及不确定性；随后展示对应逐帖事实。v2 segment 保持当前 `window_viewpoints` 与旧逐帖字段展示，不添加虚构的第三类栏目或行动倾向。

页面层级保持 `日期 → 当日判断总结（每个采集窗口、最新优先）→ 单个博主观点（博主分块、窗口最新优先）`；博主/日期筛选行为不变。所有浏览器可见数据仍是 Reader-safe 投影，绝不下发原始正文、Prompt、Cookie、本机路径、内部任务/批次/segment/analysis ID 或 provider telemetry。

## 测试与验收

1. Worker parser/Runtime 测试先证明 v3 单帖与窗口 payload 在实现前失败；实现后验证精确字段、相关性 gate、repost 归因、行动倾向与范围、条件、每帖证据边界、窗口全覆盖、三类输出、未知字段和注入式不安全文本拒绝。
2. 数据库 pgTAP 测试证明 v3 行以 version 2 不可变插入，v2 行不变；错误 schema、prompt、analysis/evidence 关系、重复冲突、无效 v3 window 与混用 v2 上游输入均被拒绝；v3 judgement context 和权威校验只接受同一 batch 的 v3 证据。
3. 控制面 repository/component 测试证明 v3 与 v2 同时安全显示、segment 使用引用的实际 version、三类单博主窗口卡片和最新窗口排序正确，且安全投影不泄露内部或原始数据。
4. 完整数据库、Worker、控制面回归、lint、production build、`git diff --check` 和 `bash scripts/v0/redact-check.sh` 必须通过。公开仓库只包含合成 fixture。
5. 生产发布按顺序执行：停领 X Worker → 对远端 migration history 做只读 dry-run → 应用一条新增 migration 并只读核验 → 推送并部署 control plane，确认 stable deployment Ready → 将 Worker 更新至同一 `main` 并 reload → 在已认证的 `/x` 进行只读结构与安全投影验收 → 仅等待正常 scheduler 产生首条真实 v3 上游到当日判断链路的额外证据。不得人为触发采集或 Provider。

## 发布与回滚

本次发布包含一条追加式 Supabase migration、control-plane deployment 与本机 `com.investhub.x-worker` reload。若 migration 未能完成或生产验证失败，保持 Worker 停领，回退 control-plane/Worker 至此前已验证提交；数据库不执行 destructive rollback，已插入的不可变 v3 记录保留。若正常 scheduler 发现 v3 上游 schema 拒绝，停止 Worker 的 X 领取并修复后以新的任务重试；不得删除、更新、回刷或伪造任何既有事实、segment、judgement 或 batch。
