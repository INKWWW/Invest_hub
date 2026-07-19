# V0 Infrastructure and Technical Validation Implementation Plan

## 文档状态

- 书面状态：已批准（用户确认 2026-07-18）
- 执行状态：Task 1–9 已完成；后续有界单页真实验证、隔离远程部署与恢复补测均已完成，V0 结论为通过。详细证据见 V0 最终报告、工程日志与项目状态。
- 任务提交：每个 task 独立提交并在进入下一 task 前完成对应测试

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在一个受控 Discord 来源、一个本地 Worker 和一个云端控制面之间跑通可追溯、可恢复、权限隔离的 V0 `discord_sync` 闭环。

**Architecture:** 云端使用 Next.js + TypeScript 控制面、Supabase Auth/Postgres/RLS；本地使用 Python 3.11+ Worker 持有专用 Chrome Profile、OpenCLI Browser Bridge、Active Adapter 和 Codex CLI。云端只管理逻辑来源、任务、状态和持久化结果，Worker 通过版本化 JSON contract 领取任务并上传脱敏状态；所有 checkpoint 只有在事实和结果成功持久化后推进。

**Tech Stack:** Next.js + TypeScript；Vercel 部署；Supabase Auth、Postgres、RLS；Python 3.11+ 标准库 Worker；OpenCLI Browser Bridge + Active Adapter；本机已登录 Codex CLI；Mock Provider；JSON Schema；Vitest；Python `unittest`；Supabase CLI。

## Global Constraints

- V0 只验证一个管理员配置的 Discord 来源、一个本地 Worker 和手动触发的 `discord_sync` 任务；不实现正式 Discord 阅读页、X、多来源运营或模块 2–4。
- Active Adapter 是 Discord 候选主路径；原 OpenCLI Connector 只保留为诊断基线和必要时的回退候选，不建立第二套完整采集框架。
- Codex CLI 是唯一真实 LLM Provider 候选；Mock 只用于确定性测试；不实现 GLM、其他真实 Provider 或自动 fallback。
- Provider 起始候选参数固定为 `chunk_size=100`、`max_concurrency=5`、单请求 timeout 240 秒、最多 3 次尝试；失败 chunk 独立重试，必要时显式降至 2 并发；不启用 `chunk_size=250/500` 或将 10 并发设为默认。
- Discord 单页操作保留 90 秒硬截止；missing/stale response、登录失效、无权限和 timeout 不得被记录为空数据成功。
- 云端任务只携带逻辑 `source_id`、运行参数版本和非敏感范围；Discord URL、Profile reference、Cookie、Token、Prompt 正文、完整模型响应和真实 raw evidence 只留在本地受保护路径。
- Worker 以一次性 enrolment code 换取随机设备密钥；云端只保存密钥 hash；code 消费、过期或 Worker 撤销后不能重新领取任务。
- Worker 默认每 60 秒发送心跳；lease 默认 10 分钟，剩余小于 2 分钟时续租；lease 到期不推进 checkpoint，恢复依靠唯一键幂等。
- `(source_id, external_message_id)` 是 Canonical 消息唯一键；摘要/结构化输出必须能回溯到输入 Canonical ID；未解析媒体必须显式引用对应消息 ID，不得推断媒体内容。
- 生产目录、依赖、云端项目和部署均必须等本 Spec 与本 Plan 获得用户批准后才可创建；本 Plan 本身不授权实现。
- 每个任务完成自己的测试后单独提交；提交信息使用 `feat: v0 ...`、`test: v0 ...` 或 `docs: v0 ...` 前缀，不使用合并式一次性提交。

---

## 1. 文件与边界地图

实现开始前，生产代码与验证代码按以下边界创建。不得把 `spikes/spike_01` 或 `spikes/spike_02` 直接作为运行时 import；只能读取其公开 contract 和 fixture 作为迁移输入。

| 路径 | 责任 |
| --- | --- |
| `contracts/v0/*.json` | 控制面与 Worker 之间的版本化 JSON Schema；跨 TypeScript/Python 的唯一协议来源 |
| `apps/control-plane/package.json`、`apps/control-plane/src/` | Next.js 控制面、受保护管理页、Route Handlers、Supabase server client 和错误映射 |
| `apps/control-plane/src/lib/auth/` | 当前用户、角色、邀请码和管理权限检查 |
| `apps/control-plane/src/lib/db/` | 仅服务端使用的 Supabase repository；不向浏览器暴露 service-role key |
| `apps/control-plane/src/lib/tasks/` | task 状态机、lease、幂等回报和失败分类 |
| `apps/control-plane/src/app/api/` | Admin 与 Worker Route Handlers |
| `apps/control-plane/src/app/admin/` | 管理员调试页面与状态组件；不提供普通用户阅读页 |
| `supabase/migrations/001_v0_core.sql` | V0 最小表、索引、触发器和 RLS policy |
| `supabase/tests/001_v0_rls.sql` | 数据库级角色、RLS、唯一键和 lease 竞争测试 |
| `workers/v0/pyproject.toml`、`workers/v0/src/invest_hub_worker/` | Python Worker、协议客户端、任务执行器、Active Adapter、Provider 管线和本地安全配置 |
| `workers/v0/tests/` | Worker 单元、故障注入、协议和恢复测试；只使用公开 fixture/Mock |
| `tests/e2e/v0/` | 云端控制面与 Worker 的部署前后端到端验证脚本，不保存真实正文或凭据 |
| `scripts/v0/` | 本地 preflight、脱敏检查、部署后验收入口；不包含私有来源参数 |
| `docs/engineering-journal/2026-07-18-v0.md` | V0 实际尝试、失败、修复和验证证据 |
| `docs/spikes/2026-07-18-v0-decision-report.md` | V0 脱敏 Final Report 和进入 V1 的门槛 |

