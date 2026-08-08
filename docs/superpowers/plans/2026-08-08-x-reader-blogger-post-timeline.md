# X Reader 单博主帖子时间线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用最小 Reader 改动把单个博主区域改为默认展开、带时间和类型标识的帖子时间线，同时保留当日判断总结不变。

**Architecture:** 保留现有日期、博主和采集窗口层级，只移除单博主下的三类 `BloggerViewpointList` 展示。Reader projection 从已有 `canonical_messages.occurred_at` 和 `x_post_contexts.post_type` 生成两个 reader-safe 分析字段；`XReader.tsx` 负责时间线 summary 和原生 `<details>`，CSS 负责明确 icon、展开状态和窄屏排版。

**Tech Stack:** Next.js 16、React 19、TypeScript、原生 CSS、Vitest。

## Global Constraints

- 单个博主删除三个分类模块；当日判断总结的分类模块完全不变。
- 帖子默认展开，最新窗口展开、历史窗口折叠；不改变窗口顺序。
- 发帖时间使用 `canonical_messages.occurred_at` 的北京时间展示，帖子类型使用 `x_post_contexts.post_type`。
- 不改变数据库、采集、Prompt、Schema、LLM Provider、Worker、checkpoint、coverage 或权限。
- API 只输出 `postedAt`、`postType`、原始链接和现有 reader-safe 字段，不输出内部 ID、Prompt、Provider、诊断或原始正文。
- 保留无关联帖子的旧版窗口观点，但以紧凑普通列表展示，不恢复分类模块。
- 只暂存本计划涉及文件；保留现有 `AGENTS.md`、`.superpowers/` 和 `docs/agents/` 无关改动。

## File Map

- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts` — 查询并投影帖子发布时间、类型。
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts` type definitions — 扩展分析 reader-safe 类型。
- Test: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts` — 覆盖时间/类型投影和查询字段。
- Modify: `apps/control-plane/src/app/api/reader/x/route.ts` — 透传两个 reader-safe 展示字段。
- Test: `apps/control-plane/src/app/api/reader/x/route.test.ts` — 覆盖字段保留与敏感字段隔离。
- Modify: `apps/control-plane/src/components/reader/XReader.tsx` — 移除单博主分类模块，渲染帖子时间线和展开状态。
- Test: `apps/control-plane/src/components/reader/x-reader.test.tsx` — 覆盖无分类模块、summary 元信息、默认展开和正文保留。
- Modify: `apps/control-plane/src/app/globals.css` — 添加帖子 summary icon、展开样式和窄屏规则。
- Test: `apps/control-plane/src/app/globals.test.ts` — 覆盖 icon 和 summary CSS 合同。

## Tasks

### Task 1: Add failing projection, API, and Reader tests

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Modify: `apps/control-plane/src/app/api/reader/x/route.test.ts`
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx`
- Modify: `apps/control-plane/src/app/globals.test.ts`

- [ ] **Step 1: Extend projection fixture with post metadata and assert it is selected**

In the existing v3 projection fixture, add `occurred_at: "2099-01-03T08:30:00.000Z"` to the canonical row and `post_type: "quote"` to the context row. Extend the expected analysis with `postedAt: "2099-01-03T08:30:00.000Z"` and `postType: "quote"`; assert the selected columns include `canonical_messages:id,source_id,external_message_id,occurred_at` and `x_post_contexts:canonical_message_id,post_url,post_type`.

- [ ] **Step 2: Extend API fixture and assert reader-safe metadata**

Add `postedAt` and `postType` to the safe analysis fixture and assert the response contains them. Keep the existing forbidden-field loop unchanged and add no internal IDs or raw content.

- [ ] **Step 3: Add the failing component assertions**

Add metadata to the latest analysis fixture and assert the rendered HTML contains:

```tsx
expect(html).not.toContain("个股与产业观点");
expect(html).not.toContain("市场结构观点");
expect(html).not.toContain("投资策略与心态");
expect(html).toContain("08-08 03:05 · 引用帖");
expect(html).toContain('<details class="x-analysis" open="">');
expect(html).toContain("帖子中的降息观点");
```

Retain assertions that the latest parent segment is open and history is closed, and that all existing analysis body fields remain visible.

- [ ] **Step 4: Add the failing CSS contract assertions**

Assert `globals.css` contains `.x-analysis summary::before`, an open-state rotation selector, and `overflow-wrap: anywhere` for the summary/body path.

- [ ] **Step 5: Run focused tests and verify RED**

Run:

```bash
cd apps/control-plane && npm test -- src/lib/db/repositories/reader-source-navigation.test.ts src/app/api/reader/x/route.test.ts src/components/reader/x-reader.test.tsx src/app/globals.test.ts
```

Expected: failures for missing metadata, still-rendered category modules, collapsed details, and missing icon CSS. Fix only test setup errors; do not write production code before the intended failures are observed.

