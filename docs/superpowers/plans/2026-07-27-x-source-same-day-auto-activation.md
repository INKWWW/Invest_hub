# X 新博主当日自动激活与首次总结 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 新增 X 博主自动完成身份核验、最近当日固定窗口初始化、采集及首次总结。

**Architecture:** 数据库原子创建来源、绑定唯一在线 X Worker 和 activation。常驻本机 Worker 每分钟先领取一项 activation，再以 `twitter profile` 验证身份并通过 Worker-only 接口初始化固定范围；随后复用既有 posts + receipt、持久化和 Reader 链路。

**Tech Stack:** Supabase/Postgres pgTAP、Next.js/Vitest、Python `unittest`、受控 OpenCLI、launchd、Vercel。

## Global Constraints

- 仅既有受控 OpenCLI 和 owner-only 本地会话可读取真实 X；不使用 X API、普通用户 Token 或第二采集器。
- 创建只在恰有一台 `online`、两分钟内心跳且声明 `x_sync` 的 Worker 时成功；否则为 `x_worker_unavailable`，不留下来源。
- 初始上界仅为创建前最近上海 `00:00 / 08:00 / 12:00 / 16:00 / 20:00`，范围起点为该自然日 `00:00`。
- identity、coverage、任务和 activation 按来源幂等、可恢复；失败不前移水位、不调 Provider、不显示为无新增。
- `account_id` 只能来自严格匹配的 `twitter profile` handle；不保存或回传 Profile、URL、Cookie、正文、Prompt 或凭据。
- 普通用户不可访问 activation/Worker 诊断；既有 posts + receipt 和原子范围完成不变。

### Task 1: 建立数据库 activation 契约

**Files:** Create `supabase/migrations/20260727100000_x_source_auto_activation.sql`; create `supabase/tests/020_x_source_auto_activation.sql`; modify `apps/control-plane/src/lib/db/types.ts`.

**Interfaces:** `workers.capabilities text[]` 只允许 `x_sync|discord_sync`；`x_source_activations(source_id,worker_id,stage,requested_at,initial_end_at,initial_task_id,last_error_code,completed_at)` 使用 `pending_identity|pending_initialization|collecting|completed|retryable_failed`；`claim_next_x_activation(worker_id,now)` 返回安全 activation 或 null；`initialize_x_source_activation(source_id,worker_id,now)` 返回安全初始化结果。

- [ ] **Step 1: 写失败 pgTAP。** 创建无 Worker、过期 Worker、两个 X Worker、非 X Worker、成功创建、重复 claim、身份未解析初始化、重复初始化、多个来源隔离、任务成功后完成 activation 的断言。固定 `07:59`、`08:00` 与 `15:30` 创建时间，分别断言 server 计算的初始上界。
- [ ] **Step 2: 运行失败测试。** 运行 `SUPABASE_DISABLE_TELEMETRY=1 supabase test db --file supabase/tests/020_x_source_auto_activation.sql`，预期因表/RPC 缺失失败。
- [ ] **Step 3: 写最小 migration。** 增加 `workers.capabilities` 和 RLS activation 表；扩展 `create_x_source`，锁住并绑定唯一合格 Worker、插入 activation 和固定初始上界；创建 claim RPC 锁定仅属于调用 Worker 的一行；创建 initialize RPC，重查 Worker/identity 后写 day-start coverage，复用或写入初始 `x_sync`，并转入 `collecting`；在已有 X range 成功完成路径上仅将相同 `initial_task_id` 的 activation 标记 `completed`。撤销所有 public/anon/authenticated RPC 权限，只授予 service_role，并同步手写类型。
- [ ] **Step 4: 验证数据库。** 依次运行 `supabase db reset`、新 pgTAP 文件和完整 `supabase test db`；所有既有 Discord/X 回归必须通过。
- [ ] **Step 5: 提交。** 仅暂存 migration、pgTAP 与类型，提交信息为 `feat(v2): activate new X sources automatically`。

### Task 2: 提供 Worker-only API 和安全后台状态

**Files:** Create `apps/control-plane/src/lib/db/repositories/x-activations.ts`; create `apps/control-plane/src/app/api/worker/x-activations/claim/route.ts`; create `apps/control-plane/src/app/api/worker/x-activations/[sourceId]/initialize/route.ts`; modify heartbeat route, `sources.ts`, `SourceConfigurationCard.tsx`, API/repository/component tests.

**Interfaces:** `claimXActivation(workerId,now)` 解析并返回 `{sourceId,requestedHandle,parameterVersion,initialEndAt,idempotent}`；`initializeXActivation({sourceId,workerId,now})` 返回 `{taskId,sourceId,initialEndAt,idempotent}`；管理员 lifecycle 新增 `activating|retryable_failed`，但浏览器卡片没有 handle、ID 或诊断。

**Recovery note:** failure isolation keeps a failed identity attempt source-local. The first post-release deployment requeues the pre-release `identity_failed` rows once so existing configured sources receive a fresh verification attempt after the Worker routing fix; migration `20260727160000_x_requeue_unresolved_activations.sql` also repairs legacy activation rows whose profile remained unresolved despite an old completed/collecting state. Any new failure remains isolated and is not retried in a tight loop.

