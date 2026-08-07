# X Reader 观点分类模块与原始帖子折叠 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Reader 数据契约和信息层级的前提下，让三类 X 观点以显著的分类模块呈现，并让单个博主下的原始 X 帖子默认折叠。

**Architecture:** 保留 `XReader.tsx` 现有的日期、判断、博主和采集窗口层级，新增一个只负责展示结构的 `ViewpointModule` 组件，供跨博主判断和单博主观点共同使用。原始帖子分析继续使用现有 reader-safe DTO，只把现有分析 article 包装为原生 `<details>`，默认关闭；所有视觉变化集中在 `globals.css` 的 Reader 选择器中。

**Tech Stack:** Next.js 16、React 19、TypeScript、原生 CSS、Vitest。

## Global Constraints

- “判断”和“观点”文字仍按各自语义保留，视觉对齐不合并内容来源或确定性。
- 三类模块纵向排列，不在桌面端并排成三列。
- 只有实际有内容的分类才渲染分类模块；空分类不渲染空模块或占位标题。
- 最新博主窗口默认展开，历史窗口默认折叠；有内容的观点分类模块默认展开；原始 X 帖子证据默认折叠；跨博主判断历史修订默认折叠。
- 原始帖子折叠后仍显示“原始 X 帖子”入口和展开指示符，并保留现有帖子链接。
- 展开后继续显示当前已有的博主观点、操作表述、条件、论据、引用帖观点和不确定性；不新生成摘要，不删除或重写现有字段。
- 不改变数据库、Reader API、Reader-safe DTO、Prompt、Schema、LLM Provider、Worker、采集、任务、checkpoint、coverage、权限或生产数据。
- 普通 Reader 页面继续只输出 reader-safe 内容，不新增内部 ID、Prompt、Provider、运行诊断、原始正文或本地路径。
- 保留当前用户工作区中与本任务无关的 `AGENTS.md`、`.superpowers/` 和 `docs/agents/` 改动；只暂存本 Plan 涉及的代码、测试和文档文件。

## File Map

- Modify: `apps/control-plane/src/components/reader/XReader.tsx` — 抽取统一的观点分类模块，并将逐帖分析改为默认折叠的原生 details。
- Modify: `apps/control-plane/src/app/globals.css` — 增加三类模块的语义色、标题层级、模块边界、原始帖子折叠行和移动端适配。
- Test: `apps/control-plane/src/components/reader/x-reader.test.tsx` — 覆盖统一模块结构、分类内容保留、最新/历史窗口展开状态和原始帖子默认关闭。
- Test: `apps/control-plane/src/app/globals.test.ts` — 覆盖分类模块的 CSS 语义色、显著标题层级和原始帖子 summary 样式。
- Modify: `docs/superpowers/specs/2026-08-07-x-reader-category-modules-and-collapsed-posts-design.md` — 已同步用户批准状态，不再改变设计内容。

## Design Direction

这是投研阅读页，不使用泛化的 SaaS 卡片风格。整体延续当前米白纸张、深墨色和细发丝线的编辑式 Reader；本次唯一明显的视觉动作是给三类观点加上“分类标题带 + 极浅色纸面 + 类别强调线”。三种颜色来自内容分类，而不是买卖方向：蓝绿色对应个股与产业，暖金色对应市场结构，低饱和紫灰色对应投资策略与心态。观点正文继续保持克制的左侧强调线和细分隔线，不增加完整嵌套卡片。

## Tasks

### Task 1: Add failing Reader regression coverage

