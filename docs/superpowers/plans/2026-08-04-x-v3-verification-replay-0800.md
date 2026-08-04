# X 08:00 v3 验证恢复链 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans task-by-task. Do not run the production replay until every local contract test is green.

**Goal:** 对 2026-08-04 08:00 的一个 `judgement_failed` 冻结 X 批次执行一次独立的 v3 post → window → daily 验证，并在 `/x` 明确标识为非定时验证恢复。

**Architecture:** 追加 replay/replay-source/replay-segment/replay-version 表与 service-role RPC，不重用原 batch 的 run、segment 或定时队列。显式 Worker 一次性命令读取被冻结的 canonical 输入，串行运行三层 v3 Prompt；完成 RPC 以单一事务验证并持久化。Reader 将成功 replay 附在原失败卡之后。

**Tech Stack:** Supabase pgTAP、Next.js/Vitest、Python unittest、既有 Codex CLI Provider、Vercel、现有 Worker credential。

## Global Constraints

- 仅接受指定 08:00、`judgement_failed` 的原 batch；仅冻结其 `included` 来源。不得调用 OpenCLI/Browser、创建 X sync task、修改 coverage/checkpoint、调用 scheduler 或改变 launchd/cron。
- 原 batch、daily run、v2 事实、v2 segment 及既有定时任务保持不变；replay 失败不重试。
- 分析/窗口/每日判断分别严格使用已发布的 v3 schema 与 Prompt version；错误仅为 `timeout`、`provider_failure`、`empty_response`、`invalid_json`、`schema_error` 或 `persistence_failure`。
- Reader 保留原“判断失败”，增加 `验证恢复（非定时任务）` 标签，且不暴露 replay/task/analysis/segment/evidence ID、Prompt、原始正文或 telemetry。

### Task 1: 数据库 replay authority

**Files:**
- Create: generated `supabase/migrations/<timestamp>_x_v3_verification_replay_0800.sql`
- Create: `supabase/tests/033_x_v3_verification_replay_0800.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`

**Interfaces:** `create_x_v3_verification_replay(uuid, uuid)`, `claim_x_v3_verification_replay(uuid, uuid)`, `get_x_v3_verification_replay_context(uuid, integer, uuid)`, `complete_x_v3_verification_replay(uuid, integer, uuid, jsonb)`, `fail_x_v3_verification_replay(uuid, integer, uuid, text)`.

- [ ] 写 pgTAP RED：普通用户、非 08:00/非失败 batch、重复创建均拒绝；创建只冻结 included source/post，不插入 `sync_tasks`/scheduled daily run；不改变原 batch/run/v2 行。
- [ ] 运行 `supabase test db --file supabase/tests/033_x_v3_verification_replay_0800.sql`，确认因 RPC/table 缺失失败。
- [ ] 用 `supabase migration new x_v3_verification_replay_0800` 新增四张 append-only replay 表。启用 RLS、拒绝 `anon`/`authenticated` 访问、仅授权 service-role RPC；source snapshot 含原 range/segment/post 列表，segment/version 行使用 immutable trigger。
- [ ] 实现 create/claim/context/complete/fail。complete 在单一事务中验证所有 frozen posts 均有 v3 `@2` 分析、每 source 一个 v3 segment、daily 分析/证据集合精确归属；通过后写入 analysis version 2、replay segment/version 并置 succeeded，任一错误整体回滚。
- [ ] 扩展 pgTAP：排除来源不入 replay、非 v3/错证据/第二来源错误均拒绝且无半成品、成功 fixture 有三 source、v3 segments 与一条 daily version；运行 GREEN，生成 TypeScript 类型并提交 `feat: add X 08:00 v3 verification replay contract`。

### Task 2: 控制面端点与 Reader 安全投影

**Files:**
- Create: `apps/control-plane/src/lib/db/repositories/x-v3-verification-replays.ts`
- Create: `apps/control-plane/src/app/api/admin/x/v3-verification-replays/route.ts`
- Create: `apps/control-plane/src/app/api/worker/x-v3-verification-replays/[replayId]/{claim,context,complete,failure}/route.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`, `apps/control-plane/src/components/reader/XReader.tsx`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`, `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`, `apps/control-plane/src/components/reader/x-reader.test.tsx`

- [ ] 先写 RED：只有 admin 能以唯一 `{source_batch_id}` 创建；device Worker endpoints 对错误 ID/attempt/字段返回 422；Reader 同时显示原失败文本和“验证恢复（非定时任务）”，不显示内部字段。
- [ ] 运行 `cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/x-reader.test.tsx`，确认失败。
- [ ] 实现严格 repository mapper 与 endpoints；context 仅向已 claim device 返回冻结 Provider 输入。Reader 仅选 succeeded replay，复用已有 v3 judgement/segment safe mapper，将 replay 作为原 batch 的附加卡片；保留所有 legacy/date/filter 排序。
- [ ] 运行 GREEN 并提交 `feat: expose X 08:00 verification replay safely`。

### Task 3: 显式一次性 Worker replay

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`, `workers/v0/src/invest_hub_worker/runtime.py`, `workers/v0/src/invest_hub_worker/cli.py`
- Create: `workers/v0/tests/test_x_v3_verification_replay.py`
- Modify: `workers/v0/tests/test_protocol.py`, `workers/v0/tests/test_cli.py`

- [ ] 先写 RED：一条两 source fixture 必须按 `v3_x_post_analysis* → v3_x_window* → v3_x_cross_blogger` 顺序调用 Provider；schema 错误只调用 replay failure；不调用 schedule、generic task claim、OpenCLI/Browser 或 normal daily run。
- [ ] 运行 `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_v3_verification_replay.py' -v`，确认命令/Protocol 不存在。
- [ ] 增加四个 Protocol 方法的精确 JSON validator，增加 `XVerificationReplayRuntime` 以 frozen context 运行现有 v3 parser/Provider。增加 `run-x-v3-verification --replay-id`：只构建 Provider/Protocol，要求 `V2_REAL_X_ACK=authorized` 与 X-only config，执行一次并只打印 status/error；不得接入 `_run_scheduled`。
- [ ] 运行 focused + protocol + CLI GREEN，并提交 `feat: run one-off X 08:00 verification replay`。

### Task 4: 完整验证、发布与一次生产执行

**Files:**
- Modify: `docs/superpowers/plans/2026-08-04-x-v3-verification-replay-0800.md`, `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`, `docs/project-status.md`

- [ ] 运行完整 `supabase test db`、Worker unittest、控制面 Vitest/lint/build、`git diff --check` 与 `bash scripts/v0/redact-check.sh`。
- [ ] 停 Worker 领取，仅在新 migration apply 的短窗口内；dry-run/apply 一条 migration，push/deploy stable `/x` 并 reload 同一 checkout。不得创建或改动 launchd/cron/scheduler。
- [ ] 通过 admin API 创建一次 exact 08:00 replay；以 owner-only 现有 config/credential 执行一次显式 replay 命令。失败即停，不重试。
- [ ] 使用只读 SQL 验证原 failure 仍在、scheduled batch/run 数量未变、replay 有三 source/v3 analysis-v3 segment/一 daily version；在认证 `/x` 验证标签、v3 分类、日期/筛选及无内部泄露。
- [ ] 记录真实结果，勾选计划、提交 `docs: record X 08:00 v3 verification replay release` 并 push `main`。