- [ ] **Step 1: 写失败测试。** 覆盖只有已认证 Worker 可 claim、401/403/409 映射、初始化不接收客户端时间、heartbeat 仅接受 `discord_sync|x_sync`、管理员卡片显示“正在验证并准备首次采集”而不包含 handle/ID、普通用户不接触 activation。
- [ ] **Step 2: 运行聚焦测试。** 运行控制面 API、sources repository 和 workspace component 测试，预期因 repository/routes/lifecycle 缺失失败。
- [ ] **Step 3: 实现。** Route 从 `authenticateWorker` 取得 ID，server 生成 now，repository 严格拒绝未知键。heartbeat 保存能力。sources 查询只将 activation stage 投影为安全 lifecycle，后台卡片只显示自动激活进度；手动更新/回填只在 `ready` 时呈现。
- [ ] **Step 4: 验证。** 运行聚焦 Vitest、`npm run lint`、`npm run build`；预期通过且任何普通用户响应/HTML 不含 activation 细节。
- [ ] **Step 5: 提交。** 提交信息为 `feat(v2): expose safe X activation lifecycle`。

### Task 3: 实现本机自动身份核验和动态 X source

**Files:** Create `workers/v0/src/invest_hub_worker/activation.py` and `workers/v0/tests/test_activation.py`; modify `config.py`, `runtime.py`, `protocol.py`, `cli.py`, and existing config/protocol/CLI tests.

**Interfaces:** `activate_one_x_source(protocol,invoker,now)` 一次只处理一个 activation，返回 `no_activation|initialized|retryable_failed`。`LocalWorkerConfigSet.x_source_for(source_id,verified_handle,parameter_version)` 仅以验证通过的 handle 构造临时 `https://x.com/<handle>`。Protocol 增加 claim/initialize 方法并 heartbeat `x_sync`。

- [ ] **Step 1: 写失败 unittest。** Fake protocol 断言严格顺序为 claim → profile exact-match → resolve identity → initialize；覆盖空 claim、身份不匹配、协议失败、重启重试、第一来源失败后第二来源成功、heartbeat 先行、无效/不匹配动态 handle 拒绝，及身份成功前绝不调用 Provider。
- [ ] **Step 2: 运行聚焦 unittest。** 运行 activation/config/protocol/CLI 测试，预期因 helper、protocol 和动态 source 缺失失败。
- [ ] **Step 3: 实现最小 flow。** 每个 scheduled loop heartbeat `x_sync`，领取一个 activation，`twitter profile` 严格核验，调用既有 identity RPC，再调用 initialize RPC，然后运行原来的 schedule tick/run-once。删除 `len(x_sources) != 1` 门禁。静态 Discord 配置保持原样；X task 只可由 task snapshot account ID 与匹配动态 source 执行。失败仅记录安全枚举，不中止下一来源。
- [ ] **Step 4: 验证 Worker。** 运行完整 Worker unittest 与 V2 focused tests；预期失败 activation 不产生原始事实或 Provider 调用。
- [ ] **Step 5: 提交。** 提交信息为 `feat(v2): automate local X source activation`。

### Task 4: 端到端、部署和真实验收

**Files:** Create `docs/engineering-journal/2026-07-27-x-source-same-day-auto-activation.md`; modify `docs/project-status.md`, this plan, this spec, and existing V2 fixture E2E harness/tests.

- [ ] **Step 1: 写人工 fixture E2E。** 在 `15:30 Asia/Shanghai` 创建来源；profile 匹配；模拟 `12:00` 和 `16:00` collection receipt。断言一个 activation、初始 `(00:00,12:00]`、两个时间顺序 daily segments、无重复 Canonical、仅首任务完成后 activation complete。
- [ ] **Step 2: 全量本地验证。** 运行 db reset/全部 pgTAP、全部 Worker tests、控制面 tests/lint/build、`bash scripts/v0/redact-check.sh` 与 `git diff --check`。确保 `.runtime` evidence 未跟踪。
- [ ] **Step 3: 记录并提交。** journal 只记录人工 fixture 和本地验证，不写真实来源；提交 Spec、Plan、journal 和项目状态，信息 `docs: record automatic X source activation`。
- [ ] **Step 4: 发布。** 先推送 main，再 `supabase db push`、Vercel production deploy、`launchctl kickstart -k gui/$(id -u)/com.investhub.x-worker`。逐项验证 migration、Vercel Ready、`x_sync` heartbeat 与 launchd 受控 executable/config；任一步失败都停止真实激活。
- [ ] **Step 5: 有界真实验收。** 仅用现有待验证 X 来源，确认安全阶段转换、同日固定窗口任务和登录 `/x` 的对应卡片；确认普通用户无法访问 Worker API。journal 只记录来源/阶段/任务/卡片数量与上海 window key，并保持“V2 受控生产试运行”。
- [ ] **Step 6: 提交验收记录。** 提交 journal/status 并推送 main，信息 `docs: verify automatic X source activation`。

## Plan self-review

- Task 1 实现固定时间、合格 Worker、原子状态和完成闭环。
- Task 2 实现 Worker 边界及管理员安全状态。
- Task 3 实现本机登录态 identity 和隔离重试。
- Task 4 验证、部署、生产 Reader 验收和状态边界。

## Task 5：终态失败来源调度隔离 amendment（2026-07-31）

- [x] 在 `enqueue_due_x_tasks` 调度边界识别当前 coverage 起点对应的终态 `failed` X 窗口，并将来源加入安全 `deferred_source_ids`，不重复创建任务。
- [x] 新增 pgTAP 回归，证明失败来源不复制、健康来源仍可调度、失败审计保留。
- [x] 用户已明确批准本 amendment 的生产 migration、Worker 重启和线上验收；不删除历史任务、不修改来源标识或登录态。