## 2. Task 1：建立跨语言 Contract 与最小运行骨架

**Files:**

- Create: `contracts/v0/worker-enrolment.schema.json`
- Create: `contracts/v0/heartbeat.schema.json`
- Create: `contracts/v0/task-claim.schema.json`
- Create: `contracts/v0/task-event.schema.json`
- Create: `contracts/v0/task-result.schema.json`
- Create: `contracts/v0/task-failure.schema.json`
- Create: `contracts/v0/source-config.schema.json`
- Create: `contracts/v0/README.md`
- Create: `apps/control-plane/package.json`
- Create: `apps/control-plane/tsconfig.json`
- Create: `apps/control-plane/next.config.mjs`
- Create: `apps/control-plane/src/lib/contracts.ts`
- Create: `workers/v0/pyproject.toml`
- Create: `workers/v0/src/invest_hub_worker/__init__.py`
- Create: `workers/v0/src/invest_hub_worker/contracts.py`
- Create: `workers/v0/tests/test_contracts.py`

**Interfaces:**

- `source-config.schema.json` 固定 `source_id`、`source_type=discord`、`channel_url`、`profile_ref` 和 `opencli_contract_version` 的本地配置结构；`channel_url` 和 `profile_ref` 只能存在于 Worker 本地文件，不得出现在云端 task payload。
- `task-claim.schema.json` 的响应必须包含 `task_id`、`attempt`、`source_id`、`lease_expires_at`、`parameter_version` 和 `task_type=discord_sync`。
- `task-result.schema.json` 必须包含 `task_id`、`attempt`、`status=succeeded`、`safe_checkpoint`、`raw_count`、`canonical_count`、`duplicate_count`、`unresolved_count`、`structured_run_ids` 和脱敏 telemetry。
- `task-failure.schema.json` 必须包含 `task_id`、`attempt`、`status`（`retryable_failed`、`failed` 或 `cancelled`）、`failure_class`、`safe_checkpoint` 和 `retryable`。
- TypeScript 暴露 `parseContract<T>(schemaName: string, value: unknown): T`；Python 暴露 `load_contract(name: str, value: object) -> dict`。两者均拒绝缺失字段、未知枚举和未定义额外字段。

- [ ] **Step 1: Write contract rejection tests**

  在 `workers/v0/tests/test_contracts.py` 写入以下最小断言：完整 heartbeat/task claim/result 通过；缺少 `task_id`、未知 `failure_class`、`safe_checkpoint` 越过输入范围和 task result 带完整 Prompt 字段均失败。

- [ ] **Step 2: Run the contract tests and verify they fail**

  Run: `python3 -m unittest discover -s workers/v0/tests -p 'test_contracts.py' -v`

  Expected: FAIL，因为 contract loader 与 schema 文件尚不存在。

- [ ] **Step 3: Add schemas and minimal loaders**

  每个 schema 使用 JSON Schema draft 2020-12，设置 `additionalProperties: false`；`task-result` 的 `safe_checkpoint` 只允许 `string | null`，脱敏 telemetry 只允许计数、耗时、状态和分类字段。TypeScript 和 Python loader 对同一批固定样例执行相同的必填/枚举检查。`apps/control-plane/package.json` 添加运行时 `next`、`react`、`react-dom`、`@supabase/ssr`、`@supabase/supabase-js`、`ajv`，开发依赖 `typescript`、`vitest`、`eslint` 和对应 Next.js 配置；`workers/v0/pyproject.toml` 添加 `jsonschema` 运行时依赖，并固定可复现的 lock/安装记录。

- [ ] **Step 4: Run contract tests and cross-language fixture checks**

  Run: `python3 -m unittest discover -s workers/v0/tests -p 'test_contracts.py' -v`

  Expected: PASS；所有合法样例通过，所有非法样例被拒绝，且测试输出不打印真实内容。

- [ ] **Step 5: Commit the protocol boundary**

  ```bash
  git add contracts/v0 apps/control-plane/package.json apps/control-plane/tsconfig.json apps/control-plane/next.config.mjs apps/control-plane/src/lib/contracts.ts workers/v0/pyproject.toml workers/v0/src workers/v0/tests/test_contracts.py
  git commit -m "feat: define v0 control plane worker contracts"
  ```

## 3. Task 2：建立 Supabase 数据模型、RLS 与邀请码

**Files:**

- Create: `supabase/migrations/001_v0_core.sql`
- Create: `supabase/tests/001_v0_rls.sql`
- Create: `apps/control-plane/src/lib/db/types.ts`
- Create: `apps/control-plane/src/lib/db/supabase-server.ts`
- Create: `apps/control-plane/src/lib/db/repositories/invites.ts`
- Create: `apps/control-plane/src/lib/db/repositories/workers.ts`
- Create: `apps/control-plane/src/lib/db/repositories/sources.ts`
- Create: `apps/control-plane/src/lib/db/repositories/tasks.ts`
- Create: `apps/control-plane/src/lib/db/repositories/evidence.ts`
- Test: `supabase/tests/001_v0_rls.sql`

