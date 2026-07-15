# Spike-02：Codex CLI 容量与质量验证设计

## 文档状态

- 阶段：Discovery / Spike-02 设计修订
- 书面状态：待用户审阅
- 本文范围：只设计 Spike-02，不授权 V0/V1 生产实现
- 设计依据：`AGENTS.md`、`README.md`、`docs/project-status.md`、`docs/intake.md`
- 已确认范围：Codex CLI 真实评估、Mock 确定性对照；不直接调用 GLM 或其他外部模型 API

## 1. 目标与第一性原理

Spike-02 只回答一个问题：

> 在本机已登录的 Codex CLI 条件下，Codex 是否能以可接受的容量、稳定性和输出质量，处理 Invest Hub 后续批次总结所需的 Discord 结构化理解任务？

问题的本质不是“模型能否生成一段通顺文字”，而是一次本地 CLI 进程调用能否在输入规模增大、内容关系复杂和请求失败时，持续产出可校验、可追溯、不会错误归因的结构化结果。

本 Spike 验证：

1. 输入规模扩大后的进程调用次数、总耗时和失败率；
2. Codex 最终输出是否稳定解析为约定 Schema；
3. 关键事实、指定用户观点、标的和操作倾向是否准确归因；
4. 进程超时、非零退出、空输出、非法 JSON 和 Schema 错误是否可以局部恢复；
5. 未解析媒体或外部文章正文是否不会被臆测。

Spike 结果只作为后续 V0/V1 设计输入，不批准 Codex CLI 成为正式生产架构。

## 2. 范围

### 2.1 包含内容

Spike 使用本地验证 harness 和两类 Provider：

- Codex CLI：唯一真实 Provider，通过非交互 `codex exec` 运行；
- Mock Provider：确定性返回，用于验证统一契约、失败注入、局部重试和恢复逻辑。

验证覆盖：

- 小批次；
- 约 500 条消息；
- 1000 条以上消息；
- 多话题混合、指定用户短句、回复链和必要上下文；
- 中英文或其他多语言混合；
- JSON 输出与 Schema 校验；
- 进程超时、非零退出、空输出、非法 JSON、Schema 错误和局部重试；
- 事实依据、指定用户归因、标的和操作倾向；
- 调用次数、重试次数、进程 P50/P95 耗时和批次总耗时。

### 2.2 不包含内容

本 Spike 不包含：

- GLM、OpenAI 或其他外部模型 API 的直接调用；
- Codex CLI 自动 fallback 到其他 Provider；
- 生产 Provider、Worker、任务队列、数据库、认证和网页；
- 正式动态分块算法或最终 token 参数；
- Discord/X 采集、日累计总结和正式阅读页；
- 生产 Prompt 管理和历史摘要重算；
- 将 Spike harness 直接升级为生产代码。

## 3. 输入与标注

测试输入继续使用两类 fixture：

1. 脱敏真实 fixture：保留消息顺序、回复关系、语言特征、Ticker、价格和观点关系，只保存在本地受保护目录；
2. 人工构造公开 fixture：用于仓库内可重复的确定性测试，不包含真实来源信息。

每个 fixture 标记消息数量、语言、话题数量、指定用户短句、回复链、未解析媒体、标的、价格、操作倾向以及人工标注的关键事实和禁止归因。

没有人工标注的 fixture 可以用于容量测试，但不能用于质量结论。

最小测试矩阵仍为：小批次质量基线、约 500 条容量测试、1000 条以上容量测试；规模 fixture 不通过重复同一条消息制造质量结论。

## 4. 验证流程与 Codex CLI 边界

可观察验证链路：

```text
Fixture
  → 确定性预处理
  → 候选输入块
  → Codex CLI Provider 或 Mock Provider
  → JSON 解析与 Schema 校验
  → 必要时局部重试
  → 事实与归因评估
  → 指标和证据报告
```

确定性程序负责去重、排序、作者身份标记、回复关系保留、Ticker/价格/URL 提取以及输入范围记录。

传给 Codex 的每条输入行必须包含 message ID、author scope、author ID、message kind、时间、回复关系和正文，确保模型可以完成归因和未解析媒体判断。

Codex CLI Provider 每个 chunk 启动一次非交互进程，使用以下边界：

```text
codex exec
  --sandbox read-only
  --add-dir <CODEX_HOME>
  --ephemeral
  --output-last-message <temporary-file>
  -
```

