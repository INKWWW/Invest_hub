# X 迟到采集结果 Reader 投影 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让真实持久化但晚于批次结算的 X 窗口内容进入对应日期的 Reader，并明确标记“后补采集”，同时保持原跨博主日报、gap 和连续 coverage 不变。

**Architecture:** 复用现有 `x_daily_viewpoint_segments`、`sync_tasks`、`x_collection_batches` 和 `x_collection_batch_sources` 读取结果，不新增数据库表、不修改 Worker 和调度器。Reader Repository 为已持久化 segment 计算安全的 `lateArrival` 投影；React Reader 在博主卡片中显示后补状态，原日报仍使用已持久化的 judgement version，不触发 Provider。

**Tech Stack:** Next.js 16、React 19、TypeScript、Supabase server client、Vitest。

## Global Constraints

- Worker 在本 Spec 开发和发布期间继续运行，不要求为开发而停止当前采集。
- 不删除或放宽 `source_behind_cutoff` 的连续窗口调度约束。
- 不允许 coverage 水位跨过尚未成功或尚未明确登记 gap 的窗口。
- 不把原失败任务改成 `succeeded`，不删除或关闭既有 gap。
- 不为旧失败窗口自动创建历史恢复任务，不执行历史 gap 转换。
- 不重新打开已结算 batch，不修改原有日报内容或其 `partial` 语义。
- 不重新调用跨博主判断 Provider，不新增日报流水线、队列、监控平台或第二套 scheduler。
- 只有真实持久化的 `x_daily_viewpoint_segments` 才能进入 Reader；排队、处理中或未持久化成功的任务不得伪造内容。
- Reader DTO 只暴露 `lateArrival` 和上海时间 gap 范围，不暴露原始异常、Provider 输出、凭据、任务 ID 或内部排除字段。
- 本次预期不创建或修改 Supabase migration；若实现证明必须改 schema，必须停止并回到 Spec/Plan 增补 additive migration 与单独 Release Authorization。
- 所有行为先写实际 RED 测试，再写最小 GREEN 实现。
- 本地实现必须在 `/Users/hanyuec/.codex/worktrees/9276/Invest_hub` 隔离 worktree 中完成，不修改 dirty 主 checkout。

---

### Task 1: Repository 投影迟到 segment

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts:106-133,535-535,567-809`
- Modify: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`

**Interfaces:**
- Consumes: `x_daily_viewpoint_segments.range_task_id,created_at`、`sync_tasks.collection_batch_id,status`、`x_collection_batches.settlement_deadline_at`、`x_collection_batch_sources.settlement_status`。
- Produces: `XReaderBlogger.lateArrival: boolean`；segment 内容仍从现有安全 segment 投影产生。

- [ ] **Step 1: Extend the repository RED fixture with a late successful segment**

在 `reader-source-navigation.test.ts` 的基础 fixture 中增加一个独立的历史日期和窗口：

```ts
databaseMocks.rows.set("x_daily_viewpoint_segments", [
  {
    source_id: "source-a",
    natural_date: "2099-01-03",
    range_task_id: "task-late",
    created_at: "2099-01-04T01:00:00.000Z",
    occurred_from_at: "2099-01-03T08:00:00.000Z",
    occurred_through_at: "2099-01-03T12:00:00.000Z",
    window_viewpoints: ["迟到但真实持久化的观点"],
    post_analysis_refs: [],
    evidence_refs: ["internal"],
  },
]);
databaseMocks.rows.set("x_collection_batches", [{
  id: "batch-late",
  natural_date: "2099-01-03",
  cutoff_at: "2099-01-03T12:00:00.000Z",
  settlement_deadline_at: "2099-01-03T14:00:00.000Z",
  status: "succeeded",
}]);
databaseMocks.rows.set("x_collection_batch_sources", [{
  batch_id: "batch-late",
  source_id: "source-a",
  source_display_name: "Alpha",
  x_sync_task_id: "task-late",
  settlement_status: "excluded",
  exclusion_code: "settlement_deadline_exceeded",
}]);
databaseMocks.rows.set("sync_tasks", [{
  id: "task-late",
  source_id: "source-a",
  status: "succeeded",
  collection_batch_id: "batch-late",
}]);
```

同时在 fixture 中保留一个普通 `included + succeeded` segment、一个 `excluded + queued` 但没有 segment 的来源，以及一个只有 gap 没有 segment 的来源，确保测试不会把“批次排除”本身误当作可展示内容。

- [ ] **Step 2: Add assertions for the exact four-state matrix**

在同一测试文件中新增一个独立测试 `projects late persisted segments without changing judgement`，先写以下断言：

