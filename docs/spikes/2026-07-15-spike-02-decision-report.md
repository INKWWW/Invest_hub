# Spike-02 Codex CLI 容量与质量决策报告

## 报告状态

- 日期：2026-07-15；最近更新：2026-07-18
- 结论：**有条件通过（conditional pass）**
- 执行内容：本地确定性 harness、Mock 规模对照、Codex CLI 小批次真实运行、重复容量验证、人工质量复核和有界并发容量验证
- 真实 Provider：本机已登录的 Codex CLI；没有直接调用 GLM 或其他外部模型 API
- 本报告不批准 V0/V1 生产实现，也不批准自动 fallback

## 1. 范围与安全边界

本次执行只使用人工构造公开 fixture。Codex CLI 通过非交互 `codex exec` 调用，使用 `--sandbox read-only`、`--ephemeral` 和 `--output-last-message`；仅通过 `--add-dir <CODEX_HOME>` 允许其维护自身状态，项目 worktree 不允许修改。

完整 Prompt、Codex 响应和诊断只保存在本地受保护 evidence 目录，不进入 Git。`requests.jsonl` 不保存 Prompt 正文；token usage 在 Codex CLI 未提供时记录为 `null`。

## 2. 确定性验证结果

- 确定性测试：46/46 通过；
- Mock 小批次、约 500 条和 1000 条规模路径保持可运行；
- Mock 的规模结果只证明 harness 的 chunk、重试、Schema 和 evidence 流程，不代表 Codex CLI 的容量或质量。

## 3. Codex CLI 环境

- CLI：`codex-cli 0.144.3`；
- 运行时报告模型：`gpt-5.6-luna`；
- Provider：Codex CLI 当前登录配置；
- 运行方式：单 chunk 一个非交互 Codex 进程；默认串行，容量验证显式使用 2、5、10 个并发 worker，项目边界只读；
- 默认进程超时：240 秒。一次小批次请求实测约 151 秒完成，120 秒窗口会在最终 JSON 已生成但进程尚未退出时误判为 timeout。Provider 已改为独立进程组、文件诊断流和有界清理。

## 4. 真实运行结果

### 4.1 小批次长窗口成功运行

Evidence：本地 `/private/tmp/invest-hub-spike-02-evidence/codex-single-long`。

| 输入 | chunk size | 请求次数 | 首次成功率 | 最终成功率 | JSON/Schema 率 | P50/P95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 12 条公开 fixture | 100 | 1 | 100% | 100% | 100% | 150,956 ms / 150,956 ms |

人工质量复核结果：

- 6/6 claims covered、grounded、correct attribution；
- 严重归因错误：0；
- 媒体臆测：0；
- 指定用户观点保留 `target-analyst` 归因；
- `public-008` 未解析图片被标记为 `media_unparsed=true`，没有推测图片内容。

### 4.2 120 秒窗口的失败证据

先前使用 chunk size 3、120 秒超时窗口的运行，多个进程在 126–137 秒被终止。原始诊断显示 Codex 已生成合法 JSON，但仍在 WebSocket 重试和退出清理阶段，因此被 harness 记录为 `timeout`。这直接促成默认超时从 120 秒调整为 240 秒；它不能被计入成功率，也不能被忽略。

### 4.3 早期未完成的容量证据

此前尝试使用 500 条、`chunk-size 500` 和 `chunk-size 250`、240 秒超时运行，首个 chunk 分别在 240,014 ms 和 240,009 ms 后被正常记录为 `timeout`。2026-07-17 重跑 500 条、`chunk-size 250`：chunk 0000 首次成功，耗时 77,235 ms；chunk 0001 的三次尝试分别在 240,019 ms、240,017 ms、240,023 ms 超时，最终成功率 50%，重试次数 2，P50/P95 为 240,017/240,023 ms。所有超时均以退出码 -9 正常回收，没有出现此前的 runner 卡死或孤儿进程。该结果说明 250 仍不是安全配置；在该时点约 500 条和 1000 条的完整容量运行尚未完成，因此不能把部分成功外推为中、大规模容量结论；后续 c100 和 1000 条对比见 4.5。

2026-07-18 使用 500 条 synthetic fixture、`chunk-size 100` 和 240 秒超时运行：5 个 chunk 全部首次成功，最终成功率 100%，JSON/Schema 率 100%，请求数 5、重试数 0，P50/P95 为 123,354/157,740 ms，五个请求耗时合计 645,827 ms；所有进程退出码均为 0。该结果支持 100 作为当前容量候选，但 synthetic fixture 只能证明当前规模的调用容量，不能证明业务质量；重复运行稳定性和新的质量复核仍未完成。