**Interfaces:**

- Migration 创建 `profiles`、`invites`、`workers`、`sources`、`sync_tasks`、`task_attempts`、`checkpoints`、`raw_messages`、`canonical_messages`、`structured_runs`、`task_events` 和 `evidence_refs`。
- 所有表使用 UUID 主键、UTC `timestamptz`、created/updated 时间；`canonical_messages` 添加唯一约束 `(source_id, external_message_id)`；`task_attempts` 添加 `(task_id, attempt)` 唯一约束。
- `sync_tasks.status` 只允许 `queued`、`leased`、`running`、`retryable_failed`、`succeeded`、`failed`、`cancelled`；`task_attempts.status` 只允许 `leased`、`running`、`succeeded`、`retryable_failed`、`failed`。
- RLS 规则：管理员可读写控制面和调试数据；普通用户在 V0 只读取自己的 profile 和登录后的最小占位状态，不授予任务、Worker、source、raw、structured 或 event 表读取权限；Worker 不通过用户 JWT 访问数据库，只通过 Worker API。
- `claim_next_task(worker_id, now)` 必须在单个事务内锁定一条授权且未过期的 queued task，写入 attempt/lease 后返回完整 `task-claim`。
- `accept_task_result` 只有当 task/attempt 的 lease owner、attempt 和状态匹配时，才保存结果并在同一事务中推进 checkpoint；重复成功回报返回幂等成功，不重复推进。

- [ ] **Step 1: Write failing SQL tests for unique keys, RLS and lease races**

  在 `supabase/tests/001_v0_rls.sql` 覆盖：普通用户不能读/写 admin tables；管理员能创建 invite；同一 invite 不能消费两次；同一 external message 不可插入两次；两个 Worker 同时 claim 同一 queued task 时只有一个成功；过期 lease 可被另一个授权 Worker 接管。

- [ ] **Step 2: Run the database tests and verify they fail**

  Run: `supabase db reset`

  Then: `supabase test db`

  Expected: FAIL，因为 migration、functions 和 RLS 尚不存在。

- [ ] **Step 3: Implement the migration and transactional functions**

  在 `001_v0_core.sql` 中先创建 enums/tables/indexes，再创建 `claim_next_task`、`renew_task_lease`、`accept_task_result`、`record_task_failure` 四个 `security definer` 函数；每个函数固定 `search_path`，校验 worker/source 授权并避免把 service-role key 暴露给客户端。

- [ ] **Step 4: Run database tests and inspect policies**

  Run: `supabase db reset`

  Then: `supabase test db`

  Expected: PASS；并发 claim 只有一个 owner，普通用户所有越权断言均失败，重复结果不会新增消息或推进 checkpoint。

- [ ] **Step 5: Commit the data and permission boundary**

  ```bash
  git add supabase/migrations/001_v0_core.sql supabase/tests/001_v0_rls.sql apps/control-plane/src/lib/db
  git commit -m "feat: add v0 data model and row level security"
  ```

## 4. Task 3：实现 Auth、邀请码与控制面任务 API

**Files:**

- Create: `apps/control-plane/src/lib/auth/current-user.ts`
- Create: `apps/control-plane/src/lib/auth/require-role.ts`
- Create: `apps/control-plane/src/lib/auth/invites.ts`
- Create: `apps/control-plane/src/lib/tasks/state-machine.ts`
- Create: `apps/control-plane/src/lib/tasks/lease.ts`
- Create: `apps/control-plane/src/app/api/admin/invites/route.ts`
- Create: `apps/control-plane/src/app/api/admin/workers/route.ts`
- Create: `apps/control-plane/src/app/api/admin/sources/route.ts`
- Create: `apps/control-plane/src/app/api/admin/tasks/route.ts`
- Create: `apps/control-plane/src/app/api/admin/tasks/[taskId]/retry/route.ts`
- Create: `apps/control-plane/src/app/(auth)/login/page.tsx`
- Create: `apps/control-plane/src/app/(auth)/invite/page.tsx`
- Create: `apps/control-plane/src/app/page.tsx`
- Create: `apps/control-plane/src/app/api/worker/enrol/route.ts`
- Create: `apps/control-plane/src/app/api/worker/heartbeat/route.ts`
- Create: `apps/control-plane/src/app/api/worker/tasks/claim/route.ts`
- Create: `apps/control-plane/src/app/api/worker/tasks/[taskId]/lease/route.ts`
- Create: `apps/control-plane/src/app/api/worker/tasks/[taskId]/result/route.ts`
- Create: `apps/control-plane/src/app/api/worker/tasks/[taskId]/failure/route.ts`
- Create: `apps/control-plane/src/app/api/worker/tasks/[taskId]/events/route.ts`
- Test: `apps/control-plane/src/lib/tasks/state-machine.test.ts`
- Test: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

