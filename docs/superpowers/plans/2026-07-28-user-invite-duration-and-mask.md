# 普通用户邀请码时长与掩码列表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 管理员可为每个普通用户邀请码配置小时级有效期，并在刷新后查看安全掩码、时长、倒计时和状态，同时保持 Worker 长随机邀请码不变。

**Architecture:** 迁移在 `invites` 上保存最小展示元数据 `code_mask` 与 `validity_hours`，并增加仅保存来源 HMAC 的失败兑换限流状态。服务端将普通用户邀请码生成、带私钥的验证值、过期基准、列表 DTO 和兑换保护集中在 invite 模块；管理 UI 只传时长、一次性显示完整码，并从安全 DTO 渲染倒计时列表。

**Tech Stack:** Next.js App Router、TypeScript、React、Node `crypto`、Supabase/Postgres 迁移与 pgTAP、Vitest、现有 CSS；不新增生产依赖。

## Global Constraints

- 本改动只影响 `purpose = user` 的邀请码；Worker 继续使用原有长随机邀请码和 1 小时流程。
- 新普通用户邀请码固定为 8 位 ASCII 字母数字，且每个码同时包含大写、小写和数字；字符类别不得固定位置。
- 时长由管理员每次创建时输入；默认 `24`，只接受 `1–168` 的整数。
- 服务端必须以同一 `created_at` 基准计算 `expires_at`；浏览器倒计时不是授权依据。
- 完整码只在成功创建的单次响应中返回；数据库、日志、列表 DTO、页面刷新和测试输出均不得保存或回显完整码。
- 持久化掩码固定为前两位 + `••••` + 后两位，例如 `Ab••••7Q`；列表不得返回 `code_hash`。
- 新普通用户验证码 hash 必须由 server-only `INVITE_CODE_PEPPER` 参与计算；该变量不得使用 `NEXT_PUBLIC_` 前缀、不得进入 Git 或日志。旧邀请码在其剩余有效期内必须仍可兑换。
- 兑换端点对失败尝试返回同一 `invalid_invite` 错误，并以来源 HMAC 进行 `5 次失败 / 15 分钟` 限流；不得保存原始 IP。
- 所有新增管理 API 继续要求管理员角色，普通用户、未认证请求和 Worker 凭据均不能读取邀请码列表。
- 发布前运行数据库、控制面、lint、build、redaction 与 whitespace 验证；远程环境变量配置和部署另需明确发布授权。

---

## File Structure

- `supabase/migrations/20260728090000_user_invite_duration_and_mask.sql`: 新增普通用户邀请码展示元数据、失败兑换限流表/RPC 与仅 `service_role` 的权限。
- `supabase/tests/021_user_invite_duration_and_mask.sql`: pgTAP 验证列约束、历史兼容、限流原子语义和 RLS。
- `apps/control-plane/src/lib/db/types.ts`: 手写 Supabase `invites` 与限流 RPC 类型。
- `apps/control-plane/src/lib/db/repositories/invites.ts`: 创建记录携带掩码/时长/同一创建时刻，读取最近普通用户邀请码安全投影。
- `apps/control-plane/src/lib/db/repositories/invite-rate-limits.ts`: 只调用服务端 RPC 的限流读取与失败记录边界。
- `apps/control-plane/src/lib/auth/invite-code.ts`: 普通用户 8 位码、掩码、HMAC 验证值与旧 SHA-256 验证值的纯函数。
- `apps/control-plane/src/lib/auth/invite-code.test.ts`: 格式、掩码、HMAC、Worker 兼容与不固定位置测试。
- `apps/control-plane/src/lib/auth/invites.ts`: 普通用户/Worker 创建路径分离、旧码兑换兼容、限流后的账户创建流程。
- `apps/control-plane/src/lib/auth/invites.test.ts`: 创建基准、碰撞重试、单次兑换和失败限流编排测试。
- `apps/control-plane/src/app/api/admin/invites/route.ts`: 管理员 `POST` 创建与 `GET` 最近普通用户邀请码安全 DTO。
- `apps/control-plane/src/app/api/auth/invite/route.ts`: 无泄露的兑换错误与来源限流接入。
- `apps/control-plane/src/app/api/api.integration.test.ts`: 管理员 API、列表授权、安全响应与兑换 API 回归。
- `apps/control-plane/src/components/admin/UserInviteForm.tsx`: 时长输入、一次性明码展示、列表加载与创建后的刷新。
- `apps/control-plane/src/components/admin/UserInviteList.tsx`: 倒计时、状态投影和无掩码历史记录显示。
- `apps/control-plane/src/components/admin/user-invite.ts`: 浏览器安全响应解析、时长校验与列表 DTO 类型。
- `apps/control-plane/src/components/admin/user-invite-list.test.tsx`: 静态渲染与模拟时间下的倒计时/状态测试。
- `apps/control-plane/src/app/globals.css`: 邀请码表格、状态标签和移动端可读样式。
- `apps/control-plane/.env.example`、`apps/control-plane/src/lib/deployment-contract.test.ts`: 增加并锁定 server-only pepper 环境契约。
- `docs/engineering-journal/2026-07-28-user-invite-duration-and-mask.md`、`docs/project-status.md`: 记录范围、验证结果和部署前置条件。