- Prompt 通过 stdin 传递；
- 当前 Spike worktree 作为工作目录；
- Prompt 明确要求不使用工具、不读取项目文件、不执行项目命令、只返回 JSON；
- `--sandbox read-only` 作为文件修改防护；
- `--add-dir <CODEX_HOME>` 只允许 Codex 写入自身状态目录，解决 read-only sandbox 下状态库初始化问题；
- Codex CLI 不得修改 worktree；
- Codex 最终输出从 `output-last-message` 读取，再交给既有 JSON Parser 和 Schema Validator；
- `SPIKE02_CODEX_BIN` 可指定 CLI 路径，默认值为 `codex`；
- `SPIKE02_CODEX_MODEL` 可选，设置后通过 `--model` 传入；未设置时使用 Codex CLI 当前默认模型；
- 进程超时默认 240 秒，可由运行参数覆盖。实测本机 Codex CLI 在连接重试和退出清理后约 151 秒完成一次小批次请求，因此 120 秒不足以作为默认窗口；240 秒仍保持单进程有界等待；
- 不读取或写入 GLM endpoint、API key 或其他外部 Provider 配置。

Codex 输出至少需要能够表达：结构化话题、关键事实和观点类型、指定用户观点、标的和操作倾向、不确定性或未解析媒体标记以及原始消息 ID。

## 5. 失败、重试与恢复

每个进程调用分类为以下状态之一：

- `success`：退出码为 0、存在最终输出且后续 JSON/Schema 校验通过；
- `timeout`：超过进程超时时间；
- `provider_failed`：进程退出码非 0；
- `empty_response`：没有最终输出文件或输出为空；
- `invalid_json`：最终输出不是合法 JSON；
- `schema_error`：JSON 不符合 Spike Schema。

处理规则：

- 只重试失败 chunk，成功 chunk 不重复执行；
- 默认最多三次尝试，并使用有界退避；
- 超时后必须终止 Codex 子进程；
- 单个 chunk 最终失败时保留其他 chunk 的结果和失败证据；
- stdout/stderr 只作本地诊断，不作为业务输出；
- 不伪造 Codex 不提供的 token usage，缺失时记录为 `null`；
- JSON 解析和 Schema 校验继续使用现有确定性逻辑，不让 Codex 通过自由文本修复结构。

## 6. 指标与质量评估

每次运行至少记录：

- 输入消息数和 chunk 数；
- Codex 进程调用数、重试数和最终成功 chunk 数；
- 首次成功率和最终成功率；
- JSON 可解析率和 Schema 通过率；
- 进程总耗时 P50/P95；
- 批次总耗时；
- 退出码、超时、空输出、非法 JSON 和 Schema 错误数量；
- input/output token usage（Codex CLI 未提供时为 `null`）；
- 失败 chunk 是否可以独立恢复。

质量继续使用固定 fixture 和人工标注检查：

- 关键事实是否有原始消息依据；
- 核心观点是否被覆盖；
- 指定用户观点是否正确归因；
- 普通上下文是否被必要保留；
- Ticker、价格和操作倾向是否正确；
- 多语言和回复链是否发生事实丢失或错误合并；
- 是否引入输入中没有的结论；
- 未解析媒体是否被臆测。

严重错误归因和未解析媒体臆测仍属于阻断级错误。

初始判定门槛保持不变：首次成功率不低于 90%、有界重试后最终成功率不低于 99%、JSON 可解析率不低于 98%、核心事实有据率不低于 95%、严重错误归因为 0、未解析媒体臆测为 0。P95、批次总耗时和调用次数记录实际观测值，不预先写死绝对数值。

## 7. 通过结论

Spike 结束时只能得出：

- **通过**：阻断级质量门槛满足，三档规模均有可解释的容量和恢复结果；
- **有条件通过**：质量满足，但必须限定 Codex CLI 的进程超时、低并发、chunk 大小或本地运行条件；
- **不通过**：出现阻断级错误，或高消息量下无法获得可恢复、可追溯结果；
- **未验证**：本机 Codex CLI 登录、模型配置或运行稳定性不足，无法对关键指标作结论。

结论只适用于被记录的 Codex CLI 版本、模型配置、运行机器和 Prompt 版本，不直接批准云端 Worker 或其他生产运行方式。

## 8. 预期产物

Spike-02 后续至少形成：

- 本 Spec 对应的独立 implementation plan；
- 本地或公开 fixture 清单及脱敏说明；
- Mock Provider 确定性测试结果；
- Codex CLI 各规模运行 evidence；
- 指标汇总和质量人工评估表；
- Spike-02 decision report，包含 Codex CLI 版本、模型配置、结论、限制、未决项和下一阶段建议。

## 9. 安全与阶段门禁

- Codex CLI 运行使用 `--sandbox read-only` 和 `--ephemeral`；
- 真实 fixture、Prompt、完整 Codex 响应和历史数据只保存在本地受保护目录；
- API key、Cookie、Chrome Profile、私有 URL 和真实历史数据不得进入 Git；
- 公开仓库只允许人工构造的公开 fixture 和不含敏感信息的测试结果；
- 本阶段不安装生产依赖、不初始化应用框架、不创建云端资源；
- 在修订后的 Spec 和 implementation plan 获得批准前，不开始 Spike-02 实现；
- 本 Spec 不批准 Codex CLI 作为正式生产 Provider，也不批准任何自动 fallback。
