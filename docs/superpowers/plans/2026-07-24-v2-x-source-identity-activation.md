# V2 X 来源身份解析与激活 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让已注册的本机 Worker 以受控 OpenCLI profile 读取，安全地将一个管理员登记的 X 来源从 `pending` 激活为 `resolved`，从而为一次真实持久化 E2E 建立合法前置条件。

**Architecture:** 新增一个最小 Supabase RPC，服务端在单一事务中核验来源、显式 Worker 绑定、参数版本、任务与 coverage 状态，并只写入规范化 handle。控制面提供仅限设备凭据的路由；本机 Python Worker 增加独立的 profile invoker 与 CLI 子命令。受限 shell runner 只协调本地私有输入和门禁，不领取任务、不采集帖子、不调用 Codex CLI。

**Tech Stack:** Supabase/Postgres PL/pgSQL + pgTAP、Next.js Route Handler + Vitest、Python 3.11 `unittest`、已锁定的本地 OpenCLI `twitter profile`、POSIX shell。

## Global Constraints

- 所有真实 X 访问只能使用 `.runtime/v2/opencli-collection/current/bin/opencli-v2-collection`，不得替换全局 `opencli`、调用 X REST API、使用普通用户 Token 或建设第二采集器。
- 身份解析只接受 `twitter profile` JSON 中唯一一行的 `screen_name`；对请求账号与结果均执行去 `@`、小写与合法 handle 校验，并要求精确相等。
- `account_id` 固定为规范化 handle；不得保存 profile JSON、帖子、URL、Cookie、浏览器路径、Prompt 或模型输出。
- 首次解析只允许来源为 `pending`、已明确绑定到调用 Worker、参数版本一致、没有 X 活动任务且 coverage 未初始化。相同身份的后续请求仅返回幂等结果，不写入；不一致请求永不覆盖已解析身份。
- 普通用户、未认证调用与未绑定 Worker 必须被拒绝。RPC 必须执行 `revoke all on function public.resolve_x_source_identity(uuid, uuid, text, text) from public, anon, authenticated;`，只向 `service_role` 授予 execute。
- 每个实现任务都先写失败测试、观察失败、再写最小实现；不得在测试前写生产代码。
- 实现、合并、推送、远程 migration、部署、identity resolution、窗口创建及真实 E2E 是独立检查点；不安装 scheduler/launchd/cron，不自动持续采集或部署生产。

---

### Task 1: 原子身份确认数据库契约

**Files:**

- Create: `supabase/migrations/019_v2_x_worker_identity_resolution.sql`
- Create: `supabase/tests/019_v2_x_worker_identity_resolution.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`

**Interfaces:**

- Produces `public.resolve_x_source_identity(p_source_id uuid, p_worker_id uuid, p_parameter_version text, p_account_id text) returns jsonb`.
- Success payload is exactly `{ source_id, account_id, resolution_status: "resolved", parameter_version, idempotent }`.
- Failure codes are `source_not_found`, `worker_not_authorized`, `source_parameter_version_mismatch`, `invalid_x_identity`, `x_identity_conflict`, and `x_identity_activation_blocked`.

- [ ] **Step 1: 写 pgTAP 失败断言。**

  在新测试中建立管理员、两个 Worker、一条 `pending` X 来源及显式 `authorized_worker_id`，然后断言目标 RPC 在 migration 未实现时不存在；预先写入下列最终行为断言：

  ```sql
  select is(
    (public.resolve_x_source_identity(v_source, v_worker, 'v2-identity', 'fixture_handle')->>'resolution_status'),
    'resolved',
    'matching bound worker resolves a pending X source'
  );
  select throws_ok(
    $$select public.resolve_x_source_identity(
      (select (payload->>'id')::uuid from x_identity_source),
      '00000000-0000-0000-0000-000000019002',
      'v2-identity', 'fixture_handle'
    )$$,
    '42501', 'worker_not_authorized',
    'a worker not explicitly bound to the source cannot resolve it'
  );
  ```

  同一文件还必须覆盖：参数版本不一致、空/带 `@`/大写之外的非法身份、已有 coverage 的首次解析、存在 `queued` 或 `leased` `x_sync` 的首次解析、已解析后不同 identity 的覆盖，以及已解析后相同 identity 的 `idempotent=true`。

