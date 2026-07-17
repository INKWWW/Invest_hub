# Spike-02 Codex CLI 容量与质量决策报告

## 报告状态

- 日期：2026-07-15；最近更新：2026-07-18
- 结论：**未验证（unverified）**
- 执行内容：本地确定性 harness、Mock 规模对照、Codex CLI 小批次真实运行和人工质量复核
- 真实 Provider：本机已登录的 Codex CLI；没有直接调用 GLM 或其他外部模型 API
- 本报告不批准 V0/V1 生产实现，也不批准自动 fallback

## 1. 范围与安全边界

本次执行只使用人工构造公开 fixture。Codex CLI 通过非交互 `codex exec` 调用，使用 `--sandbox read-only`、`--ephemeral` 和 `--output-last-message`；仅通过 `--add-dir <CODEX_HOME>` 允许其维护自身状态，项目 worktree 不允许修改。

完整 Prompt、Codex 响应和诊断只保存在本地受保护 evidence 目录，不进入 Git。`requests.jsonl` 不保存 Prompt 正文；token usage 在 Codex CLI 未提供时记录为 `null`。

## 2. 确定性验证结果

- 确定性测试：35/35 通过；
- Mock 小批次、约 500 条和 1000 条规模路径保持可运行；
- Mock 的规模结果只证明 harness 的 chunk、重试、Schema 和 evidence 流程，不代表 Codex CLI 的容量或质量。

## 3. Codex CLI 环境

- CLI：`codex-cli 0.144.3`；
- 运行时报告模型：`gpt-5.6-luna`；
- Provider：Codex CLI 当前登录配置；
- 运行方式：单 chunk 一个非交互 Codex 进程，低并发、只读项目边界；
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

### 4.3 尚未完成的容量证据

此前尝试使用 500 条、`chunk-size 500` 和 `chunk-size 250`、240 秒超时运行，首个 chunk 分别在 240,014 ms 和 240,009 ms 后被正常记录为 `timeout`。2026-07-17 重跑 500 条、`chunk-size 250`：chunk 0000 首次成功，耗时 77,235 ms；chunk 0001 的三次尝试分别在 240,019 ms、240,017 ms、240,023 ms 超时，最终成功率 50%，重试次数 2，P50/P95 为 240,017/240,023 ms。所有超时均以退出码 -9 正常回收，没有出现此前的 runner 卡死或孤儿进程。该结果说明 250 仍不是安全配置；约 500 条和 1000 条的完整容量运行仍未完成，本报告不把部分成功外推为中、大规模容量结论。

2026-07-18 使用 500 条 synthetic fixture、`chunk-size 100` 和 240 秒超时运行：5 个 chunk 全部首次成功，最终成功率 100%，JSON/Schema 率 100%，请求数 5、重试数 0，P50/P95 为 123,354/157,740 ms，五个请求耗时合计 645,827 ms；所有进程退出码均为 0。该结果支持 100 作为当前安全候选，但 synthetic fixture 只能证明当前规模的调用容量，不能证明业务质量；1000 条容量、重复运行稳定性和新的质量复核仍未完成。

## 5. 当前结论

结论为 **未验证**：

1. Codex CLI 可以在受限的非交互进程边界下返回符合 Schema 的结构化结果；
2. 当前公开小 fixture 的归因、来源 ID 和未解析媒体边界通过人工复核；
3. 120 秒不足以覆盖本机 Codex CLI 的完整进程生命周期，240 秒应作为当前 Spike 默认窗口；
4. `chunk-size 500` 和 `chunk-size 250` 已实测超时；500 条在 `chunk-size 100` 的一次 synthetic run 中达到 100% 首次/最终成功率，P95 为 157,740 ms，但 1000 条容量、重复稳定性和可接受生产边界尚未验证；
5. 不能据此批准 Codex CLI 进入 V0/V1 生产架构。

## 6. 下一阶段门槛

后续需要在同一受保护环境、优先使用 chunk size 100 或更小，完成约 1000 条 Codex CLI 运行，并视需要重复 500 条运行，同时记录：

- 全部 chunk 的首次/最终成功率、JSON/Schema 率、重试率和 P50/P95；
- timeout、provider failure、empty response、invalid JSON/Schema 的分类；
- 真实总耗时和可接受的串行运行边界；
- 小 fixture 的人工质量复核是否在新的 Prompt/模型配置下保持通过。

在这些证据齐全、正式 Spec 和 implementation plan 另行批准前，不启动 V0/V1 生产实现。