```ts
const result = await readXDay();
const late = result.find((day) => day.naturalDate === "2099-01-03")?.bloggers
  .find((blogger) => blogger.source.sourceKey === "alpha");

expect(late).toMatchObject({
  lateArrival: true,
  segments: [{ viewpoints: ["迟到但真实持久化的观点"] }],
});
expect(result.find((day) => day.naturalDate === "2099-01-03")?.judgement.batches)
  .toEqual(expect.arrayContaining([expect.objectContaining({ coverageStatus: null })]));
```

另外明确断言：

```ts
expect(normalIncluded?.lateArrival).toBe(false);
expect(queuedWithoutSegment?.segments).toEqual([]);
expect(gapOnly?.collectionGaps).toEqual([{
  startAt: "2099-01-03T04:00:00.000Z",
  endAt: "2099-01-03T08:00:00.000Z",
}]);
expect(JSON.stringify(result)).not.toContain("settlement_deadline_exceeded");
expect(JSON.stringify(result)).not.toContain("task-late");
```

如果当前 `XReaderBlogger` 尚无 `lateArrival` 字段，RED 必须因为字段缺失或值不正确而失败，而不是通过放宽断言制造假 GREEN。

- [ ] **Step 3: Run the focused RED test**

Run:

```bash
cd apps/control-plane
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts -t "late persisted segments"
```

Expected: FAIL because the repository currently does not return `lateArrival` and its query projection does not carry the segment-to-batch timing inputs. Do not modify production data or create a migration to make this test pass.

- [ ] **Step 4: Add the minimal safe repository data shape**

In `reader.ts`:

1. Add `lateArrival: boolean` to `XReaderBlogger`.
2. Extend the segment select to include only `range_task_id` and `created_at` in addition to the existing safe projection fields. Do not select `evidence_refs` or raw payloads.
3. Extend the batch select with `settlement_deadline_at`.
4. Build task IDs from both `x_collection_batch_sources.x_sync_task_id` and `x_daily_viewpoint_segments.range_task_id`, deduplicate them, and keep the existing chunk size and pagination behavior.
5. Extend the `sync_tasks` select to `id,status,collection_batch_id`; retain the existing task-attempt query only for status derivation.
6. Build maps keyed by batch ID and by `${batch_id}:${source_id}`. For each projected segment, mark its source/date as late only when its range task resolves to a batch and either of these conditions is true:

```ts
const lateArrival = Boolean(
  batchSource?.settlement_status === "excluded"
  || (batch?.settlement_deadline_at && segment.created_at > batch.settlement_deadline_at),
);
```

If a segment has no reliable task-to-batch association, leave `lateArrival` false but still project the validated segment. Never infer lateness from a missing association.

7. Aggregate the segment-level boolean to the source/date blogger card with `some(Boolean)`; do not change batch judgement construction or `coverageStatus`.
8. Preserve the existing safe output checks and keep `settlement_status`, `exclusion_code`, task IDs, `range_task_id`, and `created_at` out of the returned DTO.

- [ ] **Step 5: Run the focused GREEN and repository regression suite**

Run:

```bash
cd apps/control-plane
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts -t "late persisted segments"
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts
```

Expected: the new late-arrival test passes, all existing Reader navigation tests pass, high-cardinality chunking remains bounded, and the safe projection test confirms no internal task or exclusion fields cross the Reader boundary.

- [ ] **Step 6: Commit the repository change**

```bash
git add apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts
git commit -m "feat(reader): project late X segments"
```

---

### Task 2: Reader UI 展示“后补采集”

**Files:**
- Modify: `apps/control-plane/src/components/reader/XReader.tsx:46-50,348-360`
- Modify: `apps/control-plane/src/components/reader/x-reader.test.tsx`

**Interfaces:**
- Consumes: `XReaderBlogger.lateArrival` from Task 1 and existing `collectionGaps`.
- Produces: 博主卡片内的安全状态文案；不改变日报或观点内容。

- [ ] **Step 1: Add the UI RED assertion**

在 `x-reader.test.tsx` 增加一个 `lateArrival: true` 的博主 fixture，并在 `XReader` 测试中先写：

```ts
expect(html).toContain("后补采集：该内容未纳入原跨博主日报。");
expect(html).toContain("采集缺失：01月02日 12:00–16:00");
```

同时增加一个正常博主 fixture，断言：

```ts
expect(normalHtml).not.toContain("后补采集：该内容未纳入原跨博主日报。");
```

- [ ] **Step 2: Run the focused UI RED test**

Run:

```bash
cd apps/control-plane
npm test -- src/components/reader/x-reader.test.tsx -t "late"
```

Expected: FAIL because `XReaderBloggerCard` currently has no late-arrival status block.

- [ ] **Step 3: Implement the minimal UI status block**

在 `XReaderBloggerCard` 中保留现有 `CollectionGapNotice`，并在其后增加：