### 4.4 有界并发验证

在不复用 Codex 会话、不改变 Provider 和 chunk size 的前提下，增加标准库 `ThreadPoolExecutor` 的最多 2 worker 模式；EvidenceStore 对本地 JSON/JSONL 写入加锁，单 chunk 的重试仍保持独立。

- 公开小 fixture smoke：12 条消息、`chunk-size 3`、4 个 chunk、`max-concurrency 2`；4/4 成功、0 重试，批次耗时 39,884 ms，`max_active_requests=2`。
- 500 条 synthetic fixture：5 个 chunk、`chunk-size 100`、`max-concurrency 2`；5/5 首次及最终成功，0 重试，JSON/Schema 率 100%，P50/P95 为 127,935/129,800 ms，批次墙钟 321,965 ms，`max_active_requests=2`。
- 与同一 500 条、`chunk-size 100` 串行基线的请求耗时合计 645,827 ms 相比，本轮观测 speedup 约 2.006x；并发 evidence 的 5 条 request、5 条 result 和 5 个 raw response 均完整，所有 Provider 状态为 `success`。
- 追加 5 并发探针：同样的 500 条 synthetic fixture、5 个 chunk、`chunk-size 100`；5/5 首次及最终成功，0 重试，P50/P95 为 112,947/129,807 ms，批次墙钟 129,814 ms，`max_active_requests=5`。相对串行约 4.975x、相对 2 并发约 2.480x；evidence 的 5 条 request、5 条 result 和 5 个 raw response 均完整。
- 追加稳定性验证时，Repeat-1 通过；Repeat-2 的 5 个 chunk 中有 1 个在 240,018 ms timeout（退出码 -9），随后重试成功。本轮最终成功率为 100%，但首次成功率 80%、请求数 6、重试数 1、P50/P95 为 127,522/240,018 ms，因此按当时的零重试门槛暂停后续测试；后续完整 1000 条重复验证见 4.6。

该结果验证了“独立 chunk 的有界并发”可以缩短 synthetic capacity 的批次耗时，但当时的 500 条重复运行出现 timeout 后重试。它不代表限流边界或生产安全性，也不代表业务质量提升；后续 1000 条重复运行结果见 4.6。

### 4.5 1000 条 5/10 并发容量对比

在接受“最多 3 次尝试内恢复成功属于可恢复事件”的增量 Spec 口径后，使用相同的 1000 条 synthetic fixture、`chunk-size 100`、240 秒单次 timeout 和最多 3 次尝试，分别执行一轮 5 并发和 10 并发。两轮均生成 10 个初始 chunk；最终 results、requests 和 raw response 数量一致，没有 evidence 错配、状态竞争或进程清理异常。

| 配置 | 请求数 | 重试数 | 首次/最终成功率 | JSON/Schema 率 | P50/P95 | 批次墙钟 | 最大活动请求 | 分类 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1000 / c100 / max5 | 10 | 0 | 100% / 100% | 100% | 119,898 / 129,648 ms | 253,921 ms | 5 | `capacity_probe_pass` |
| 1000 / c100 / max10 | 10 | 0 | 100% / 100% | 100% | 123,711 / 132,231 ms | 132,241 ms | 10 | `capacity_probe_pass` |

10 并发相对 5 并发的批次墙钟减少 121,680 ms，观测 speedup 约 1.92x；两轮都只有一次真实容量探针，不能据此固化 10 并发为生产默认值。synthetic fixture 也不能证明业务摘要质量。

### 4.6 完整验证：重复容量与新鲜质量

在同一 1000 条 synthetic、`chunk-size 100`、240 秒 timeout 和最多 3 次尝试边界下，c5 和 c10 各追加两轮，合并既有首轮后各有 3 个样本。六轮均为 10/10 chunk 最终成功、首次成功率 100%、最终成功率 100%、JSON/Schema 率 100%、重试数 0，requests/results/raw response 数量完整，实际并发没有超过配置值。