## Task 1: 建立持久化元数据与原子失败兑换限流

**Files:**

- Create: `supabase/tests/021_user_invite_duration_and_mask.sql`
- Create: `supabase/migrations/20260728090000_user_invite_duration_and_mask.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`

**Interfaces:**

```sql
-- 新列均允许旧记录为 null；新普通用户记录由应用层同时写入两列。
public.invites.code_mask text null
public.invites.validity_hours integer null check (validity_hours between 1 and 168)

public.can_attempt_invite_redemption(p_source_hash text, p_now timestamptz)
  returns boolean
public.record_failed_invite_redemption(p_source_hash text, p_now timestamptz)
  returns boolean -- 第五次失败时返回 false，并封锁 15 分钟
```

- [ ] **Step 1: 写失败的 pgTAP 测试。**

  在新测试文件以固定 UUID 与固定时间插入：一条无元数据的旧邀请、一条含 `Ab••••7Q`/`24` 的新普通用户邀请和一条 Worker 邀请。断言新列存在、`validity_hours = 0` 与 `169` 被拒绝、旧行仍可插入及消费、管理员可读新列而普通用户不能读 `invites`。用同一个 `source_hash` 连续调用失败 RPC 五次，断言前四次允许、第五次返回 `false`、15 分钟前仍拒绝、15 分钟后恢复允许；不同 hash 互不影响。

  ```sql
  select throws_ok(
    $$insert into public.invites (code_hash, purpose, expires_at, validity_hours)
      values ('fixture-invalid-hours', 'user', '2099-01-02T00:00:00Z', 169)$$,
    '23514', null, 'invite duration has an upper bound'
  );
  select is(public.record_failed_invite_redemption('source-hmac-a', '2099-01-01T00:00:00Z')::text, 'true', 'first failure is allowed');
  ```

- [ ] **Step 2: 运行新测试，确认它失败。**

  Run: `SUPABASE_DISABLE_TELEMETRY=1 supabase test db --file supabase/tests/021_user_invite_duration_and_mask.sql`

  Expected: FAIL，因为新增列、表和 RPC 尚不存在；不得通过删减断言使其通过。

- [ ] **Step 3: 写最小 migration 与手写类型。**

  创建限流表 `invite_redemption_attempts(source_hash text primary key, window_started_at timestamptz, failure_count integer check (failure_count > 0), blocked_until timestamptz null, expires_at timestamptz)`；每个 RPC 调用先删除 `expires_at <= p_now` 的记录，永不保存原始 IP。`record_failed_invite_redemption` 必须使用单条 `insert ... on conflict ... do update` 或行锁，实现 15 分钟窗口、第五次开始封锁 15 分钟，并把过期清理时间延长至当前时刻后 1 天。

  对 `invites` 新列添加 `code_mask` 格式检查：仅允许 `^[A-Za-z0-9]{2}••••[A-Za-z0-9]{2}$`；保留 null 以兼容历史记录。撤销两个 RPC 对 `public`、`anon`、`authenticated` 的执行权限，只授予 `service_role`。同步 `Database` 类型：`Row`/`Insert` 有可空 `code_mask`、`validity_hours`，Functions 含两个限流 RPC 的参数与返回值。

- [ ] **Step 4: 验证数据库迁移和回归。**

  Run:

  ```bash
  SUPABASE_DISABLE_TELEMETRY=1 supabase db reset
  SUPABASE_DISABLE_TELEMETRY=1 supabase test db --file supabase/tests/021_user_invite_duration_and_mask.sql
  SUPABASE_DISABLE_TELEMETRY=1 supabase test db
  ```

  Expected: 新文件和全部既有 pgTAP 均通过；既有 `consume_invite`、Worker 和 RLS 断言不回退。

- [ ] **Step 5: 提交数据库边界。**

  ```bash
  git add supabase/migrations/20260728090000_user_invite_duration_and_mask.sql supabase/tests/021_user_invite_duration_and_mask.sql apps/control-plane/src/lib/db/types.ts
  git commit -m "feat: persist user invite duration and throttle failures"
  ```