- Admin APIs require a server-side Supabase session with `role=admin`; all non-admin calls return `403` without revealing record existence.
- `POST /api/admin/invites` returns the one-time plaintext code once and stores only its hash; `POST /api/worker/enrol` consumes the code once and returns `{ worker_id, device_secret, expires_at }`, after which only the hash is retained.
- Worker APIs authenticate `Authorization: Bearer <device_secret>`; `/heartbeat` returns current worker status and next heartbeat deadline; `/tasks/claim` returns `204` when no eligible task exists or a versioned task claim when one exists.
- `POST /api/worker/tasks/{taskId}/result` and `/failure` require matching `attempt`, lease owner and contract version; the response is idempotent for repeated identical payloads and rejects conflicting payloads with `409`.
- `state-machine.ts` exports `transitionTask(current, event) -> next` and rejects invalid transitions with a typed `InvalidTaskTransition` error.
- `/login` supports email/password sign-in through Supabase Auth; `/invite` accepts the one-time invite code and creates the ordinary-user account; `/` only renders the authenticated V0 minimal status page and never exposes admin data.

- [ ] **Step 1: Write state-machine and API authorization tests**

  Test every legal transition, invalid `succeeded → running`, expired lease, ordinary-user admin access, enrolment-code replay, missing Worker secret, result attempt mismatch, conflicting duplicate result, login failure and invite-code replay.

- [ ] **Step 2: Run the tests and verify they fail**

  Run: `cd apps/control-plane && npm test -- state-machine api.integration`

  Expected: FAIL，因为 route handlers、state machine 和 repositories 尚不存在。

- [ ] **Step 3: Implement auth, enrolment and task routes**

  Route handlers must parse JSON through `contracts/v0`, call repositories only on the server, map database errors to stable `400/401/403/404/409/422/503` responses, and write a脱敏 `task_event` for every state change. No route may accept `role` or `worker_id` from an untrusted body when it can derive them from the session/token.

- [ ] **Step 4: Run unit and integration tests**

  Run: `cd apps/control-plane && npm test -- state-machine api.integration`

  Expected: PASS；所有授权、状态、租约和幂等测试通过，响应体不包含 token hash、Prompt、Profile 或完整响应。

- [ ] **Step 5: Commit the control-plane protocol**

  ```bash
  git add apps/control-plane/src/app apps/control-plane/src/lib/auth apps/control-plane/src/lib/tasks apps/control-plane/src/app/api/api.integration.test.ts apps/control-plane/src/lib/tasks/state-machine.test.ts
  git commit -m "feat: add v0 auth and task control APIs"
  ```

## 5. Task 4：实现 Worker 本地安全配置、心跳、租约与恢复状态机

**Files:**

- Create: `workers/v0/src/invest_hub_worker/config.py`
- Create: `workers/v0/src/invest_hub_worker/protocol.py`
- Create: `workers/v0/src/invest_hub_worker/heartbeat.py`
- Create: `workers/v0/src/invest_hub_worker/lease.py`
- Create: `workers/v0/src/invest_hub_worker/worker.py`
- Create: `workers/v0/src/invest_hub_worker/errors.py`
- Create: `workers/v0/tests/test_config.py`
- Create: `workers/v0/tests/test_protocol.py`
- Create: `workers/v0/tests/test_worker_recovery.py`
- Create: `workers/v0/README.md`

**Interfaces:**

- `LocalWorkerConfig.load(path: Path) -> LocalWorkerConfig` 只读取本地权限为 owner-only 的 JSON/TOML 文件，字段为 `control_plane_url`、`source_id`、`channel_url`、`profile_ref`、`opencli_contract_version` 和 `parameter_version`；打印配置时只显示 hash/逻辑 ID。
- `WorkerProtocol.enrol(code: str) -> DeviceCredential` 只调用一次 enrol endpoint；`DeviceCredential` 写入本地 credential store，原始 enrolment code 不落盘。
- `WorkerProtocol.claim() -> TaskClaim | None`、`renew(task_id, attempt) -> LeaseState`、`report_result(result) -> Ack`、`report_failure(failure) -> Ack` 必须发送 contract version 和 attempt。
- `Worker.run_once() -> RunOutcome` 执行 `heartbeat → claim → preflight → execute → report`；网络失败不把 task 变成 succeeded，租约不确定时停止上传结果并保留本地诊断。
- Worker 本地状态只允许 `idle`、`claimed`、`executing`、`reporting`、`recovering`、`stopped`；重启后从云端 claim 状态恢复，不从本地猜测 checkpoint。

- [ ] **Step 1: Write local-config, protocol and recovery tests**

  测试 owner-only 配置、缺字段/可疑权限拒绝、enrol code 不落盘、heartbeat 失败保持可重试、claim 后进程中断、lease 到期停止回报、重复 result 幂等和 conflicting result 拒绝。

- [ ] **Step 2: Run the Worker tests and verify they fail**

  Run: `python3 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v`

  Expected: FAIL，因为 protocol/client、状态机和本地 config 尚不存在。

- [ ] **Step 3: Implement the Worker protocol and recovery loop**

  使用 Python 标准库 HTTPS client；每次请求设置显式 connect/read timeout，响应先过 JSON Schema 再进入状态机。Worker 只把脱敏计数、分类和状态发回云端；真实 URL、Profile reference、Prompt 和 raw/response 文件保持本地。