- [ ] **Step 2: 运行测试，确认它因 RPC 不存在而失败。**

  Run: `SUPABASE_DISABLE_TELEMETRY=1 supabase test db --file supabase/tests/019_v2_x_worker_identity_resolution.sql`

  Expected: FAIL，原因是 `resolve_x_source_identity` 尚不存在；不得通过删减断言把失败变为成功。

- [ ] **Step 3: 写最小 migration。**

  新 migration 创建 `security definer` RPC，使用 `set search_path = public, extensions`。它必须先锁定 `sources`、`x_source_profiles`，并按照以下顺序处理：

  ```sql
  -- worker must equal sources.authorized_worker_id; NULL is not an authorization.
  if v_source.authorized_worker_id is distinct from p_worker_id then
    raise exception 'worker_not_authorized' using errcode = '42501';
  end if;
  if v_profile.resolution_status = 'resolved' then
    if v_profile.account_id = v_normalized_account
       and v_source.parameter_version = p_parameter_version then
      return jsonb_build_object(
        'source_id', p_source_id::text,
        'account_id', v_profile.account_id,
        'resolution_status', 'resolved',
        'parameter_version', v_source.parameter_version,
        'idempotent', true
      );
    end if;
    raise exception 'x_identity_conflict' using errcode = '22023';
  end if;
  -- pending-only mutation: reject coverage or queued/leased/retryable_failed x_sync.
  update public.x_source_profiles
  set account_id = v_normalized_account, resolution_status = 'resolved'
  where source_id = p_source_id and resolution_status = 'pending';
  ```

  只接受已经是小写、不带 `@` 的 `[a-z0-9_]{1,15}` 账号值；由本机先规范化，但数据库再作防御性验证。RPC 仅写 `account_id` 与 `resolution_status`，不写 profile 正文或审计载荷。撤销 `public/anon/authenticated` 的 execute 权限，仅授予 `service_role`。同步更新手写 `Database` 类型中的 RPC 参数和 JSON 返回类型。

- [ ] **Step 4: 运行新测试和完整数据库回归，确认通过。**

  Run:

  ```bash
  SUPABASE_DISABLE_TELEMETRY=1 supabase db reset
  SUPABASE_DISABLE_TELEMETRY=1 supabase test db
  ```

  Expected: 新 pgTAP 文件与全部既有数据库测试通过；现有 Discord/X 迁移不失败。

- [ ] **Step 5: 检查 SQL 安全边界并提交。**

  Run:

  ```bash
  rg -n 'resolve_x_source_identity|grant execute|revoke all' supabase/migrations/019_v2_x_worker_identity_resolution.sql
  git diff --check
  git add supabase/migrations/019_v2_x_worker_identity_resolution.sql supabase/tests/019_v2_x_worker_identity_resolution.sql apps/control-plane/src/lib/db/types.ts
  git commit -m "feat(v2): resolve X source identities atomically"
  ```

### Task 2: Worker 身份确认 API 与控制面测试

**Files:**

- Create: `apps/control-plane/src/lib/db/repositories/x-identities.ts`
- Create: `apps/control-plane/src/app/api/worker/x-sources/[sourceId]/resolve-identity/route.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

- `resolveXSourceIdentity(input: { sourceId: string; workerId: string; parameterVersion: string; accountId: string }): Promise<{ sourceId: string; accountId: string; resolutionStatus: "resolved"; parameterVersion: string; idempotent: boolean }>`.
- Route accepts exactly `{ parameter_version, account_id }` and returns only `{ identity }`.

- [ ] **Step 1: 为路由写失败的集成测试。**

  在 `api.integration.test.ts` mock 新 repository，并增加：未认证请求返回 `401 { error: "unauthorized" }`、多余字段/缺字段返回 `422 { error: "invalid_x_identity_resolution" }`、已认证 Worker 将来自 URL 的 source ID 和 payload 传给 repository、`worker_not_authorized` 映射 `403`、冲突/activation blocked 映射 `409`，成功响应不含 `profile`、`url`、`cookie`、`source_key` 或原始请求账号。

- [ ] **Step 2: 运行测试，确认新模块/路由不存在。**

  Run: `cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts`

  Expected: FAIL，因无法导入新 repository/route 或路由尚未注册到测试。

- [ ] **Step 3: 实现 repository 与 route。**

  Repository 仅调用 Task 1 RPC 并严格验证返回对象的完整键集合。Route 使用现有 `authenticateWorker`，拒绝非字符串或不匹配 `/^[a-z0-9_]{1,15}$/` 的 `account_id`，不自行小写或去 `@`，从而确保客户端规范化动作可被测试。错误响应只使用固定枚举；不得把 SQL、来源 URL 或输入值回显。

  ```ts
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await parseIdentityBody(request);
  if (!body) return NextResponse.json({ error: "invalid_x_identity_resolution" }, { status: 422 });
  const identity = await resolveXSourceIdentity({
    sourceId,
    workerId: worker.id,
    parameterVersion: body.parameterVersion,
    accountId: body.accountId,
  });
  return NextResponse.json({ identity });
  ```

- [ ] **Step 4: 运行控制面测试和类型检查。**

  Run:

  ```bash
  cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts src/lib/contracts.test.ts
  cd apps/control-plane && npm run lint && npm run build
  ```

  Expected: API、lint 与 production build 通过；普通用户权限测试仍为绿。

- [ ] **Step 5: 提交。**

  ```bash
  git add apps/control-plane/src/lib/db/repositories/x-identities.ts apps/control-plane/src/app/api/worker/x-sources/[sourceId]/resolve-identity/route.ts apps/control-plane/src/app/api/api.integration.test.ts
  git commit -m "feat(v2): add worker X identity resolution API"
  ```

### Task 3: 本机 profile 验证与一次性 CLI

**Files:**

- Create: `workers/v0/src/invest_hub_worker/x_identity.py`
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`
- Modify: `workers/v0/src/invest_hub_worker/cli.py`
- Create: `workers/v0/tests/test_x_identity.py`
- Modify: `workers/v0/tests/test_protocol.py`
- Modify: `workers/v0/tests/test_cli.py`