| 配置 | 三轮批次墙钟 | 三轮 P50/P95 | 三轮重试 | 三轮最终成功率 | 容量分类 |
| --- | --- | --- | ---: | --- | --- |
| c5 | 253,921 / 304,162 / 264,062 ms | 119,898/129,648；122,831/188,732；125,138/138,903 ms | 0 | 100% / 100% / 100% | `capacity_stable_pass` |
| c10 | 132,241 / 139,351 / 144,374 ms | 123,711/132,231；126,464/139,341；120,682/144,362 ms | 0 | 100% / 100% / 100% | `capacity_stable_pass` |

随后使用 `public_small.json` 做一轮新鲜质量复核：1/1 chunk 成功、JSON/Schema 率 100%、6 个 claims 中 5 个 covered、5 个 grounded，人工复核未发现严重归因错误或媒体臆测。失败点是 `public-008`：输出设置了全局 `media_unparsed=true` 并给出未解析图片 warning，但没有在 topic 中引用 `public-008`，因此没有满足可追溯的 coverage/grounding 门槛。该结果作为历史失败证据保留。

### 4.7 未解析媒体 source linkage 修复后的新鲜质量复核

按方案 1 增加必填的 `media_source_message_ids` 字段，并在 Schema 中要求它精确覆盖当前 chunk 的全部 `unparsed_media` 消息；runner 传入当前 chunk 的媒体 ID 集合，评估器使用该字段判断媒体 claim 的 grounding。确定性测试从 40/40 增加到 46/46，缺失、未知、非媒体和漏引用 ID 均有回归覆盖。

使用明确设置的 `gpt-5.6-luna`、`public_small.json`、`chunk-size=12`、`max-concurrency=1`、最多 3 次尝试和 240 秒 timeout 重新运行；新鲜 evidence 为 `/private/tmp/invest-hub-spike-02-evidence/codex-public-small-media-linkage-20260718-luna`。1/1 chunk 首次及最终成功，JSON/Schema 率 100%，请求数 1、重试数 0，P50/P95 为 46,938/46,938 ms。

模型输出显式包含 `media_source_message_ids=["public-008"]`。直接 Schema 校验和质量评估均为 6/6 covered、6/6 grounded、6/6 correct attribution，严重归因错误 0，媒体臆测 0；未解析媒体仍未被推断。该结果通过了质量门槛。

## 5. 当前结论

结论为 **有条件通过（conditional pass）**：

1. Codex CLI 可以在受限的非交互进程边界下返回符合 Schema 的结构化结果；
2. 当前公开小 fixture 的归因、来源 ID 和未解析媒体边界通过人工复核；
3. 120 秒不足以覆盖本机 Codex CLI 的完整进程生命周期，240 秒应作为当前 Spike 默认窗口；
4. `chunk-size 500` 和 `chunk-size 250` 已实测超时；1000 条 c100 的 c5/c10 各 3 轮均最终成功且无 retry，重复容量稳定性通过；
5. 1000 条 c10 三轮批次墙钟为 132.2–144.4 秒，c5 三轮为 253.9–304.2 秒；在本次 synthetic 观测中 c10 明显更快，但不等于生产限流上限；
6. 修复后的新鲜公开质量复核为 6/6 claims covered、grounded、correct attribution，严重归因错误和媒体臆测均为 0，质量门槛通过；
7. 结合 1000 条 c100 的 c5/c10 各三轮容量稳定性通过，Spike-02 在已记录的本机 Codex CLI 条件下为 `conditional pass`；
8. 之所以是有条件通过，是因为此前 500 条、chunk size 100 的 5 个并发请求 Repeat-2 出现过一次可恢复 timeout/retry，且 chunk size 250/500 已实测不稳定；
9. 用户已确认未来生产试运行优先采用 chunk size 100、5 个并发请求，10 个并发请求作为后续扩容候选；这仍需在未来正式生产 Spec/Plan 中确认，不等于本报告批准 V0/V1 实现或最终 Provider 选型。

## 6. 下一阶段门槛

后续如果进入生产设计，需要在新的正式 Spec/Plan 中明确真实数据运行、限流/SLA、Provider 选择和失败降级策略，同时保留以下运行约束：

- 全部 chunk 的首次/最终成功率、JSON/Schema 率、重试率和 P50/P95；
- timeout、provider failure、empty response、invalid JSON/Schema 的分类；
- 真实总耗时、并发间 speedup 和可接受的运行边界；
- 小 fixture 的人工质量复核已达到 6/6 coverage、grounding 和正确归因，且媒体臆测为 0；本结果不外推为真实业务质量。

在这些证据齐全、正式 Spec 和 implementation plan 另行批准前，不启动 V0/V1 生产实现。