- [ ] **Step 4: Run Worker tests with fake control-plane responses**

  Run: `python3 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v`

  Expected: PASS；故障注入能证明 Worker 不在不确定 lease 时推进状态，重启能安全重新 claim。

- [ ] **Step 5: Commit the Worker lifecycle**

  ```bash
  git add workers/v0/src/invest_hub_worker workers/v0/tests workers/v0/README.md
  git commit -m "feat: add v0 worker lifecycle and recovery"
  ```

## 6. Task 5：实现 Discord Active Adapter 任务执行与 checkpoint 保护

**Files:**

- Create: `workers/v0/src/invest_hub_worker/connectors/base.py`
- Create: `workers/v0/src/invest_hub_worker/connectors/discord_active_adapter.py`
- Create: `workers/v0/src/invest_hub_worker/canonical.py`
- Create: `workers/v0/src/invest_hub_worker/checkpoint.py`
- Create: `workers/v0/src/invest_hub_worker/evidence.py`
- Create: `workers/v0/src/invest_hub_worker/sync_executor.py`
- Create: `workers/v0/tests/test_discord_active_adapter.py`
- Create: `workers/v0/tests/test_checkpoint_order.py`
- Create: `workers/v0/tests/test_sync_executor.py`
- Create: `workers/v0/tests/fixtures/discord_public_page.json`

**Interfaces:**

- `Connector.collect(source: LocalWorkerConfig, checkpoint: str | None, deadline: float) -> Iterator[RawPage]` 只返回当前来源的 raw page 和 page telemetry，不写 checkpoint。
- `DiscordActiveAdapter` 负责频道根路由规范化、cursor 分页、`request key + request URL` freshness 匹配、一次 cache-buster 重开、90 秒硬截止、missing/stale 分类和有限重试。
- `Canonicalizer.map(raw_page) -> tuple[CanonicalMessage, ...]` 保留作者、时间、正文、回复/引用关系、附件元数据和 unresolved 状态；重复 ID 在 repository 层幂等。
- `SyncExecutor.execute(task_claim, local_source) -> TaskResult | TaskFailure` 依次执行 `collect → raw persist → canonical validate/persist → deterministic sort/chunk → provider pipeline → result report`；只有 cloud ack 确认结果持久化成功后才返回安全 checkpoint。
- `CheckpointGuard.commit(old, candidate, persistence_ack) -> str` 在 `persistence_ack != accepted` 时抛出 `CheckpointNotAdvanced`；candidate 必须属于本次采集范围。

- [ ] **Step 1: Write fixture and checkpoint-order tests**

  覆盖频道深链规范化、freshness 缺失/陈旧响应、一次重开后仍缺失、页面硬截止、重复消息、未知回复目标、raw persistence 失败、Canonical validation 失败、provider 失败和 persistence ack 前试图推进 checkpoint。

- [ ] **Step 2: Run connector tests and verify they fail**

  Run: `python3 -m unittest workers/v0/tests/test_discord_active_adapter.py workers/v0/tests/test_checkpoint_order.py workers/v0/tests/test_sync_executor.py -v`

  Expected: FAIL，因为 V0 connector、canonicalizer、evidence store 和 checkpoint guard 尚不存在。

- [ ] **Step 3: Implement the adapter and checkpoint guard**

  Active Adapter 只将 OpenCLI Browser Bridge 作为外部边界；不得通过 DOM 内容填补缺失 network response，不得把错误会话、登录页或空页面标成成功。每页保存脱敏 `match_state`、attempt、阶段耗时和失败分类。

- [ ] **Step 4: Run deterministic connector and recovery tests**

  Run: `python3 -m unittest workers/v0/tests/test_discord_active_adapter.py workers/v0/tests/test_checkpoint_order.py workers/v0/tests/test_sync_executor.py -v`

  Expected: PASS；fixture 完整率 100%、重复写入 0，checkpoint 只在 persistence ack 后推进，失败页可从旧边界恢复。

- [ ] **Step 5: Commit the Discord execution boundary**

  ```bash
  git add workers/v0/src/invest_hub_worker/connectors workers/v0/src/invest_hub_worker/canonical.py workers/v0/src/invest_hub_worker/checkpoint.py workers/v0/src/invest_hub_worker/evidence.py workers/v0/src/invest_hub_worker/sync_executor.py workers/v0/tests
  git commit -m "feat: add v0 discord sync and checkpoint guard"
  ```

## 7. Task 6：实现 Mock/Codex Provider 管线与结构化证据持久化

**Files:**

- Create: `workers/v0/src/invest_hub_worker/providers/base.py`
- Create: `workers/v0/src/invest_hub_worker/providers/mock.py`
- Create: `workers/v0/src/invest_hub_worker/providers/codex_cli.py`
- Create: `workers/v0/src/invest_hub_worker/structured.py`
- Create: `workers/v0/src/invest_hub_worker/retry.py`
- Create: `workers/v0/tests/test_provider_retry.py`
- Create: `workers/v0/tests/test_codex_process_cleanup.py`
- Create: `workers/v0/tests/test_structured_output.py`
- Create: `workers/v0/tests/fixtures/structured_valid.json`
- Create: `workers/v0/tests/fixtures/structured_media_linkage_invalid.json`

**Interfaces:**