**Interfaces:**

- `normalize_x_handle(value: str) -> str` returns a lowercase `[a-z0-9_]{1,15}` handle or raises `IdentityResolutionError("invalid_x_identity")`.
- `OpenCLIProfileInvoker(executable).resolve(requested_handle: str) -> str` invokes only `twitter profile <handle> --site-session persistent -f json` and returns the verified normalized `screen_name`.
- `resolve_configured_x_identity(config: LocalWorkerConfig, protocol: WorkerProtocol, executable: str) -> dict[str, object]` performs local verification then `protocol.resolve_x_source_identity(...)`.
- `WorkerProtocol.resolve_x_source_identity(source_id: str, parameter_version: str, account_id: str) -> dict[str, object]` calls the Task 2 endpoint.

- [ ] **Step 1: 写 Worker 失败测试。**

  `test_x_identity.py` 先覆盖以下最小行为：

  ```python
  def test_profile_invoker_rejects_a_screen_name_different_from_requested_handle():
      invoker = OpenCLIProfileInvoker("fixture-opencli", runner=lambda *_a, **_k: completed_profile("other"))
      with self.assertRaisesRegex(IdentityResolutionError, "identity_mismatch"):
          invoker.resolve("fixture_handle")

  def test_resolution_posts_only_normalized_identity_to_protocol():
      result = resolve_configured_x_identity(config, protocol, executable="fixture-opencli")
      self.assertEqual(protocol.calls, [("x-source", "v2-test", "fixture_handle")])
      self.assertEqual(result["resolution_status"], "resolved")
  ```

  还要覆盖：`@` 与大写输入规范化、profile JSON 非单行/缺少 `screen_name`、子进程非零、超时、配置非 X、profile 行返回 `@` 形式、协议返回额外字段、以及没有任何对 Codex Provider、EvidenceStore、任务 claim 或 capture/persist 方法的调用。

