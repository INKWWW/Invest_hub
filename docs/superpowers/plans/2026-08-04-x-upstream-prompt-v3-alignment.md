# X 上游 Prompt v3 对齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 让新的 X 单帖分析、单博主窗口和跨博主当日判断形成一条严格验证、不可变且可安全阅读的 v3 证据链，同时完整保留 v2 历史。

**Architecture:** 单帖与窗口分别新增 v3 Prompt 和 parser；X Runtime 默认产生 version 2 的 v3 analysis 与 v3 segment。追加式数据库 migration 在原有不可变表中保存权威 v3 JSON，并将跨博主 context/authority 切换为引用的 v3 证据；Reader 依据每个 segment 的 schema 版本投影 v2 或 v3 内容。

**Tech Stack:** Python 3 unittest、Codex CLI Provider 边界、PostgreSQL/Supabase pgTAP、Next.js/TypeScript/Vitest、Vercel、launchd Worker。

## Global Constraints

- 新单帖 Prompt/version 为 v3-x-post-analysis-1 / v3-x-post-analysis；新窗口 Prompt/version 为 v3-x-window-1 / v3-x-window；当日判断继续为 v3-x-cross-blogger-1 / v3-x-cross-blogger。
- 新单帖 analysis 使用 analysis_version = 2；v2 行、v2 Prompt、既有 v2 segment 和 judgement 不得更新、删除、回刷或伪造成 v3。
- 所有 schema、来源、分析、证据、行动倾向、范围、条件和 telemetry 验证均 fail closed；非法上游结果为 schema_error，不得发送 completion 或留下部分持久化结果。
- 公开仓库只使用人工构造的公开 fixture；不得提交真实博主文本、Prompt 私有补充、Cookie、Profile、路径、任务/批次/分析 ID 或 Provider telemetry。
- 不手工触发真实采集、Provider、batch、judgement 或历史回放；首条真实 v3 链路只由正常 scheduler 产生。

---

### Task 1: Public Prompt v3 Contracts

**Files:**

- Create: workers/v0/prompts/v3_x_post_analysis.md
- Create: workers/v0/prompts/v3_x_window.md
- Modify: workers/v0/prompts/v3_x_cross_blogger.md
- Test: workers/v0/tests/test_x_prompts.py

**Interfaces:**

- Consumes: 合成 post/context_post 输入，以及 v3 post_analyses 窗口输入。
- Produces: 三份公开 Prompt 的精确 schema/version、信任边界、分类和证据规则。

- [ ] **Step 1: Write failing Prompt contract tests**

~~~python
def test_v3_upstream_prompts_publish_exact_versions_and_required_boundaries(self) -> None:
    post = _read_prompt("v3_x_post_analysis.md")
    window = _read_prompt("v3_x_window.md")
    daily = _read_prompt("v3_x_cross_blogger.md")
    self.assertIn('"schema_version": "v3-x-post-analysis"', post)
    self.assertIn('"schema_version": "v3-x-window"', window)
    self.assertIn("security_industry_viewpoints", window)
    self.assertIn("完整 v3 单帖分析", daily)
~~~

- [ ] **Step 2: Run the focused test and confirm RED**

Run: PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_prompts.py' -v

Expected: FAIL because the two v3 upstream Prompt files do not exist and daily input instructions do not name v3 upstream analyses.

- [ ] **Step 3: Add the public Prompt files and revise daily input instructions**

Write the approved v3 contracts exactly: post relevance/category/action/condition/evidence/repost rules; window three-category atomic items and complete input coverage; daily input explicitly permits only the v3 segment and v3 analysis shape. Keep all prose generic and public; preserve daily output schema unchanged.

- [ ] **Step 4: Run the focused Prompt tests and confirm GREEN**

Run: PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_prompts.py' -v

Expected: PASS.

- [ ] **Step 5: Commit the Prompt contracts**