## Task 2: 固化普通用户码生成、服务端计时与安全兑换流程

**Files:**

- Create: `apps/control-plane/src/lib/auth/invite-code.ts`
- Create: `apps/control-plane/src/lib/auth/invite-code.test.ts`
- Create: `apps/control-plane/src/lib/auth/invites.test.ts`
- Create: `apps/control-plane/src/lib/db/repositories/invite-rate-limits.ts`
- Modify: `apps/control-plane/src/lib/auth/invites.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/invites.ts`
- Modify: `apps/control-plane/.env.example`
- Modify: `apps/control-plane/src/lib/deployment-contract.test.ts`

**Interfaces:**

```ts
export type UserInviteCode = { code: string; mask: string };
export function generateUserInviteCode(): UserInviteCode;
export function hashUserInviteCode(code: string): string; // HMAC-SHA-256 with INVITE_CODE_PEPPER
export function hashLegacyInviteCode(code: string): string; // SHA-256; compatibility only
export function isValidUserInviteCode(code: string): boolean;

export type RecentUserInvite = {
  codeMask: string | null;
  validityHours: number | null;
  createdAt: string;
  expiresAt: string;
  consumedAt: string | null;
};
export async function listRecentUserInvites(limit?: number): Promise<RecentUserInvite[]>;
```

- [ ] **Step 1: 写失败的码策略、repository 和认证编排测试。**

  在 `invite-code.test.ts` 生成至少 200 个码，逐一断言长度 `8`、`/^[A-Za-z0-9]{8}$/`、大写/小写/数字均存在、掩码等于 `code.slice(0, 2) + "••••" + code.slice(-2)`，并断言这些类别不会被固定到特定下标。在 `invites.test.ts` 用固定 `now = "2099-01-01T00:00:00.000Z"` 断言创建输入同时传 `createdAt` 与 `expiresAt = "2099-01-02T00:00:00.000Z"`，以及 `validityHours: 24`、掩码和 HMAC hash；模拟一次唯一冲突后成功重试。

  还要断言 Worker 创建仍调用原长随机 SHA-256 路径；普通用户兑换先尝试 HMAC、再兼容旧 SHA-256，并且任何兑换失败只返回内部统一 `invalid_invite` 给路由层。模拟限流被封锁时，不得调用 `admin.auth.admin.createUser`。

- [ ] **Step 2: 运行聚焦测试，确认它们失败。**

  Run: `cd apps/control-plane && npm test -- --run src/lib/auth/invite-code.test.ts src/lib/auth/invites.test.ts src/lib/deployment-contract.test.ts`

  Expected: FAIL，因为码策略、pepper 环境契约、限流 repository 和分离后的普通用户创建路径不存在。

- [ ] **Step 3: 实现无位置偏置的 8 位码和 invite 服务边界。**

  `generateUserInviteCode` 从每个类别各抽一个字符，再从全字符集抽其余 5 个字符，使用 `randomInt` 的 Fisher–Yates shuffle 打散 8 个位置。不得通过把类别固定在首尾来满足格式。`hashUserInviteCode` 使用 `createHmac("sha256", requiredInvitePepper())`；缺少 `INVITE_CODE_PEPPER` 时服务器启动路径明确失败。`hashLegacyInviteCode` 保留当前 SHA-256 算法，仅用于已有记录兼容和 Worker。

  将现有统一 `createOneTimeInvite` 拆成普通用户与 Worker 的明确入口。普通用户入口接收 `{ expiresInHours, createdBy, now? }`，在生成码后以同一 `now` 写入 `created_at` 和 `expires_at`，并在唯一冲突后最多重试 3 次；Worker 入口保留现有 `randomBytes(24).toString("base64url")` 和调用方提供的过期时刻。repository 的普通用户列表查询固定 `purpose = "user"`、`created_at desc`、`limit 20`，只投影 `code_mask`、`validity_hours`、`created_at`、`expires_at`、`consumed_at`。

  `invite-rate-limits.ts` 只把服务器计算出的来源 HMAC 交给两个 RPC。兑换流程先检查是否允许，再创建账户并原子消费邀请码；无效/过期/已消费的结果记录失败并删除刚创建的账户。正常账户/配置失败保留内部可诊断结果，但 API 不得把邀请码状态差异返回给浏览器。