- `Provider.complete(input_chunk: tuple[CanonicalMessage, ...], context: ProviderContext) -> ProviderResponse`；`ProviderResponse` 必须包含 status、provider、model_reported、prompt_version、elapsed_ms、attempt、raw_ref 和 parsed_output_ref，不包含 Prompt 或完整响应正文。
- `MockProvider` 产生可重复的 valid/schema-error/timeout/provider-failure fixture；不得调用网络。
- `CodexCLIProvider.complete()` 每个 chunk 启动独立进程组，使用 `codex exec --sandbox read-only --add-dir <CODEX_HOME> --ephemeral --output-last-message <file> -`，stdout/stderr 写临时文件；timeout 时终止整个进程组并有限清理，不调用无界 `communicate()`。
- `RetryPolicy(max_attempts=3, timeout_seconds=240)` 只重试当前 chunk；Schema error、timeout、provider failure、empty response 和 invalid JSON 进入不同的 `failure_class`。
- `validate_structured_output(output, input_ids, unparsed_media_ids) -> StructuredOutput` 要求 `media_source_message_ids` 精确覆盖当前 chunk 的所有未解析媒体消息，禁止未知/非媒体/漏引用 ID。

- [ ] **Step 1: Write Provider, cleanup and media-linkage tests**

  测试首次成功、最多 3 次恢复、三次失败、invalid JSON、Schema error、超时后 descendant process 被回收、完整/缺失/未知/非媒体/漏引用 `media_source_message_ids`，以及成功结果的 evidence ref 完整性。

- [ ] **Step 2: Run provider tests and verify they fail**

  Run: `python3 -m unittest workers/v0/tests/test_provider_retry.py workers/v0/tests/test_codex_process_cleanup.py workers/v0/tests/test_structured_output.py -v`

  Expected: FAIL，因为 Provider、retry policy、cleanup 和 structured validator 尚不存在。

- [ ] **Step 3: Implement Mock, Codex process boundary and validator**

  Codex provider 读取 `--output-last-message` 文件，先校验 JSON，再校验 Schema，再写本地 raw response ref；任何完整 Prompt/response 只能写到受保护 evidence 目录。Runner 不得自动补齐媒体来源 ID。

- [ ] **Step 4: Run provider and deterministic evidence tests**

  Run: `python3 -m unittest workers/v0/tests/test_provider_retry.py workers/v0/tests/test_codex_process_cleanup.py workers/v0/tests/test_structured_output.py -v`

  Expected: PASS；所有失败分类稳定，重试只影响当前 chunk，进程组可回收，媒体来源字段完整性得到确定性验证。

- [ ] **Step 5: Commit the structured Provider boundary**

  ```bash
  git add workers/v0/src/invest_hub_worker/providers workers/v0/src/invest_hub_worker/structured.py workers/v0/src/invest_hub_worker/retry.py workers/v0/tests
  git commit -m "feat: add v0 structured provider pipeline"
  ```

## 8. Task 7：实现管理员调试页与状态可视化

**Files:**

- Create: `apps/control-plane/src/app/admin/layout.tsx`
- Create: `apps/control-plane/src/app/admin/page.tsx`
- Create: `apps/control-plane/src/app/admin/workers/page.tsx`
- Create: `apps/control-plane/src/app/admin/sources/page.tsx`
- Create: `apps/control-plane/src/app/admin/tasks/page.tsx`
- Create: `apps/control-plane/src/app/admin/tasks/[taskId]/page.tsx`
- Create: `apps/control-plane/src/components/admin/StatusBadge.tsx`
- Create: `apps/control-plane/src/components/admin/WorkerCard.tsx`
- Create: `apps/control-plane/src/components/admin/TaskTimeline.tsx`
- Create: `apps/control-plane/src/components/admin/EvidenceSummary.tsx`
- Create: `apps/control-plane/src/components/admin/RetryTaskButton.tsx`
- Create: `apps/control-plane/src/app/admin/admin-ui.test.tsx`

**Interfaces:**

- Admin page consumes server-side view models from `/api/admin/workers`, `/api/admin/sources`, `/api/admin/tasks` and `/api/admin/tasks/{taskId}`；页面组件不得直接读取 Supabase service-role client。
- `StatusBadge` 必须区分 `no_new_data`、`retryable_failed`、`failed`、`succeeded_with_unresolved` 和 `succeeded`；不能用统一的成功/失败标签替代。
- Task detail 必须展示 task/attempt、lease、阶段、失败分类、retry count、raw/Canonical/duplicate/unresolved/media counts、chunk ranges、Provider/model/prompt version、P50/P95、Schema status、checkpoint 和 evidence refs。
- Debug UI 永远不展示 Cookie、Token、Profile reference、Prompt 正文或完整模型响应；普通用户访问 `/admin/*` 返回 403/重定向登录。

- [ ] **Step 1: Write admin view-model and role-boundary tests**

  测试四种状态显示、脱敏字段过滤、普通用户访问阻断、retry button 只对 `retryable_failed` 显示、没有新数据与成功但有 unresolved 的区分。

- [ ] **Step 2: Run UI tests and verify they fail**

  Run: `cd apps/control-plane && npm test -- admin-ui`

  Expected: FAIL，因为页面、组件和 view-model 尚不存在。

- [ ] **Step 3: Implement the admin pages and components**

  使用 server components 读取已授权 view model；retry 操作只创建新的 task attempt，不覆盖旧事件。所有错误通过状态分类展示，详细诊断只在本地 evidence ref 上可追踪。