~~~bash
git add workers/v0/prompts/v3_x_post_analysis.md workers/v0/prompts/v3_x_window.md workers/v0/prompts/v3_x_cross_blogger.md workers/v0/tests/test_x_prompts.py
git commit -m "feat: add X upstream prompt v3 contracts"
~~~

### Task 2: Strict v3 Upstream Structured Parsers

**Files:**

- Modify: workers/v0/src/invest_hub_worker/structured.py
- Modify: workers/v0/tests/test_x_structured_output.py

**Interfaces:**

- Consumes: parse_v3_x_post_analysis_output(text, allowed_post_ids, allowed_context_post_ids) and parse_v3_x_window_output(text, allowed_analysis_ids, analysis_evidence_post_ids).
- Produces: normalized v3 post and window mappings, or SchemaError before Runtime persistence.

- [ ] **Step 1: Write failing v3 parser tests**

~~~python
def test_v3_post_parser_accepts_one_grounded_related_post(self) -> None:
    output = parse_v3_x_post_analysis_output(json.dumps(V3_POST), {"post-1"}, {"post-1": {"context-1"}})
    self.assertEqual(output["analyses"][0]["investment_categories"], ["security_industry"])

def test_v3_window_parser_rejects_partial_input_coverage(self) -> None:
    with self.assertRaises(SchemaError):
        parse_v3_x_window_output(json.dumps(V3_WINDOW_MISSING_ANALYSIS), {"post-1@2", "post-2@2"}, {"post-1@2": {"post-1"}, "post-2@2": {"post-2"}})
~~~

Also cover exact fields, one analysis per input post, relevance gate, none/scope consistency, explicit-only action enum, context-only evidence, repost attribution, natural-language ID rejection, three categories, atomic window evidence ownership, duplicate IDs, unknown analysis/evidence, and full top-level coverage.

- [ ] **Step 2: Run the focused parser tests and confirm RED**

Run: PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_structured_output.py' -v

Expected: FAIL because v3 parser functions are undefined.

- [ ] **Step 3: Implement the minimal strict parser functions**

Add v3 field sets and V3_X_ACTION_INTENTS; reuse existing JSON/exact-field/opaque-ID helpers. Require window item evidence to equal the union of its referenced v3 analyses and require top-level IDs to equal all input v3 analysis/evidence IDs. Keep v2 parser behavior untouched.

- [ ] **Step 4: Run the focused parser tests and confirm GREEN**

Run: PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_structured_output.py' -v

Expected: PASS.

- [ ] **Step 5: Commit the parser boundary**

~~~bash
git add workers/v0/src/invest_hub_worker/structured.py workers/v0/tests/test_x_structured_output.py
git commit -m "feat: validate X upstream v3 output"
~~~

### Task 3: Runtime v3 Production Payload

**Files:**

- Modify: workers/v0/src/invest_hub_worker/runtime.py
- Modify: workers/v0/tests/test_x_windowed_runtime.py

**Interfaces:**

- Consumes: v3 parser output and the existing AuthorizedXRuntime.execute_windowed claim.
- Produces: range completion payload with x_post_analyses[*].analysis_version = 2, schema_version, prompt_version, analysis_output, and a v3 x_daily_segments[*].segment_output.

- [ ] **Step 1: Write failing Runtime tests**

~~~python
def test_x_runtime_emits_v3_analysis_and_window_payloads(self) -> None:
    result = runtime.execute_windowed(CLAIM)
    analysis = result["range_completion"]["x_post_analyses"][0]
    segment = result["range_completion"]["x_daily_segments"][0]
    self.assertEqual((analysis["analysis_version"], analysis["schema_version"]), (2, "v3-x-post-analysis"))
    self.assertEqual(segment["schema_version"], "v3-x-window")
~~~

Add failure tests that malformed v3 post/window output stops before completion, and that Provider contexts use v3_x_post_analysis / v3_x_window operations and the matching public Prompt templates.

- [ ] **Step 2: Run the focused Runtime tests and confirm RED**

Run: PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_windowed_runtime.py' -v

