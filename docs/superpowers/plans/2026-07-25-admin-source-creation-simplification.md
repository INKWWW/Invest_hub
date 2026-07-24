# 管理员来源创建简化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让管理员只填写来源业务信息，由服务端自动生成内部来源键和稳定采集版本。

**Architecture:** 新增服务端创建策略模块，集中定义每种来源的默认契约与 UUID 键生成。两个管理员创建路由收窄公开请求 DTO、在服务端补齐技术值并投影安全响应；Discord/X 客户端表单只呈现可理解的来源资料和只读标准采集说明。

**Tech Stack:** Next.js App Router、TypeScript、React、Vitest、现有 Supabase repository/RPC、CSS。

## Global Constraints

- 创建请求、DOM、成功响应和状态文本不得包含 `source_key` 或 `parameter_version`。
- 服务端键格式固定为 `<source_type>:<UUID>`；默认版本固定为 Discord `discord-standard-v1`、X `x-standard-v2`。
- 不迁移数据库，不修改已有来源及其任务、coverage、checkpoint、Worker 或 Reader 语义。
- Discord POST 仅接受 `{ display_name }`；X POST 仅接受 `{ display_name, requested_handle }`；额外字段必须以 422 拒绝。
- 保持管理员角色门禁，不暴露 URL、Cookie、Profile、Worker 凭据、Provider 或原始内容。
- X 展示名称自动建议不得覆盖管理员已手工编辑的值。

---

## File Structure

- `apps/control-plane/src/lib/source-creation.ts`: 服务器生成来源键、默认参数版本与安全创建响应投影。
- `apps/control-plane/src/lib/source-creation.test.ts`: 生成规则与安全 DTO 单元测试。
- `apps/control-plane/src/app/api/admin/sources/route.ts`: Discord 创建请求收窄及服务端默认值。
- `apps/control-plane/src/app/api/admin/x/sources/route.ts`: X 创建请求收窄及服务端默认值。
- `apps/control-plane/src/app/api/api.integration.test.ts`: 管理员创建请求、拒绝技术字段和安全响应回归。
- `apps/control-plane/src/components/admin/SourceCreateForm.tsx`: Discord 创建表单简化。
- `apps/control-plane/src/components/admin/XSourceForm.tsx`: X 账号优先、展示名建议与只读采集方案。
- `apps/control-plane/src/components/admin/source-create-form.test.tsx`: Discord 表单与请求体测试。
- `apps/control-plane/src/components/admin/x-source-form.test.tsx`: X 自动建议、手动覆盖与请求体测试。
- `apps/control-plane/src/app/globals.css`: 创建表单的采集方案说明与账号前缀样式。
- `docs/engineering-journal/2026-07-25-admin-source-creation-simplification.md`: 实现与验证记录。
- `docs/project-status.md`: 批准文档与完成状态。

## Task 1: Lock the server-owned creation contract

**Files:**

- Create: `apps/control-plane/src/lib/source-creation.ts`
- Create: `apps/control-plane/src/lib/source-creation.test.ts`
- Modify: `apps/control-plane/src/app/api/admin/sources/route.ts`
- Modify: `apps/control-plane/src/app/api/admin/x/sources/route.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

```ts
export type NewSourceType = "discord" | "x";
export function buildSourceCreation(type: NewSourceType): {
  sourceKey: string;
  parameterVersion: "discord-standard-v1" | "x-standard-v2";
};
export function publicCreatedSource(source: {
  source_type: NewSourceType; display_name: string; resolution_status?: "pending";
}): { source_type: NewSourceType; display_name: string; resolution_status?: "pending" };
```

- [x] **Step 1: Write failing server policy and route tests.**

```ts
it("generates an opaque X key and stable default contract", () => {
  expect(buildSourceCreation("x").sourceKey).toMatch(/^x:[0-9a-f-]{36}$/);
  expect(buildSourceCreation("x").parameterVersion).toBe("x-standard-v2");
});

