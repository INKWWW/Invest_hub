# X v3 历史验证恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` task-by-task. Do not run the production replay until every local contract test is green.

**Goal:** 对 2026-08-03 两个 `judgement_failed` 的冻结 X 批次生成单次、独立且可审计的 v3 恢复结果；原批次、旧 run、v2 事实、覆盖水位与定时任务一律保持不变。

**Architecture:** 追加独立 replay 表和仅 service-role 可调用的 RPC。创建时原子冻结每个 batch 的 `included` 来源、range task、v2 segment 与 canonical post；Worker 显式运行一次 `post → window → daily` v3 Provider 链，完成 RPC 一次性验证并写入 immutable v3 replay 行。Reader 将成功 replay 附在原失败窗口后，并明确显示“验证恢复（非定时任务）”。

**Constraints:** 不调用 OpenCLI/Browser、不创建 X sync task、不变更 coverage/checkpoint、不重试原 initial run、不把 replay 伪装成定时成功、不提交真实 ID/正文/Prompt 私有内容/telemetry。

### Task 1: Database replay authority

- [ ] 先在 `supabase/tests` 写失败的 pgTAP：actor、终态失败、单次创建、冻结 source/post 完整性、claim lease、成功原子写入、失败无半成品、原 batch/run/v2 行不变。
- [ ] 用 `supabase migration new x_v3_verification_replay` 创建追加 migration；只增加 replay、replay-source、replay-segment、replay-version 表及 create/claim/context/complete/fail RPC。
- [ ] 完成 RPC 以 frozen source/analysis/evidence 精确归属校验 v3 output，事务内写入 `x_post_analyses@2`、replay segment/version；任一错误只记录枚举 failure class。
- [ ] 更新生成的控制面数据库类型，并运行 migration-focused pgTAP。

### Task 2: Explicit Worker replay command

- [ ] 先为 Protocol 与 CLI 写失败测试，证明 explicit command 只能使用 opaque replay ID，且不会调用 schedule、OpenCLI 或 Browser。
- [ ] 添加 claim/context/complete/fail Protocol 边界和 `run-x-v3-verification --replay-id` 命令，复用现有 v3 post/window/daily parser 与 Provider；按 post → window → daily 串行执行。
- [ ] 仅以合成 fixture 运行 focused Worker tests；任一 Provider/parser/persistence 错误必须将 replay 记为 failed，不触及原 batch。

### Task 3: Reader-safe projection

- [ ] 先写 repository/component 失败测试：原“判断失败”卡保留，成功 replay 显示非定时恢复标识，v3 三类观点与逐帖投影可读且不泄露内部 ID 或原始正文。
- [ ] 扩展 Reader projection 与 `XReader`；正常 batch 与历史 v2 UI 不改变。
- [ ] 运行控制面 focused tests。

### Task 4: Full verification and production release

- [ ] 运行完整 pgTAP、Worker unittest、控制面 Vitest、lint、production build、`git diff --check`、`bash scripts/v0/redact-check.sh`。
- [ ] 评审 migration 对远端的只读 dry-run；暂停 X Worker 领取，应用 migration 并只读验证 grants/schema，部署同一 main 的 control plane，更新并 reload Worker。
- [ ] 使用两条经只读 SQL 核验的 2026-08-03 failed batch ID 创建 replay；各执行一次显式 Worker 命令并等待终态。失败不自动重试。
- [ ] 以只读 SQL 和已认证正式 `/x` 验收：两条原失败 run 仍为失败、replay 均成功且 Reader 可读；确认没有新增 sync task、scheduler 变更或 coverage/checkpoint 写入。
- [ ] 写入工程日志/项目状态，提交、合入 `main`、推送并记录 stable-domain release 证据。