Expected: FAIL because Runtime still emits version 1 and v2 payload fields.

- [ ] **Step 3: Switch new Runtime output to v3**

Read the two new Prompt files; call the v3 parsers; emit exact v3 schema/prompt versions and normalized JSON in analysis_output/segment_output. Continue projecting v3 blogger_viewpoint, arguments, quoted_post_viewpoint, uncertainties, and evidence into existing required fields, while window_viewpoints is [] for v3. Do not change claim/source parameter version handling.

- [ ] **Step 4: Run the focused Runtime tests and confirm GREEN**

Run: PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_windowed_runtime.py' -v

Expected: PASS.

- [ ] **Step 5: Commit the Runtime transition**

~~~bash
git add workers/v0/src/invest_hub_worker/runtime.py workers/v0/tests/test_x_windowed_runtime.py
git commit -m "feat: emit X upstream v3 analysis chain"
~~~

### Task 4: Additive Database Migration and Authority Chain

**Files:**

- Create: the migration produced by supabase migration new x_upstream_prompt_v3_alignment
- Create: supabase/tests/032_x_upstream_prompt_v3_alignment.sql
- Modify: apps/control-plane/src/lib/db/types.ts

**Interfaces:**

- Consumes: exact v2 or v3 range completion payloads through complete_windowed_capture_range.
- Produces: immutable v3 rows and a v3-only cross-blogger context/authority graph; preserves the existing v2 path for in-flight work.

- [ ] **Step 1: Generate the migration and write failing pgTAP tests**

Run supabase migration new x_upstream_prompt_v3_alignment from the repository root, then add tests that call the existing completion RPC with synthetic v3 data and assert: version-2 insertion; v2 rows unchanged; invalid schema/prompt/analysis/evidence rejected; mismatched repeated version-2 output conflicts; v3 context exposes three window categories and v3 analyses; v2-only upstream evidence is rejected for a v3 daily run.

- [ ] **Step 2: Run the new pgTAP file and confirm RED**

Run: supabase test db --file supabase/tests/032_x_upstream_prompt_v3_alignment.sql

Expected: FAIL because v3 columns and range-completion/context support do not exist.

- [ ] **Step 3: Implement the additive migration**

Add non-null schema/prompt version and JSON output columns to both immutable tables, preserving legacy v2 values by default without row updates. Add exact JSON/type checks; create a v3 range-completion core and make the existing wrapper dispatch exact v2 versus v3 payloads. Update daily context construction, input snapshot validation and authority checks to use segment refs and v3 JSON, including @2 ownership/evidence validation. Retain grants/RLS and only the existing service-role RPC boundary.

- [ ] **Step 4: Regenerate control-plane database types**

Use the repository's existing Supabase type-generation command discovered with supabase gen types --help; update apps/control-plane/src/lib/db/types.ts only with the generated shape for the added columns and unchanged RPC signatures.

- [ ] **Step 5: Run migration-focused tests and confirm GREEN**

Run: supabase test db --file supabase/tests/032_x_upstream_prompt_v3_alignment.sql

Expected: PASS.

- [ ] **Step 6: Commit the database contract**

~~~bash
git add supabase/migrations supabase/tests/032_x_upstream_prompt_v3_alignment.sql apps/control-plane/src/lib/db/types.ts
git commit -m "feat: persist X upstream v3 evidence"
~~~

### Task 5: Reader-safe v3 Blogger Projection and UI

**Files:**

- Modify: apps/control-plane/src/lib/db/repositories/reader.ts
- Modify: apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts
- Modify: apps/control-plane/src/components/reader/XReader.tsx
- Modify: apps/control-plane/src/components/reader/x-reader.test.tsx

**Interfaces:**

- Consumes: segment schema/version/output plus referenced analysis schema/version/output.
- Produces: XReaderSegment with v2 legacy or v3 categorized window/analysis data, without internal IDs or raw source text.

- [ ] **Step 1: Write failing repository and component tests**