- [ ] **Step 4: 扩展环境模板并通过聚焦测试。**

  在 `.env.example` 添加不含真实值的：

  ```dotenv
  # Server-only HMAC pepper for ordinary-user invite verification; never expose or commit its value.
  INVITE_CODE_PEPPER=
  ```

  更新部署契约测试的期望顺序，运行：

  ```bash
  cd apps/control-plane && npm test -- --run src/lib/auth/invite-code.test.ts src/lib/auth/invites.test.ts src/lib/deployment-contract.test.ts
  ```

  Expected: PASS；测试只用人工 fixture pepper，断言或错误输出不包含真实邀请码或 secret。

- [ ] **Step 5: 提交服务端安全契约。**

  ```bash
  git add apps/control-plane/src/lib/auth/invite-code.ts apps/control-plane/src/lib/auth/invite-code.test.ts apps/control-plane/src/lib/auth/invites.ts apps/control-plane/src/lib/auth/invites.test.ts apps/control-plane/src/lib/db/repositories/invites.ts apps/control-plane/src/lib/db/repositories/invite-rate-limits.ts apps/control-plane/.env.example apps/control-plane/src/lib/deployment-contract.test.ts
  git commit -m "feat: secure configurable user invites"
  ```

## Task 3: 提供安全管理 API 与可刷新倒计时列表

**Files:**

- Modify: `apps/control-plane/src/app/api/admin/invites/route.ts`
- Modify: `apps/control-plane/src/app/api/auth/invite/route.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`
- Modify: `apps/control-plane/src/components/admin/user-invite.ts`
- Modify: `apps/control-plane/src/components/admin/UserInviteForm.tsx`
- Create: `apps/control-plane/src/components/admin/UserInviteList.tsx`
- Create: `apps/control-plane/src/components/admin/user-invite-list.test.tsx`
- Modify: `apps/control-plane/src/app/globals.css`

**Interfaces:**

```ts
type UserInviteListResponse = {
  invites: Array<{
    code_mask: string | null;
    validity_hours: number | null;
    created_at: string;
    expires_at: string;
    consumed_at: string | null;
  }>;
};

export function inviteDisplayState(invite: UserInviteListItem, now: Date):
  { label: "有效"; remaining: string } |
  { label: "已过期"; remaining: "已过期" } |
  { label: "已使用"; remaining: "已使用" };
```

- [ ] **Step 1: 写失败的 API 和 UI 测试。**

  在 API integration 测试中断言：管理员 `POST /api/admin/invites` 对 `{ purpose: "user", expires_in_hours: 2 }` 返回 `201`、完整 `code`、`expires_at`，并把 `2` 传给普通用户创建服务；`0`、`1.5`、`169` 和未知字段返回 `422`。管理员 `GET` 返回最多 20 条安全 DTO，且没有 `code_hash` 或 `code`；普通用户/未认证 `GET` 返回既有 `403`/`401` 门禁。`POST /api/auth/invite` 对错误码、过期码、已使用码和被限流尝试都返回同一 `{ error: "invalid_invite" }` 与同一 HTTP `400`。

  在列表组件测试中使用 `vi.useFakeTimers()` 固定 `2099-01-01T00:00:00Z`，断言未消费未来记录显示掩码、`24 小时` 与递减 `01:00:00`；消费记录优先显示“已使用”；未消费且到期记录显示“已过期”；`codeMask: null` 显示“旧邀请码（无掩码）”。静态表单测试断言 label 为“有效时长”、默认值为 `24`、按钮随值显示“创建 2 小时邀请码”，非法值禁用提交。

- [ ] **Step 2: 运行聚焦测试，确认它们失败。**

  Run: `cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts src/components/admin/user-invite-list.test.tsx src/app/admin/admin-ui.test.tsx`

  Expected: FAIL，因为 GET 列表、时长表单、倒计时组件和统一兑换错误尚未实现。

- [ ] **Step 3: 实现严格 DTO、列表与倒计时。**

  管理路由继续先调用 `requireRole("admin")`。`POST` 对 JSON body 做精确键、purpose 和整数校验；Worker 请求继续走原有长随机码与既有时长校验，现有 Worker 表单仍发送 `1` 小时，普通用户才使用 Task 2 的新入口。`GET` 只调用 `listRecentUserInvites(20)` 并按上述 snake_case DTO 返回。任何 repository 错误统一映射为既有通用 `503`，不回显 SQL 或邀请码信息。

  兑换路由从受信任请求头取得来源地址，立即在服务端 HMAC 后传入认证服务；不可用时使用固定的 `unknown` 来源值，绝不将请求头原文存入数据库。所有邀请码失败统一返回 `400 { error: "invalid_invite" }`。

  `UserInviteForm` 使用 `type="number"`、`min={1}`、`max={168}`、`step={1}` 和可见说明“生成后立即开始计时”。成功时只在本地 state 保存完整码，同时重新请求 GET 列表；列表加载失败显示通用可重试消息，不清空已显示的一次性成功码。`UserInviteList` 每秒从 `expires_at` 计算剩余秒数并在零点切换状态；它不接收或请求完整码。新增 CSS 使用响应式可横向滚动表格、状态标签和至少 44px 的可操作输入/按钮目标。