```tsx
{blogger.lateArrival ? <div className="reader-status" data-status="late_arrival">
  <p role="status">后补采集：该内容未纳入原跨博主日报。</p>
</div> : null}
```

不要删除或替换现有的超时、失败、覆盖不完整和 gap 文案。迟到内容有 segment 时必须继续渲染 segment；迟到内容没有 segment 时不能因为 `lateArrival` 标记而生成观点卡片。

- [ ] **Step 4: Run focused GREEN and full Reader component tests**

Run:

```bash
cd apps/control-plane
npm test -- src/components/reader/x-reader.test.tsx -t "late"
npm test -- src/components/reader/x-reader.test.tsx
```

Expected: late badge appears only for `lateArrival: true`, normal cards remain unchanged, gaps remain visible, and existing v4/v5 layout and safe-output assertions pass.

- [ ] **Step 5: Commit the UI change**

```bash
git add apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/components/reader/x-reader.test.tsx
git commit -m "feat(reader): label late X collection"
```

---

### Task 3: 集成回归、对抗验证与本地 release handoff

**Files:**
- Read-only review: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Read-only review: `apps/control-plane/src/components/reader/XReader.tsx`
- Read-only review: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Read-only review: `apps/control-plane/src/components/reader/x-reader.test.tsx`
- No changes: `supabase/migrations/`, `workers/v0/`

**Interfaces:**
- Consumes: Task 1 repository projection and Task 2 Reader presentation.
- Produces: 本地验证证据和生产 release handoff；不执行部署、远程 migration、Worker reload 或真实 X 调用。

- [ ] **Step 1: Run the combined focused Reader tests**

Run:

```bash
cd apps/control-plane
npm test -- src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/x-reader.test.tsx
```

Expected: both suites pass, including late segment visibility, safe DTO redaction, gap retention, source/date filtering and existing daily judgement immutability.

- [ ] **Step 2: Run the full Control Plane test suite**

Run:

```bash
cd apps/control-plane
npm test
```

Expected: the full existing Control Plane suite passes without changing any assertion that expects the original judgement or coverage state to remain unchanged.

- [ ] **Step 3: Run static and build gates**

Run:

```bash
cd apps/control-plane
npm run lint
npm run build
git diff --check
bash ../../scripts/v0/redact-check.sh
```

Expected: lint, production build, diff check and redaction check pass. If a build failure is caused by the known external `node_modules` symlink issue, record it as an environment blocker and run the repository-approved supplemental webpack build only as supplemental evidence; do not hide the default build result.

- [ ] **Step 4: Perform fresh adversarial review**

Review the final diff against the Spec and verify all of the following:

```text
normal included segment -> visible, lateArrival=false
excluded batch + persisted succeeded segment -> visible, lateArrival=true
queued/running task without segment -> no fabricated content
gap without segment -> gap only, no viewpoint
late segment plus gap -> both late label and Shanghai gap range remain visible
late segment -> no judgement revision, no Provider call, no coverage mutation
source/date filters -> same projection rules as all-source view
```

Search the diff and output DTO for `task_id`, `range_task_id`, `settlement_status`, `exclusion_code`, `failure_class`, raw error text, prompt text and Provider output. Any such field crossing the Reader boundary is a stop-the-line finding.

- [ ] **Step 5: Verify no unintended production-scope changes**

Run:

```bash
git status --short
git diff --name-only HEAD~2..HEAD
git diff -- supabase/migrations workers/v0
```

Expected: only the Reader repository, Reader component and their tests changed; `supabase/migrations/` and `workers/v0/` are unchanged. Current production Worker remains running throughout this local work.

- [ ] **Step 6: Prepare release handoff without executing release actions**

Record the following handoff facts in the final report, without writing production data:

- exact implementation HEAD and commit list;
- local focused/full test results, lint, build, diff and redaction results;
- fresh review Critical/Important/Minor findings;
- no Supabase migration required by the implementation;
- deployment order: Control Plane release only, then read-only verification against one late persisted segment, one gap-only source and one normal source;
- explicitly unexecuted actions: remote migration, production data update, historical gap conversion, Worker reload, manual enqueue, real X/OpenCLI/Provider call and deployment.

No empty verification commit is required if Task 3 produces no file changes.

## Completion Criteria

- Task 1 and Task 2 each show actual RED before GREEN and have focused regression evidence.
- Full Control Plane tests, lint, build, diff check and redaction check pass, with any environment-only supplemental evidence clearly separated.
- Fresh review finds no Critical or Important issue and no internal failure metadata crosses the Reader DTO.
- The original cross-blogger daily judgement remains byte-for-byte semantically unchanged; no new revision is written.
- The current Worker was not stopped and no production state was changed during development.
- Release handoff is prepared but production deployment and live verification remain separately authorized actions.