**Files:**
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx:27-37,47-86`
- Modify: `apps/control-plane/src/app/globals.test.ts:1-15`

**Interfaces:**
- Consumes: Existing `XReader` render output and existing `globals.css` text fixture.
- Produces: Failing tests that define the target DOM classes, default `<details>` state, preserved analysis body, and category CSS tokens before production code changes.

- [ ] **Step 1: Add one realistic analysis fixture before changing production code**

Extend the latest `Second Author` segment in `x-reader.test.tsx` with one analysis containing a link and every body field that must remain visible after expansion:

```tsx
analyses: [{
  postLink: "https://x.example/posts/analysis-1",
  bloggerViewpoint: "帖子中的降息观点",
  actionIntent: null,
  conditions: ["等待数据确认"],
  arguments: ["博主此前已持续提及该判断"],
  quotedPostViewpoint: "引用帖的补充判断",
  uncertainties: ["未说明完整时间范围"],
}],
```

Use the exact `XReaderBlogger` analysis type already accepted by the repository; do not add a new DTO field or change the fixture contract.

- [ ] **Step 2: Add the failing DOM assertions**

Add assertions to the existing Reader render test for:

```tsx
expect(html).toContain('class="x-reader-viewpoint-group x-reader-viewpoint-group--security"');
expect(html).toContain('class="x-reader-viewpoint-group x-reader-viewpoint-group--market"');
expect(html).toContain('class="x-reader-viewpoint-group x-reader-viewpoint-group--strategy"');
expect(html).toContain('<details class="x-analysis">');
expect(html).not.toContain('<details class="x-analysis" open="">');
expect(html).toContain('<summary><a href="https://x.example/posts/analysis-1"');
expect(html).toContain("帖子中的降息观点");
expect(html).toContain("博主此前已持续提及该判断");
expect(html).toContain("引用帖的补充判断");
```

Also keep the existing assertions that the latest segment is open and the historical segment is closed. The new assertions must prove the nested raw-post details are closed without changing the parent window state.

- [ ] **Step 3: Add failing CSS contract assertions**

In `globals.test.ts`, add checks that `globals.css` contains each semantic module selector and a responsive-safe heading rule, for example:

```ts
expect(css).toMatch(/\.x-reader-viewpoint-group--security\s*\{/);
expect(css).toMatch(/\.x-reader-viewpoint-group--market\s*\{/);
expect(css).toMatch(/\.x-reader-viewpoint-group--strategy\s*\{/);
expect(css).toMatch(/\.x-reader-viewpoint-heading\s*\{[^}]*font-size:\s*clamp\(/s);
expect(css).toMatch(/\.x-analysis\s+summary\s*\{/);
```

- [ ] **Step 4: Run the focused tests and verify the expected RED state**

Run:

```bash
cd apps/control-plane && npm test -- src/components/reader/x-reader.test.tsx src/app/globals.test.ts
```

Expected: FAIL because the current DOM has no semantic category modifier classes, raw analyses are `<article>` elements rather than closed `<details>`, and the new CSS selectors do not yet exist. If the tests pass, correct the assertions before writing production code.

- [ ] **Step 5: Commit the red tests only**

Stage only the two test files and commit:

```bash
git add apps/control-plane/src/components/reader/x-reader.test.tsx apps/control-plane/src/app/globals.test.ts
git commit -m "test: define X Reader category and evidence presentation"
```

### Task 2: Implement the shared category module and collapsed evidence structure

**Files:**
- Modify: `apps/control-plane/src/components/reader/XReader.tsx:1-119`
- Test: `apps/control-plane/src/components/reader/x-reader.test.tsx`

**Interfaces:**
- Consumes: Existing `ReaderJudgement`, `XReaderBlogger`, `XReaderJudgementRevision`, and reader-safe analysis fields.
- Produces: `ViewpointModule` with the exact interface `{ title: string; tone: "security" | "market" | "strategy"; children: ReactNode }`, plus closed `.x-analysis` details consumed by the CSS and tests.

- [ ] **Step 1: Add the minimal shared module component**

Import `ReactNode` as a type and add a local component near the existing viewpoint helpers:

```tsx
type ViewpointTone = "security" | "market" | "strategy";

function ViewpointModule({ title, tone, children }: {
  title: string;
  tone: ViewpointTone;
  children: ReactNode;
}) {
  return <section className={`x-reader-viewpoint-group x-reader-viewpoint-group--${tone}`}>
    <h3 className="x-reader-viewpoint-heading">{title}</h3>
    {children}
  </section>;
}
```

Do not move this into a new file; this is a small presentation seam and keeping it beside `JudgementRevision` and `BloggerViewpointList` avoids an unnecessary component module.

- [ ] **Step 2: Route cross-blogger categories through the shared module**

Change the three direct `<section><h3>` branches in `JudgementRevision` to `ViewpointModule` calls with the following stable tones:

```tsx
<ViewpointModule title="个股与产业判断" tone="security">
  <div className="x-reader-viewpoint-list">
    {revision.stockViewpoints.map(...)}
  </div>
</ViewpointModule>
<ViewpointModule title="市场结构判断" tone="market">
  <div className="x-reader-viewpoint-list">
    {revision.marketIndustryViewpoints.map(...)}
  </div>
</ViewpointModule>
<ViewpointModule title="投资策略与心态" tone="strategy">
  <div className="x-reader-viewpoint-list">
    {revision.strategyMindsetViewpoints.map(...)}
  </div>
</ViewpointModule>
```

Keep the existing conditional rendering so empty categories remain absent. Keep the current `JudgementCard` fields and order unchanged.

- [ ] **Step 3: Route single-blogger categories through the shared module**

Change `BloggerViewpointList` to accept a `tone: ViewpointTone` prop and return `ViewpointModule`. Update its three call sites with `security`, `market`, and `strategy`; preserve the current title strings ending in “观点” and the existing `x-reader-viewpoint-list` wrapper.

- [ ] **Step 4: Convert each raw analysis article into a closed details block**

Replace the current `.x-analysis` `<article>` with:

```tsx
<details className="x-analysis" key={analysisIndex}>
  <summary>
    <a href={analysis.postLink} target="_blank" rel="noreferrer">原始 X 帖子</a>
  </summary>
  <div className="x-analysis-body">
    <p><strong>博主观点：</strong>{analysis.bloggerViewpoint ?? "未表达（例如普通 repost）"}</p>
    {/* Keep the existing action, condition, argument, quote, and uncertainty paragraphs unchanged. */}
  </div>
</details>
```

Do not add `open`. Native `<details>` therefore starts collapsed. Keep the parent `.x-reader-segment` `open={index === 0}` rule unchanged. Keep the external link visible in the summary; the expanded body must not expose internal IDs or raw content.

- [ ] **Step 5: Run the focused component test and verify GREEN**

Run:

```bash
cd apps/control-plane && npm test -- src/components/reader/x-reader.test.tsx
```

Expected: the DOM tests for category classes and closed raw evidence pass. The CSS contract test remains intentionally red until Task 3 adds the visual rules.

- [ ] **Step 6: Commit the component structure**

After the component tests pass or are only blocked by the intentionally missing CSS selectors, stage only `XReader.tsx` and its focused test file and commit:

```bash
git add apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/components/reader/x-reader.test.tsx
git commit -m "feat: group X Reader viewpoints and collapse evidence"
```

### Task 3: Implement the editorial category styling and responsive evidence row

**Files:**
- Modify: `apps/control-plane/src/app/globals.css:210-240,504-538`
- Test: `apps/control-plane/src/app/globals.test.ts`

**Interfaces:**
- Consumes: `.x-reader-viewpoint-group`, `.x-reader-viewpoint-group--security`, `.x-reader-viewpoint-group--market`, `.x-reader-viewpoint-group--strategy`, `.x-reader-viewpoint-heading`, `.x-reader-viewpoint-list`, `.x-analysis`, `.x-analysis-body` from Task 2.
- Produces: Responsive, keyboard-visible, non-nested editorial modules matching the approved Spec.

- [ ] **Step 1: Add the three semantic color tokens and module base rules**

Use the current paper/ink palette and add a compact token block near the existing Reader styles:

```css
.x-reader-viewpoint-group {
  --x-category-accent: #2d6872;
  --x-category-surface: #eff5f2;
  display: grid;
  gap: 0.75rem;
  margin-top: 1rem;
  border: 1px solid color-mix(in srgb, var(--x-category-accent) 28%, #dce4e0);
  border-left: 4px solid var(--x-category-accent);
  background: var(--x-category-surface);
  padding: 0.85rem 1rem 1rem;
}

.x-reader-viewpoint-group--market {
  --x-category-accent: #a86b20;
  --x-category-surface: #fff7e8;
}

.x-reader-viewpoint-group--strategy {
  --x-category-accent: #6b5a78;
  --x-category-surface: #f3eff6;
}
```

If `color-mix()` is not supported by the existing production browser baseline, replace only the border expression with explicit low-contrast border colors; do not remove the three semantic accents or introduce a dependency.

- [ ] **Step 2: Add the prominent heading and preserve the inner viewpoint rhythm**

Add a dedicated heading selector, replacing the current generic `h3` rule for `.x-reader-viewpoint-group`:

```css
.reader-content .x-reader-viewpoint-heading {
  margin: 0 -1rem;
  border-bottom: 1px solid color-mix(in srgb, var(--x-category-accent) 25%, transparent);
  padding: 0.2rem 1rem 0.65rem;
  color: color-mix(in srgb, var(--x-category-accent) 78%, #17252d);
  font-family: inherit;
  font-size: clamp(1.15rem, 2vw, 1.35rem);
  font-weight: 850;
  letter-spacing: -0.01em;
}

.x-reader-viewpoint-group .topic-card {
  border-left-color: var(--x-category-accent);
}
```

Retain the existing `topic-card + .topic-card` divider and do not add full borders around each viewpoint. The module is the visual container; the viewpoint remains a readable editorial item.

- [ ] **Step 3: Style the collapsed raw-post summary without hiding the link**

Add specific rules after the generic Reader details rules so they win without changing batch or window details:

```css
.reader-content details.x-analysis {
  border-top: 1px solid #dce4e0;
  margin-top: 0.8rem;
  padding: 0.8rem 0 0;
}

.reader-content details.x-analysis summary {
  display: flex;
  align-items: center;
  min-height: 2.75rem;
  padding: 0.25rem 0;
}

.reader-content details.x-analysis summary a {
  color: #1f5663;
  font-weight: 800;
}

.x-analysis-body {
  max-width: 72ch;
  padding: 0.75rem 0 0.2rem 1.25rem;
}
```

The native summary marker remains the expand indicator. Do not apply a page-wide `details` rule that opens or hides these blocks.

- [ ] **Step 4: Add the mobile and focus constraints**

Within the existing `@media (max-width: 430px)` block, keep module padding compact without reducing the heading below the approved scale:

```css
.x-reader-viewpoint-group { padding: 0.75rem 0.75rem 0.85rem; }
.reader-content .x-reader-viewpoint-heading { margin-inline: -0.75rem; padding-inline: 0.75rem; }
.x-analysis-body { padding-left: 0.75rem; }
```

The existing global `summary:focus-visible` rule must remain active. Do not add motion or hide focus outlines.

- [ ] **Step 5: Run focused CSS and Reader tests**

Run:

```bash
cd apps/control-plane && npm test -- src/components/reader/x-reader.test.tsx src/app/globals.test.ts
```

Expected: PASS with no warnings. If `color-mix()` makes the CSS contract difficult to test or breaks the production build, use explicit token border colors while preserving the same visual hierarchy.

- [ ] **Step 6: Commit the visual implementation**

Stage only CSS and its CSS test:

```bash
git add apps/control-plane/src/app/globals.css apps/control-plane/src/app/globals.test.ts
git commit -m "style: strengthen X Reader category modules"
```

### Task 4: Run full verification and real Reader acceptance

**Files:**
- Verify: all changed files from Tasks 1–3; no new source files are expected.
- Inspect: `/x` on the deployed stable domain after release.

**Interfaces:**
- Consumes: Approved Spec, completed component/CSS changes, and the repository's existing test/build/deploy tooling.
- Produces: Fresh local verification evidence, a reviewable diff, a production deployment, and logged-in acceptance of the new Reader presentation.

- [ ] **Step 1: Run the full control-plane test suite**

Run:

```bash
cd apps/control-plane && npm test
```

Expected: exit code 0 and zero failed tests. Record the exact test count from the command output.

- [ ] **Step 2: Run lint, production build, diff check, and redaction checks**

Run each command fresh:

```bash
cd apps/control-plane && npm run lint
cd apps/control-plane && npm run build
cd /Users/hanyuec/Desktop/Invest_hub && git diff --check
cd /Users/hanyuec/Desktop/Invest_hub && bash scripts/v0/redact-check.sh
```

Expected: every command exits 0. A failure must be fixed with a new TDD regression where it concerns the feature before continuing.

- [ ] **Step 3: Review the complete diff against the approved Spec**

Run:

```bash
git diff -- apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/app/globals.css apps/control-plane/src/components/reader/x-reader.test.tsx apps/control-plane/src/app/globals.test.ts
git status --short
```

Confirm manually that the diff does not include API, database, Worker, Prompt, authentication, source-order, or unrelated user files. Then dispatch the Superpowers code reviewer with the approved Spec and this Plan as the review contract. Fix all Critical and Important findings before release.

- [ ] **Step 4: Create the release commit with scoped files only**

After review and all checks pass, stage only the feature files and the approved Spec/Plan documents:

```bash
git add \
  CONTEXT.md \
  docs/superpowers/specs/2026-08-07-x-reader-category-modules-and-collapsed-posts-design.md \
  docs/superpowers/plans/2026-08-07-x-reader-category-modules-and-collapsed-posts.md \
  apps/control-plane/src/components/reader/XReader.tsx \
  apps/control-plane/src/components/reader/x-reader.test.tsx \
  apps/control-plane/src/app/globals.css \
  apps/control-plane/src/app/globals.test.ts
git commit -m "feat: improve X Reader viewpoint presentation"
```

Do not stage `AGENTS.md`, `.superpowers/`, or `docs/agents/` unless their owners explicitly request it.

- [ ] **Step 5: Push and deploy the approved commit**

Verify the remote and branch before pushing, then use the repository's existing Vercel deployment path. The deployment must reach `READY`; do not treat a local build or preview URL as production acceptance.

- [ ] **Step 6: Perform logged-in stable-domain acceptance at desktop and 375px widths**

On the stable `/x` page, verify all of the following against real rendered content:

1. “个股与产业判断”“市场结构判断”“投资策略与心态” are visibly distinct modules.
2. The same module treatment appears under single-blogger viewpoints, with “观点” labels preserved.
3. The latest blogger window is open and historical windows are closed.
4. Each “原始 X 帖子” is collapsed by default, its link remains visible, and opening it reveals the existing analysis fields.
5. No horizontal overflow occurs at desktop and 375px widths; keyboard focus is visible.
6. Filters, dates, blogger ordering, judgement ordering, and security boundaries remain unchanged.

Record the deployment URL, deployment status, authenticated acceptance result, and any remaining limitation in the engineering journal before claiming completion.

## Plan Self-Review

- Spec coverage: Tasks 1–3 cover both judgement and blogger category modules, semantic colors, vertical layout, preserved viewpoint structure, nested raw-post folding, responsive behavior, and accessibility. Task 4 covers all listed verification and production acceptance requirements.
- Placeholder scan: No `TBD`, `TODO`, “implement later”, or unspecified edge-case steps are used; every command and file boundary is explicit.
- Type consistency: `ViewpointTone` and `ViewpointModule` are defined in Task 2 and consumed by both `JudgementRevision` and `BloggerViewpointList`; CSS selectors exactly match the emitted modifier classes.