it("rejects client-supplied source_key and parameter_version", async () => {
  const response = await postAdminXSource(jsonRequest("/api/admin/x/sources", {
    display_name: "Analyst", requested_handle: "analyst", source_key: "forged", parameter_version: "forged",
  }));
  expect(response.status).toBe(422);
});
```

- [x] **Step 2: Run the focused failure.**

Run: `cd apps/control-plane && npm test -- --run src/lib/source-creation.test.ts src/app/api/api.integration.test.ts`

Expected: FAIL because the policy module does not exist and creation routes accept technical fields.

- [x] **Step 3: Implement the server policy and narrow route DTOs.**

```ts
import { randomUUID } from "node:crypto";

const defaultParameterVersion = {
  discord: "discord-standard-v1",
  x: "x-standard-v2",
} as const;

export function buildSourceCreation(type: "discord" | "x") {
  return { sourceKey: `${type}:${randomUUID()}`, parameterVersion: defaultParameterVersion[type] };
}
```

Each route validates exact public keys, invokes `buildSourceCreation`, passes only its generated values to the existing repository/RPC, and returns a safe projection that has no `id`, `source_key` or `parameter_version`.

- [x] **Step 4: Run the focused server tests.**

Run: `cd apps/control-plane && npm test -- --run src/lib/source-creation.test.ts src/app/api/api.integration.test.ts`

Expected: PASS, including ordinary-user rejection, generated values passed to repository mocks, extra-key rejection and safe response assertions.

- [x] **Step 5: Commit the server contract.**

```bash
git add apps/control-plane/src/lib/source-creation.ts apps/control-plane/src/lib/source-creation.test.ts apps/control-plane/src/app/api/admin/sources/route.ts apps/control-plane/src/app/api/admin/x/sources/route.ts apps/control-plane/src/app/api/api.integration.test.ts
git commit -m "feat: automate source creation metadata"
```

## Task 2: Replace technical form fields with source-oriented controls

**Files:**

- Modify: `apps/control-plane/src/components/admin/SourceCreateForm.tsx`
- Modify: `apps/control-plane/src/components/admin/XSourceForm.tsx`
- Create: `apps/control-plane/src/components/admin/source-create-form.test.tsx`
- Create: `apps/control-plane/src/components/admin/x-source-form.test.tsx`
- Modify: `apps/control-plane/src/app/globals.css`

**Interfaces:**

```tsx
<p className="source-creation-preset" role="note">
  <strong>采集方案</strong><span>标准采集（推荐）</span><small>系统自动维护</small>