- [ ] **Step 4: 运行控制面聚焦回归。**

  Run:

  ```bash
  cd apps/control-plane && npm test -- --run src/app/api/api.integration.test.ts src/components/admin/user-invite-list.test.tsx src/app/admin/admin-ui.test.tsx
  cd apps/control-plane && npm test -- --run src/components/admin
  ```

  Expected: PASS；包括既有 Worker 邀请响应解析、普通用户管理员阻断和新普通用户邀请码列表边界。

- [ ] **Step 5: 提交 API 与管理 UI。**

  ```bash
  git add apps/control-plane/src/app/api/admin/invites/route.ts apps/control-plane/src/app/api/auth/invite/route.ts apps/control-plane/src/app/api/api.integration.test.ts apps/control-plane/src/components/admin/user-invite.ts apps/control-plane/src/components/admin/UserInviteForm.tsx apps/control-plane/src/components/admin/UserInviteList.tsx apps/control-plane/src/components/admin/user-invite-list.test.tsx apps/control-plane/src/app/globals.css
  git commit -m "feat: show masked user invite countdowns"
  ```

## Task 4: 记录实现证据并完成发布前验证

**Files:**

- Create: `docs/engineering-journal/2026-07-28-user-invite-duration-and-mask.md`
- Modify: `docs/project-status.md`
- Modify: `docs/superpowers/specs/2026-07-28-user-invite-duration-and-mask-design.md`
- Modify: `docs/superpowers/plans/2026-07-28-user-invite-duration-and-mask.md`

- [ ] **Step 1: 记录完成范围与敏感数据边界。**

  Engineering journal 只记录：迁移号、普通用户与 Worker 的边界、掩码而非明文、配置时长、统一错误、限流参数以及下列命令的通过/失败结果。不得记录真实邀请码、邮箱、IP、pepper、cookie、浏览器 profile、私有来源或完整 API 响应。`project-status.md` 将本项列为已验收的控制面增量，不将其错误地描述为全局邀请码策略或 Worker 安全模型改动。

- [ ] **Step 2: 运行完整验证。**

  Run:

  ```bash
  SUPABASE_DISABLE_TELEMETRY=1 supabase db reset
  SUPABASE_DISABLE_TELEMETRY=1 supabase test db
  cd apps/control-plane && npm test && npm run lint && npm run build
  cd ../.. && bash scripts/v0/redact-check.sh && git diff --check
  ```

  Expected: 所有命令退出码为 `0`。若任一命令失败，先以失败输出对应的实际边界修复；不得跳过或删除已有回归。

- [ ] **Step 3: 完成部署前环境审计。**

  在不写出值的前提下，确认本地和目标 Vercel 项目都已配置独立的 `INVITE_CODE_PEPPER`，其值不是任何 Supabase key 且未使用 `NEXT_PUBLIC_` 前缀。未配置该变量时不得部署新控制面版本；本步骤不授权执行远程配置、数据库 push 或生产部署。

- [ ] **Step 4: 提交文档与已完成计划。**

  ```bash
  git add docs/engineering-journal/2026-07-28-user-invite-duration-and-mask.md docs/project-status.md docs/superpowers/specs/2026-07-28-user-invite-duration-and-mask-design.md docs/superpowers/plans/2026-07-28-user-invite-duration-and-mask.md
  git commit -m "docs: record user invite duration verification"
  ```

## Plan Self-Review

- Spec coverage: Task 1 covers nullable historical metadata, status source fields and atomic source-HMAC throttling; Task 2 covers 8 位生成、掩码、同一生成基准、HMAC、旧码/Worker 兼容；Task 3 covers exact管理员 API、统一兑换错误、刷新列表、倒计时与访问控制；Task 4 covers全部验证、秘密配置审计与脱敏记录。
- Placeholder scan: 没有未选择的存储方案或笼统错误处理描述；限流计数、窗口、封锁时长、DTO 和文件路径均已固定。
- Type consistency: `UserInviteCode` 由 Task 2 产生并只给管理员 POST 成功响应使用；`RecentUserInvite` 经 Task 3 的 snake_case DTO 转入 `UserInviteList`；`INVITE_CODE_PEPPER` 只由 server-side invite-code 模块读取，Worker 路径继续调用 legacy hash。