- [ ] **Step 4: Run UI tests and lint**

  Run: `cd apps/control-plane && npm test -- admin-ui`

  Then: `cd apps/control-plane && npm run lint`

  Expected: PASS；页面状态、脱敏和普通用户阻断测试通过，lint 无错误。

- [ ] **Step 5: Commit the admin debug surface**

  ```bash
  git add apps/control-plane/src/app/admin apps/control-plane/src/components/admin
  git commit -m "feat: add v0 admin debug pages"
  ```

## 9. Task 8：接通端到端任务执行并验证恢复

**Files:**

- Create: `tests/e2e/v0/fixtures.py`
- Create: `tests/e2e/v0/test_auth_and_rls.py`
- Create: `tests/e2e/v0/test_worker_task_flow.py`
- Create: `tests/e2e/v0/test_checkpoint_recovery.py`
- Create: `tests/e2e/v0/test_real_discord_preflight.py`
- Create: `scripts/v0/preflight.py`
- Create: `scripts/v0/run-e2e.sh`
- Create: `scripts/v0/redact-check.sh`
- Modify: `apps/control-plane/.env.example`
- Modify: `workers/v0/README.md`

**Interfaces:**

- `scripts/v0/preflight.py` 检查 OpenCLI 版本/contract、Worker 本地配置权限、Profile reference 是否存在、控制面 URL 是否可达；输出只包含 pass/fail、版本和逻辑 ID。
- `tests/e2e/v0/test_auth_and_rls.py` 使用本地 Supabase 测试项目和人工构造账号，不使用真实邀请、真实来源或真实消息。
- `tests/e2e/v0/test_worker_task_flow.py` 使用 Mock Provider 和 fixture Connector 验证 `invite → enrol → heartbeat → claim → execute → result → succeeded`。
- `tests/e2e/v0/test_checkpoint_recovery.py` 在 raw persistence 前、Canonical persistence 后、Provider 失败后和 lease 到期时注入中断，证明 checkpoint 不越界且重复 Canonical 为 0。
- `tests/e2e/v0/test_real_discord_preflight.py` 只在用户明确提供已登录专用 Profile 和授权 Discord 来源时运行；脚本不得把 URL、正文或 Profile path 写入 stdout、Git 或 evidence report。

- [ ] **Step 1: Write local end-to-end test harness and failure injections**

  先建立 fake control-plane responses、Mock Provider、fixture Connector 和故障注入点；所有测试清理本地临时目录并断言敏感值不在输出中。

- [ ] **Step 2: Run the harness and verify it fails at missing wiring**

  Run: `python3 -m unittest discover -s tests/e2e/v0 -p 'test_*.py' -v`

  Expected: FAIL，具体失败应落在未连接的 control-plane/Worker/connector，而不是静默跳过。

- [ ] **Step 3: Wire the control plane, Worker and persistence path**

  使用本地 Supabase 与 Next.js dev server；Worker 通过真实 HTTP contract 调用控制面。Mock path 完成后，再把真实 OpenCLI/Codex 作为显式 preflight-gated path 接入，不在测试中自动读取用户 Profile。

- [ ] **Step 4: Run the full deterministic E2E suite**

  Run: `supabase db reset`

  Then: `python3 -m unittest discover -s tests/e2e/v0 -p 'test_*.py' -v`

  Expected: PASS；auth/RLS、Worker lifecycle、task state、raw→Canonical→structured、lease recovery 和 checkpoint invariants 全部通过。

- [ ] **Step 5: Run the explicitly authorized real-page validation**

  Run: `python3 scripts/v0/preflight.py`

  Then: `bash scripts/v0/run-e2e.sh --mode real-discord --provider codex --chunk-size 100 --max-concurrency 5 --timeout-seconds 240 --max-attempts 3`

  Expected: preflight 通过后完成至少一个真实增量页；若登录态、权限、OpenCLI contract 或 Provider 失败，任务必须以明确失败分类结束，不得伪造成成功。

- [ ] **Step 6: Run redaction and repository checks**

  Run: `bash scripts/v0/redact-check.sh`

  Then: `git diff --check`

  Expected: Git 中无 Cookie、Token、Profile path、真实正文、完整 Prompt/response 或本地 evidence；diff 无 whitespace error。

- [ ] **Step 7: Commit the end-to-end verification harness**

  ```bash
  git add tests/e2e/v0 scripts/v0 apps/control-plane/.env.example workers/v0/README.md
  git commit -m "test: verify v0 end to end recovery flow"
  ```

## 10. Task 9：构建、部署检查与阶段收口

**Files:**

- Create: `apps/control-plane/vercel.json`
- Create: `apps/control-plane/.env.example`
- Create: `docs/engineering-journal/2026-07-18-v0.md`
- Create: `docs/spikes/2026-07-18-v0-decision-report.md`
- Modify: `docs/project-status.md`
- Modify: `docs/README.md`
- Modify: `README.md`

**Interfaces:**