- [ ] **Step 2: 运行 Worker 测试，确认失败。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_identity.py -v`

  Expected: FAIL，原因是 `x_identity` 模块和 Protocol 方法尚不存在。

- [ ] **Step 3: 写最小 Worker 实现。**

  `OpenCLIProfileInvoker` 使用 `subprocess.run(command, capture_output=True, text=True, timeout=60, check=False)`，从 stdout 解析严格的单元素数组，且仅读取 `screen_name`。异常统一映射为 `IdentityResolutionError` 的枚举代码；不得传播 stderr、URL 或原始 JSON。

  ```python
  command = [self.executable, "twitter", "profile", requested_handle,
             "--site-session", "persistent", "-f", "json"]
  row = _single_profile_row(result.stdout)
  observed = normalize_x_handle(str(row.get("screen_name") or ""))
  if observed != requested:
      raise IdentityResolutionError("identity_mismatch")
  ```

  在 `cli.py` 添加 `resolve-x-identity` 子命令，接受 `--config`、`--credential`、`--source-id`、`--opencli-executable`、`--evidence-dir` 与 `--worker-name`。它要求 `V2_REAL_X_ACK=authorized`、配置中 source ID 唯一且为 X；不读取 prompt 或 contract，不调用 `Worker.run_once`。它只在 owner-only evidence 目录追加脱敏事件 `{ occurred_at, contract_version, result_code }`，标准输出仅为 `{ "status", "resolution_status", "idempotent", "error" }`，不含 source ID 或账号。

- [ ] **Step 4: 扩展协议测试并运行聚焦回归。**

  在 `test_protocol.py` 确认 URL 为 `api/worker/x-sources/<source-id>/resolve-identity`、Authorization 来自 owner-only credential、请求体恰为 `{"parameter_version": "v2-test", "account_id": "fixture_handle"}`，并确认 409 映射 `RemoteConflict`。

  Run:

  ```bash
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_x_identity.py workers/v0/tests/test_protocol.py workers/v0/tests/test_cli.py -v
  ```

  Expected: PASS，且无真实 OpenCLI、网络、Codex 或数据库调用。

- [ ] **Step 5: 提交。**

  ```bash
  git add workers/v0/src/invest_hub_worker/x_identity.py workers/v0/src/invest_hub_worker/protocol.py workers/v0/src/invest_hub_worker/cli.py workers/v0/tests/test_x_identity.py workers/v0/tests/test_protocol.py workers/v0/tests/test_cli.py
  git commit -m "feat(v2): verify local X source identities"
  ```

### Task 4: 受限本地 runner、回归与操作记录

**Files:**

- Create: `scripts/v2/run-local-x-identity-resolution.sh`
- Create: `scripts/v2/test-local-x-identity-resolution-gate.mjs`
- Modify: `scripts/v2/run-v2-e2e.sh`
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-07-23-v2-x-local-implementation.md`

**Interfaces:**

- Runner requires `--opencli-executable`, `--source-config`, `--credential`, `--source-id`, `--evidence-dir`, `--approve-identity-resolution`, `V2_REAL_X_ACK=authorized`, and executable `V2_PYTHON_BIN`.
- It accepts only the dedicated `.runtime/v2/opencli-collection/current/bin/opencli-v2-collection` path and Git-ignored owner-only config/credential/evidence paths.

- [ ] **Step 1: 写 runner 门禁失败测试。**

  `test-local-x-identity-resolution-gate.mjs` 必须静态断言 runner：缺少任一参数时在调用 Python 前退出；拒绝 global `opencli`、`--approve-identity-resolution` 缺失、ACK 不匹配、非忽略路径、非 executable Python、以及 `run-once`/`run-scheduled`/`codex`/`twitter collection` 字样作为执行命令。

- [ ] **Step 2: 运行门禁测试，确认新脚本不存在。**

  Run: `node scripts/v2/test-local-x-identity-resolution-gate.mjs`

  Expected: FAIL，因为 runner 尚不存在。

- [ ] **Step 3: 实现最小 shell runner。**

  脚本复用现有本地 Collection runtime 验证，并通过 `git check-ignore -q` 与文件权限检查私有输入。最终仅执行：

  ```bash
  V2_REAL_X_ACK=authorized PYTHONPATH="$repo_root/workers/v0/src" "$V2_PYTHON_BIN" \
    -m invest_hub_worker.cli resolve-x-identity \
    --config "$source_config" --credential "$credential" --source-id "$source_id" --evidence-dir "$evidence_dir" \
    --opencli-executable "$opencli_executable" --worker-name "$worker_name"
  ```

  不创建目录外文件、不安装运行时、不写 prompt、不开 scheduler；evidence 只能追加 owner-only 的 `{ occurred_at, contract_version, result_code }`，不得出现账号、profile 内容、URL 或完整响应。错误输出只能是固定门禁或 CLI 枚举。

- [ ] **Step 4: 运行完整本地回归与脱敏检查。**

  Run:

  ```bash
  bash scripts/v2/run-v2-e2e.sh
  node scripts/v2/test-local-x-identity-resolution-gate.mjs
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
  cd apps/control-plane && npm test && npm run lint && npm run build
  SUPABASE_DISABLE_TELEMETRY=1 supabase test db
  bash scripts/v0/redact-check.sh
  git diff --check
  ```

  Expected: 全部通过；`.runtime/`、真实账户、profile 输出、凭据和真实 evidence 均不出现在 Git 状态。