~~~tsx
expect(screen.getByRole("heading", { name: "个股与产业观点" })).toBeInTheDocument();
expect(screen.getByText("博主倾向：买入（测试标的）")).toBeInTheDocument();
expect(screen.queryByText("post-1@2")).not.toBeInTheDocument();
~~~

Add repository fixtures with one v2 segment and one v3 segment that refer to different analysis versions of the same post. Assert that v3 reads its analysis_output, v2 stays legacy, windows are newest first, and no raw body/prompt/internal IDs are returned.

- [ ] **Step 2: Run focused Reader tests and confirm RED**

Run from apps/control-plane: npm test -- --run src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/x-reader.test.tsx

Expected: FAIL because Reader fixes analysis version 1 and the component has only flat window_viewpoints.

- [ ] **Step 3: Implement the safe dual-version projection**

Select schema/version/output columns, index analyses by (canonical_message_id, analysis_version), and validate v3 natural-language fields before exposing them. Extend XReaderSegment with three optional categorized lists and enriched safe analysis details. Render categorized v3 cards before the v3 per-post facts; preserve old flat cards for v2. Keep all current filters and date → judgement → blogger hierarchy unchanged.

- [ ] **Step 4: Run focused Reader tests and confirm GREEN**

Run from apps/control-plane: npm test -- --run src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/x-reader.test.tsx

Expected: PASS.

- [ ] **Step 5: Commit the Reader projection**

~~~bash
git add apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/components/reader/x-reader.test.tsx
git commit -m "feat: display X blogger viewpoints from v3 evidence"
~~~

### Task 6: Full Regression, Release, and Production Acceptance

**Files:**

- Modify: docs/superpowers/plans/2026-08-04-x-upstream-prompt-v3-alignment.md
- Modify: docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md
- Modify: docs/project-status.md

**Interfaces:**

- Consumes: committed local implementation, remote migration history, stable production deployment and normal Worker schedule.
- Produces: released v3 upstream capability with evidence-backed operational record; no claim of a real v3 generation before the normal scheduler produces one.

- [ ] **Step 1: Run complete local verification**

~~~bash
supabase test db
PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
cd apps/control-plane && npm test -- --run && npm run lint && npm run build
cd ../.. && git diff --check && bash scripts/v0/redact-check.sh
~~~

Expected: all commands pass. If the default production build has a pre-existing environmental failure, record the exact cause and separately run the existing approved webpack fallback; do not call that a full default-build pass.

- [ ] **Step 2: Review the release diff and commit release records**

Verify the only production changes are the two v3 Prompt files, parser/Runtime, one additive migration, generated types, Reader/tests and project records. Update completed plan checkboxes and document actual test counts, commit SHA, migration version, deployment readiness and acceptance result; do not record future scheduler output as complete.

- [ ] **Step 3: Pause Worker, dry-run and apply the remote migration**

Stop X claiming through the existing com.investhub.x-worker service. Read remote migration history and run the repository's migration dry-run; verify it contains exactly the new generated migration. Apply it once, then read back the migration history and the new column/RPC contract with safe synthetic/read-only SQL. Do not inspect or emit real X content.

- [ ] **Step 4: Push, deploy and confirm the stable deployment**

Push the verified main commit to origin/main; deploy the control plane with the repository's configured Vercel production path. Confirm the deployment is Ready and the stable /x URL resolves to the released commit before restarting Worker.

- [ ] **Step 5: Reload Worker and perform authenticated read-only acceptance**

Reload com.investhub.x-worker from that same main checkout. On an existing authenticated production /x session, verify date → daily judgement → blogger hierarchy, newest window first, v2 readability and absence of raw/internal/Prompt/telemetry exposure. Do not cause a collection or model call.

- [ ] **Step 6: Record completion and final state**

Commit and push the journal/status/plan record. Report deployment and Worker state separately from the next normal scheduler’s first real v3 evidence; monitor it only by safe read-only state inspection.