### Task 2: Add minimal reader-safe post metadata projection

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/app/api/reader/x/route.ts`
- Test: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Test: `apps/control-plane/src/app/api/reader/x/route.test.ts`

- [ ] **Step 1: Extend the local analysis type with optional safe fields**

Add:

```ts
type XPostType = "original" | "quote" | "reply" | "repost";
postedAt?: string | null;
postType?: XPostType | null;
```

Keep the fields optional for old fixtures and legacy rows.

- [ ] **Step 2: Select existing database columns only**

Change the canonical select to `id,source_id,external_message_id,occurred_at` and context select to `canonical_message_id,post_url,post_type`. Do not select canonical content, metadata, internal analysis identity, or evidence fields.

- [ ] **Step 3: Project metadata into each analysis**

When building the existing analysis object, set `postedAt: canonical.occurred_at ?? null` and `postType: context.post_type ?? null`; keep all existing analysis validation and body fields unchanged.

- [ ] **Step 4: Pass only the two safe fields through the API**

Add `postedAt: analysis.postedAt ?? null` and `postType: analysis.postType ?? null` to the existing analysis mapping in `readerSafeXDays`.

- [ ] **Step 5: Run projection and API tests GREEN**

Run the two focused test files from Task 1 and confirm the metadata assertions pass while forbidden-field assertions still pass.

### Task 3: Convert the single-blogger view to a post timeline

**Files:**
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Test: `apps/control-plane/src/components/reader/x-reader.test.tsx`

- [ ] **Step 1: Add stable display helpers**

Add a local label map for `original`, `quote`, `reply`, and `repost`, plus a helper that formats a valid `postedAt` as `MM-DD HH:mm` in `Asia/Shanghai`. Use `原帖`, `引用帖`, `回复`, and `转发` as labels. If the date is missing, show the type label; if both are missing, show `原始 X 帖子`.

- [ ] **Step 2: Remove single-blogger category module calls**

Delete the three `BloggerViewpointList` calls and the now-unused `BloggerViewpointList` function. Do not touch `JudgementRevision` or the shared cross-blogger `ViewpointModule`.

- [ ] **Step 3: Preserve unmatched window viewpoints compactly**

Render the existing `segment.viewpoints` list only when it has entries, using a compact `x-reader-unlinked-viewpoints` block before the post list. Do not label it as any of the deleted categories.

- [ ] **Step 4: Render each analysis as an open details item**

Use:

```tsx
<details className="x-analysis" key={analysisIndex} open>
  <summary>
    <a href={analysis.postLink} target="_blank" rel="noreferrer">
      {analysisLabel(analysis)}
    </a>
  </summary>
  <div className="x-analysis-body">{existingFields}</div>
</details>
```

Keep the existing field order and link behavior. The `<details>` open attribute applies only to each post; retain `open={index === 0}` on the parent segment.

- [ ] **Step 5: Run the component test GREEN**

Run `npm test -- src/components/reader/x-reader.test.tsx` and confirm category module titles are absent, each post is open, and all existing fields remain present.

### Task 4: Style the post summary and responsive timeline

**Files:**
- Modify: `apps/control-plane/src/app/globals.css`
- Test: `apps/control-plane/src/app/globals.test.ts`

- [ ] **Step 1: Add explicit summary icon rules**

Hide the browser-specific default marker, add `.x-analysis summary::before` with `content: "▸"`, and rotate it for `.x-analysis[open] > summary::before`. Keep focus-visible styling inherited from the existing global rule.

- [ ] **Step 2: Style metadata and body without adding nested cards**

Use a quiet divider, compact summary row, timestamp/type text, and the existing link color. Preserve `min-width: 0` and `overflow-wrap: anywhere` for summary and body. Keep the body fields in the current editorial text treatment.

- [ ] **Step 3: Add narrow-screen rules and CSS tests**

At the existing 430px breakpoint reduce horizontal padding, retain a tappable summary row, and keep long labels wrapping. Run the focused CSS test and confirm it passes.

### Task 5: Full verification, review, release, and production acceptance

**Files:**
- Review all scoped changes; no additional implementation files expected.

- [ ] **Step 1: Run focused and full checks**

Run:

```bash
cd apps/control-plane && npm test
cd apps/control-plane && npm run lint
cd apps/control-plane && npm run build
cd ../.. && git diff --check
cd ../.. && bash scripts/v0/redact-check.sh
```

- [ ] **Step 2: Perform read-only code review**

Review the diff against `ce32566` for scope leakage, reader-safe boundaries, unchanged cross-blogger categories, default states, and 375px layout. Fix only concrete findings, then rerun the affected checks.

- [ ] **Step 3: Commit only scoped files**

Stage the new Spec/Plan and the repository, API, component, CSS, and test files listed above. Leave `AGENTS.md`, `.superpowers/`, and `docs/agents/` unstaged. Commit with:

```bash
git commit -m "feat: show X blogger posts as a timeline"
```

- [ ] **Step 4: Push and deploy**

After fresh verification, push `origin/main` and run `npx --yes vercel@latest --prod` from `apps/control-plane`. Record the READY deployment URL and stable alias.

- [ ] **Step 5: Verify the formal `/x` page**

Open `https://invest-hub-v0-control-plane.vercel.app/x` in the logged-in browser session and verify: no single-blogger category modules, post labels show time/type, posts are open, icon rotates when collapsed, and the daily judgement category modules remain present. If the command-line browser lacks the user login session, report deployment READY and provide the stable URL for the user’s active session rather than claiming authenticated visual acceptance.