- [ ] **Step 5: 更新事实记录并提交。**

  文档只记录“identity resolver 本地实现与拒绝门禁已通过、真实远程执行未开始”；不得把真实身份解析、迁移、部署或 E2E 表述为完成。

  ```bash
  git add scripts/v2/run-local-x-identity-resolution.sh scripts/v2/test-local-x-identity-resolution-gate.mjs scripts/v2/run-v2-e2e.sh docs/project-status.md docs/engineering-journal/2026-07-23-v2-x-local-implementation.md
  git commit -m "test(v2): gate local X identity resolution"
  ```

### Task 5: 审核、合并与受限远程验收

**Files:**

- Verify: `supabase/migrations/012_v2_x_sources_and_posts.sql` through `019_v2_x_worker_identity_resolution.sql`
- Verify: `apps/control-plane/vercel.json`
- Verify: `docs/superpowers/specs/2026-07-24-v2-x-source-identity-activation-design.md`
- Verify: `docs/superpowers/plans/2026-07-24-v2-x-source-identity-activation.md`

**Interfaces:**

- Remote sequence is fixed: merged `main` → remote migration list → `db push` → deployed control plane → registered/bound Worker → identity resolution → coverage initialization → one manual task → one real E2E.

- [ ] **Step 1: 完成分支审查和合并前验证。**

  Run the full Task 4 suite, inspect `git diff main...HEAD`, run `bash scripts/v0/redact-check.sh`, and verify all required source/plan/status docs. Use the project’s finishing-branch workflow; do not merge with failing tests or unrelated worktree changes.

- [ ] **Step 2: 合并后核对远程前置状态。**

  On `main`, run:

  ```bash
  git status -sb
  git log --oneline origin/main..main
  SUPABASE_DISABLE_TELEMETRY=1 supabase migration list
  ```

  Confirm the selected Supabase project is the intended isolated project, migrations `012`–`018` are absent/present exactly as reported, and no other operator is running `db push`. Do not use Dashboard SQL, `migration repair`, or a production project as a substitute.

- [ ] **Step 3: 推送、迁移与部署。**

  Only after Step 2’s target confirmation and the user’s deployment authorization are recorded, execute sequentially:

  ```bash
  git push origin main
  SUPABASE_DISABLE_TELEMETRY=1 supabase db push
  cd apps/control-plane && vercel --prod
  ```

  Verify `supabase migration list` shows `019` applied, deployment reports Ready, `/admin/sources` exposes the X controls, `/x` renders its safe empty state, and a normal user gets 403 from the new Worker-only endpoint. On migration/deployment failure, stop; rollback is disable X sources and cancel only unfinished `x_sync`, never drop completed facts or alter Discord data.

- [ ] **Step 4: 执行一次真实、有限的激活与持久化验收。**

  In the deployed admin UI: create or select exactly one X source, bind the registered Worker, then run `run-local-x-identity-resolution.sh` once. Confirm only `resolved` status is returned. Initialize exactly one prior Shanghai coverage boundary, click one manual refresh (which fixes `end_at` server-side), and run the existing `run-local-collection-real-e2e.sh` once.

  Success evidence is limited to: identity result enum, one task terminal status, aggregate raw/canonical/analysis/segment counts, receipt stop reason, fixed range boundaries, safe coverage result, `/x` reader status, ordinary-user admin denial, and source-specific no-secret redaction check. Do not preserve actual posts, account names, URLs, Cookie/Profile paths, Prompt, model output or full HTTP responses in Git or public logs.

- [ ] **Step 5: 记录结论并提交事实文档。**

  Update `docs/project-status.md` and the V2 engineering journal with pass/fail facts and explicitly state remaining unverified post-type/recovery/normal-reader coverage. Run `bash scripts/v0/redact-check.sh`, `git diff --check`, and a clean-status check before committing the documentation-only result. Push only after the user authorizes publication of that final documentation commit.

## Plan self-review

- Spec coverage: Task 1 enforces atomic state and idempotency; Task 2 isolates the Worker API; Task 3 proves the local OpenCLI profile identity; Task 4 proves no accidental task/model/collection execution; Task 5 sequences merge, migration, deployment and one real E2E.
- Security coverage: all mutation paths require an explicitly bound Worker, service-role-only RPC, typed validation and safe response projections; raw X/profile data never crosses the local boundary.
- Scope check: this plan adds only the missing identity-activation bridge. It does not change X collection receipts, task semantics, Codex understanding, Reader DTOs, scheduling, Discord behavior or automatic operation.