</p>
```

- [x] **Step 1: Write failing form tests.**

```ts
it("submits only a Discord display name", async () => {
  render(<SourceCreateForm />);
  await user.type(screen.getByLabelText("显示名称（社区名 · 频道名）"), "Research · #daily");
  await user.click(screen.getByRole("button", { name: "创建 Discord 来源" }));
  expect(fetch).toHaveBeenCalledWith("/api/admin/sources", expect.objectContaining({
    body: JSON.stringify({ display_name: "Research · #daily" }),
  }));
  expect(screen.queryByText("内部来源标识")).not.toBeInTheDocument();
});
```

Add X assertions for `@handle` suggestion, preservation after manual display-name edit, no technical labels and a request body of exactly `{ display_name, requested_handle }`.

- [x] **Step 2: Run the focused failure.**

Run: `cd apps/control-plane && npm test -- --run src/components/admin/source-create-form.test.tsx src/components/admin/x-source-form.test.tsx`

Expected: FAIL because both forms still render and submit technical fields.

- [x] **Step 3: Implement the plain-language form flow.**

Render Discord’s display name field and X’s account-first pair of fields, with `@` removed from the submitted account. Add a `displayNameEdited` state flag: derive `@${normalizedHandle}` only until the name’s first manual change. Use the shared preset note above; it is explanatory and has no form name/value.

- [x] **Step 4: Run focused form tests.**

Run: `cd apps/control-plane && npm test -- --run src/components/admin/source-create-form.test.tsx src/components/admin/x-source-form.test.tsx`

Expected: PASS.

- [x] **Step 5: Add scoped, responsive styles and commit.**

```css
.source-creation-preset { display: grid; grid-template-columns: auto 1fr; gap: .25rem .75rem; }
.source-creation-preset small { grid-column: 2; color: var(--muted); }
.source-handle-field { position: relative; }
```

Run: `cd apps/control-plane && npm test -- --run src/components/admin/source-create-form.test.tsx src/components/admin/x-source-form.test.tsx`

Expected: PASS.

```bash
git add apps/control-plane/src/components/admin/SourceCreateForm.tsx apps/control-plane/src/components/admin/XSourceForm.tsx apps/control-plane/src/components/admin/source-create-form.test.tsx apps/control-plane/src/components/admin/x-source-form.test.tsx apps/control-plane/src/app/globals.css
git commit -m "feat: simplify source creation forms"
```

## Task 3: Document and verify the production-ready change

**Files:**

- Create: `docs/engineering-journal/2026-07-25-admin-source-creation-simplification.md`
- Modify: `docs/project-status.md`

- [x] **Step 1: Record design approval, implementation boundary and test evidence.**

State that this change only automates values for newly created sources; it neither changes existing source metadata nor requires a database migration.

- [x] **Step 2: Run complete verification.**

Run:

```bash
cd apps/control-plane && npm test && npm run lint && npm run build
cd ../.. && bash scripts/v0/redact-check.sh && git diff --check
```

Expected: all tests, lint, production build, redaction check and whitespace validation pass.

- [x] **Step 3: Commit documentation.**

```bash
git add docs/engineering-journal/2026-07-25-admin-source-creation-simplification.md docs/project-status.md docs/superpowers/specs/2026-07-25-admin-source-creation-simplification-design.md docs/superpowers/plans/2026-07-25-admin-source-creation-simplification.md
git commit -m "docs: record source creation simplification"
```

## Task 4: Merge and deploy the verified control plane

**Files:** no source-file changes.

- [x] **Step 1: Merge the isolated branch into local `main` and rerun the front-end suite.**

Run:

```bash
git checkout main
git pull --ff-only
git merge codex/source-create-simplification
cd apps/control-plane && npm test
```

Expected: merged `main` passes all front-end tests.

- [x] **Step 2: Deploy the existing linked Vercel control-plane project and verify the protected route.**

Run:

```bash
cd apps/control-plane && npx --yes vercel@50.28.0 --prod --yes
npx --yes vercel@50.28.0 inspect <deployment-url>
curl --noproxy '*' --silent --show-error --max-time 20 --location --output /dev/null --write-out '%{http_code} %{url_effective}\n' https://invest-hub-v0-control-plane.vercel.app/admin/sources
```

Expected: Vercel status is `Ready`; anonymous access redirects to the protected login route, and an authenticated administrator can use the new source-creation flow. No Supabase migration is required because this change uses existing columns and RPCs.

- [ ] **Step 3: Remove the owned worktree and merged feature branch.**

Run:

```bash
git worktree remove .worktrees/codex-source-create-simplification
git worktree prune
git branch -d codex/source-create-simplification
```

Expected: `main` remains clean and the owned feature worktree is gone.

## Plan self-review

- Spec coverage: Task 1 covers server-owned metadata, exact public DTOs, authorization and safe response; Task 2 covers the source-oriented UI, X suggestion and accessibility; Task 3 covers documentation and all acceptance verification.
- Placeholder scan: no `TODO`, `TBD` or implementation placeholders remain.
- Type consistency: `buildSourceCreation` is used only by route handlers; each repository keeps its existing internal input interface, and each browser form targets the matching public route DTO.