- `.env.example` 只列变量名和用途：Supabase URL/anon key、server-only service role key variable、control-plane URL、contract version、parameter version；不得包含任何真实值。
- `vercel.json` 只声明 Next.js 构建/运行入口和必要的 server function 设置，不把 Worker、OpenCLI、Chrome Profile 或 Codex CLI 部署到 Vercel。
- Final Report 必须给出每项 V0 验收标准的 `pass`、`conditional` 或 `fail`，并链接到脱敏 evidence ref、测试命令和已知限制。

- [ ] **Step 1: Run all deterministic checks before deployment**

  Run: `cd apps/control-plane && npm ci`

  Then: `cd apps/control-plane && npm run lint && npm test && npm run build`

  Then: `python3 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v`

  Expected: all commands exit 0；任何失败先修复，不进入部署验收。

- [ ] **Step 2: Deploy the control plane to a dedicated V0 environment**

  Run: `supabase db push --db-url "$V0_SUPABASE_DB_URL"`

  Then: `cd apps/control-plane && vercel build`

  Then: `cd apps/control-plane && vercel deploy --prebuilt`

  Expected: 只部署 V0 测试项目；生产项目、真实来源配置、真实用户数据和真实凭据不被写入。

- [ ] **Step 3: Run post-deploy auth, Worker and recovery checks**

  Run: `V0_CONTROL_PLANE_URL="$V0_DEPLOYED_URL" python3 -m unittest discover -s tests/e2e/v0 -p 'test_*.py' -v`

  Expected: deployed control plane 与本地 Worker 完成 enrol/heartbeat/claim/result；普通用户不能读 admin/debug 数据；恢复测试没有重复 Canonical 或 checkpoint 越界。

- [ ] **Step 4: Write the engineering journal and decision report**

  `docs/engineering-journal/2026-07-18-v0.md` 记录每次真实尝试、失败分类、耗时、恢复动作和未决项；`docs/spikes/2026-07-18-v0-decision-report.md` 只记录脱敏计数、状态、测试结果和限制，不记录正文、URL、Profile、Cookie、Token、Prompt 或完整响应。

- [ ] **Step 5: Update project status and navigation**

  只有 Final Report 完成后才将 `docs/project-status.md` 的 Next gate 更新为 V0 结论；若为 conditional pass，必须把限制和进入 V1 前的补证据门槛写在状态页，不得只写“通过”。同步 `README.md`、`docs/README.md` 的当前阶段、入口和 V0 结果。

- [ ] **Step 6: Commit the V0 evidence and documentation**

  ```bash
  git add apps/control-plane/vercel.json apps/control-plane/.env.example docs/engineering-journal/2026-07-18-v0.md docs/spikes/2026-07-18-v0-decision-report.md docs/project-status.md docs/README.md README.md
  git commit -m "docs: record v0 validation result"
  ```

## 11. 全局测试与验收命令

实现完成后，按以下顺序运行，不跳过前置失败：

```bash
git diff --check
supabase db reset
supabase test db
cd apps/control-plane && npm test
cd apps/control-plane && npm run lint
cd apps/control-plane && npm run build
python3 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
python3 -m unittest discover -s tests/e2e/v0 -p 'test_*.py' -v
bash scripts/v0/redact-check.sh
```

通过标准：数据库/RLS、控制面 API、Worker、Active Adapter、Provider、管理员调试页和 E2E 全部通过；任何阻断级权限绕过、checkpoint 越界、事实丢失、重复写入、不可追溯结果或敏感信息泄漏均视为 V0 失败。

## 12. 回滚与恢复方案

- 应用回滚：V0 验证环境保留上一成功部署版本；发现控制面回归时切回该版本，禁止删除数据库记录或覆盖旧 task events。
- 数据回滚：不删除 raw/Canonical/structured/evidence；将受影响 task 标记为 `failed`，保留旧 checkpoint，由管理员从最后安全 checkpoint 创建新 attempt。
- Worker 回滚：撤销当前 Worker device secret，停止领取任务，部署上一版本 Worker；租约到期后由上一版本重新 claim。
- Schema 回滚：协议字段只向后兼容新增；不删除已写入字段。若新版本无法解析旧结果，保持 task failed/retryable_failed，先修复 parser 再重试。
- 真实数据安全：V0 真实网页 evidence 在仓库外受保护目录保存；V0 失败时只提交脱敏报告，不把本地 evidence 复制进 Git 或 Vercel。

## 13. 计划自检

- Spec 覆盖：范围、非目标、候选栈、角色/RLS、数据不变量、任务状态、采集、Provider、调试 UI、验收、交付物和阶段门禁均有对应 Task。
- 文件边界：生产控制面、Worker、协议、数据库、测试、脚本、工程日志和 Final Report 均有明确路径；没有把 Spike harness 直接列为运行时依赖。
- 接口一致：`source_id`、`task_id`、`attempt`、`safe_checkpoint`、`failure_class`、`media_source_message_ids` 在 contract、API、Worker 和验收中使用同一含义。
- 失败覆盖：权限、enrol replay、lease race、网络失败、OpenCLI freshness、timeout、Schema、Provider、持久化和恢复均有测试步骤。
- 安全覆盖：真实 URL/Profile/Cookie/Token/Prompt/完整响应不进入 cloud debug、Git 或部署日志；redaction check 在最终提交前运行。
- 门禁覆盖：本 Plan 不执行实现；只有用户批准本 Plan 后才创建生产目录、安装依赖、创建 V0 云端环境或运行真实端到端任务。
