# X 阅读页全量筛选与管理员入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让管理员可从阅读页进入配置管理，并让 X 阅读页默认展示可组合筛选的全部独立日卡片。

**Architecture:** `SessionControls` 只根据现有会话角色渲染管理员导航。`XReader` 以“全部”作为无筛选哨兵，计算匹配的 `XReaderDay[]` 并逐卡渲染；页面把 URL 查询参数传入该组件以恢复筛选状态，Reader API 将 `all` 规范化为无过滤。

**Tech Stack:** Next.js App Router、React、TypeScript、Vitest、现有 Supabase reader repository、CSS。

## Global Constraints

- 每张结果卡只能代表一个博主和一个自然日，禁止跨来源或跨日期合并观点。
- 默认筛选为“全部 / 全部”；未筛选 URL 不写 `source` 或 `date`。
- 管理入口仅对 `admin` 角色可见，既有 `/admin` 服务端授权不变。
- 不迁移数据库，不改采集、摘要、任务、checkpoint 或安全 reader DTO。
- 不在 DOM、URL、状态文本或 API 响应中新增原始内容、私有引用、Cookie、Profile、Worker、Prompt 或 Provider 信息。

---

## File Structure

- `apps/control-plane/src/components/auth/SessionControls.tsx`: 管理员专属配置管理入口。
- `apps/control-plane/src/components/auth/session-controls.test.tsx`: 管理员和普通用户的入口可见性测试。
- `apps/control-plane/src/components/reader/XReader.tsx`: 全部选项、组合筛选、逐日卡片和 URL 同步。
- `apps/control-plane/src/components/reader/x-reader.test.tsx`: 默认全量、筛选初始值与独立卡片安全呈现测试。
- `apps/control-plane/src/app/x/page.tsx`: 读取查询参数并传给 XReader。
- `apps/control-plane/src/app/x/page.test.tsx`: 页面查询参数透传测试。
- `apps/control-plane/src/app/api/reader/x/route.ts`: 规范化 `all` API 查询值。
- `apps/control-plane/src/app/api/api.integration.test.ts`: Reader API 全部哨兵与非法日期回归。
- `apps/control-plane/src/app/globals.css`: 多结果卡和会话链接的响应式样式。

### Task 1: Lock role-aware navigation and reader selection behavior

**Files:**

- Create: `apps/control-plane/src/components/auth/session-controls.test.tsx`
- Modify: `apps/control-plane/src/components/auth/SessionControls.tsx`
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`

**Interfaces:**

```ts
export type XReaderProps = {
  days: XReaderDay[];
  initialSourceKey?: string;
  initialNaturalDate?: string;
};
```

- [x] **Step 1: Write failing component tests.**

```tsx
expect(renderToStaticMarkup(<SessionControls viewer={{ email: "admin@example.invalid", role: "admin" }} />)).toContain('href="/admin"');
expect(renderToStaticMarkup(<SessionControls viewer={{ email: "reader@example.invalid", role: "user" }} />)).not.toContain("配置管理");
expect(renderToStaticMarkup(<XReader days={days} />)).toContain('<option value="all" selected="">全部</option>');
expect(renderToStaticMarkup(<XReader days={days} />)).toContain("Second Author");
```

- [x] **Step 2: Run focused tests to verify they fail.**

Run: `cd apps/control-plane && npm test -- --run src/components/auth/session-controls.test.tsx src/components/reader/x-reader.test.tsx`

Expected: FAIL because the admin link and `all` default do not exist and only one day is rendered.

- [x] **Step 3: Implement minimal role navigation and filtered card list.**

```tsx
const ALL = "all";
const visibleDays = days.filter((day) =>
  (sourceKey === ALL || day.source.sourceKey === sourceKey) &&
  (naturalDate === ALL || day.naturalDate === naturalDate),
);
```

Render a `/admin` link only for `viewer.role === "admin"`. Render all matching days using a small day-card helper, retaining the existing status and evidence markup per card.

- [x] **Step 4: Run focused tests to verify they pass.**

Run: `cd apps/control-plane && npm test -- --run src/components/auth/session-controls.test.tsx src/components/reader/x-reader.test.tsx`

Expected: PASS.

### Task 2: Restore URL filters and normalize the reader API

**Files:**

- Modify: `apps/control-plane/src/app/x/page.tsx`
- Modify: `apps/control-plane/src/app/x/page.test.tsx`
- Modify: `apps/control-plane/src/app/api/reader/x/route.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**

```ts
function readerFilter(value: string | null): string | undefined {
  return value && value !== "all" ? value : undefined;
}
```

- [x] **Step 1: Write failing page and API tests.**

```ts
const page = await XPage({ searchParams: Promise.resolve({ source: "fixture", date: "2099-01-01" }) });
expect(renderToStaticMarkup(page)).toContain('value="fixture"');

const response = await getXReader(new Request("http://localhost/api/reader/x?source=all&date=all"));
expect(readerMocks.readXDay).toHaveBeenCalledWith({ sourceKey: undefined, date: undefined });
```

- [x] **Step 2: Run focused tests to verify they fail.**

Run: `cd apps/control-plane && npm test -- --run src/app/x/page.test.tsx src/app/api/api.integration.test.ts`

Expected: FAIL because the page ignores search parameters and the API passes `all` to the repository.

- [x] **Step 3: Implement query propagation and normalization.**

Make `XPage` read optional `source` and `date` search parameters, pass them to `XReader`, and keep `readXDay()` unfiltered. Normalize `all` to `undefined` before API validation and repository invocation.

- [x] **Step 4: Run focused tests to verify they pass.**

Run: `cd apps/control-plane && npm test -- --run src/app/x/page.test.tsx src/app/api/api.integration.test.ts`

Expected: PASS.

### Task 3: Style, document, verify and deploy

**Files:**

- Modify: `apps/control-plane/src/app/globals.css`
- Create: `docs/engineering-journal/2026-07-26-x-reader-all-filters.md`
- Modify: `docs/project-status.md`

- [x] **Step 1: Add scoped responsive styles.**

```css
.reader-result-list { display: grid; gap: 1.5rem; }
.reader-day-card { border-top: 3px solid #2d6872; padding-top: 1.25rem; }
```

Keep desktop cards readable and stack naturally at the existing narrow breakpoint; style the administrator link with the existing session control button language.

- [x] **Step 2: Run complete verification.**

Run:

```bash
cd apps/control-plane && npm test && npm run lint && npm run build
cd ../.. && bash scripts/v0/redact-check.sh && git diff --check
```

Expected: all frontend tests, lint, production build, redaction check and whitespace validation pass.

- [ ] **Step 3: Commit and deploy the verified branch.**

Run:

```bash
git add apps/control-plane docs
git commit -m "feat: add all X reader filters"
git checkout main
git merge --ff-only codex/x-reader-all-filters
cd apps/control-plane && npx --yes vercel@50.28.0 --prod --yes
```

Expected: the Vercel deployment is `Ready`; the stable control-plane URL serves the updated authenticated X reader. No database migration is required.

## Plan self-review

- Spec coverage: Task 1 implements administrator-only navigation plus default all-card rendering; Task 2 covers URL/API selection semantics; Task 3 covers responsive styling, documentation, verification and deployment.
- Placeholder scan: no TODO or TBD markers are present.
- Type consistency: page and API preserve optional `sourceKey`/`date` repository filters; `XReader` owns only presentation state.
