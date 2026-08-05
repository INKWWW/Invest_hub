# X 判断对象范围与阅读展示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以版本化 v4 X 判断合同表达“有操作表述但对象未明确”，并把 `/x` 阅读页改为已确认的编辑式、统一观点展示。

**Architecture:** 正常 X 采集链路从单帖分析到跨博主判断统一升级为 v4，并由每一层严格校验 `action_scope_status` 与 `action_intent/action_scope` 的三态组合。已持久化 v2/v3 数据保持不变；Reader 仅作安全、可解释的兼容投影。v3 verification replay 是已冻结的历史验收合同，不升级、不回刷、不参与 v4 正常调度路径。

**Tech Stack:** Python 3 Worker、公共 Markdown Prompt、Supabase PostgreSQL/pgTAP、Next.js 16/React 19/TypeScript/Vitest、既有本机 Codex CLI Provider。

## Global Constraints

- 新合同固定为 `v4-x-post-analysis` / `v4-x-post-analysis-1`、`v4-x-window` / `v4-x-window-1`、`v4-x-cross-blogger` / `v4-x-cross-blogger-1`。
- `none/not_applicable/""`、非 `none/specified/非空对象`、非 `none/unspecified/""` 是唯一允许的操作范围组合。
- 正常 v4 路径必须拒绝 v2/v3 输入；v2/v3 历史记录只读兼容，绝不直接更新或回刷。
- `action_scope` 只能包含明确对象；“对象未明确”等解释文字只能进入 `uncertainties`。
- 保持系统不提供交易建议、来源/analysis/帖子证据同源校验、提示注入防护、opaque ID 防泄漏和普通用户 Reader-safe DTO。
- 不改采集、身份解析、调度、coverage、checkpoint、来源权限、Provider 或 v3 verification replay。
- 测试与 Git 中只使用公开合成 fixture；真实博主内容、Prompt、Cookie、Profile、密钥、内部生产 ID 和原始证据不得进入仓库。

---

### Task 1: 建立 v4 单帖、窗口与跨博主结构化合同

**Files:**
- Create: `workers/v0/prompts/v4_x_post_analysis.md`
- Create: `workers/v0/prompts/v4_x_window.md`
- Create: `workers/v0/prompts/v4_x_cross_blogger.md`
- Modify: `workers/v0/src/invest_hub_worker/structured.py`
- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Modify: `workers/v0/tests/test_x_structured_output.py`
- Modify: `workers/v0/tests/test_x_prompts.py`
- Modify: `workers/v0/tests/test_x_windowed_runtime.py`

**Interfaces:**
- Consumes: v3 parser inputs, existing canonical post/context evidence catalogs and `ProviderContext`.
- Produces: `parse_v4_x_post_analysis_output(...)`, `parse_v4_x_window_output(...)`, `parse_v4_x_cross_blogger_output(...)` and active normal-path Provider operations `v4_x_post_analysis`, `v4_x_window`, `v4_x_cross_blogger`.

- [ ] **Step 1: 写出三个失败的 v4 合同测试。**

  在 `test_x_structured_output.py` 为单帖、窗口和跨博主各增加公开合成条目：`action_intent = "build_position"`、`action_scope_status = "unspecified"`、`action_scope = ""`、不确定性为“对象未说明”。断言三种 parser 均接受该条目。再为每层添加反例：`unspecified` 带非空 scope、`specified` 带空 scope、`none` 非 `not_applicable`、或对象缺失说明被写进 scope，均抛出 `SchemaError`。

- [ ] **Step 2: 运行聚焦测试，确认当前 v3 parser 缺少字段而失败。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_structured_output.py' -v`

  Expected: 新增 v4 成功样例因 parser/版本不存在而失败；既有 v3 测试仍通过。

- [ ] **Step 3: 新增 v4 Prompt 与严格 parser。**

  三份 v4 Prompt 从 v3 的职责边界复制，不修改 v3 文件；每份 JSON item 都新增 `action_scope_status`。明确要求 `statement` 直接陈述事实，不以“博主认为”“一位博主表示”开头。`structured.py` 新增 `V4_X_*` 字段集、`V4_X_ACTION_SCOPE_STATUSES` 和共享的三态校验函数；v4 parser 必须执行现有完整字段、投资相关性、证据、来源、强共识、系统建议和 opaque ID 校验，不能透传 JSON。将正常 `XWindowedRuntime` 的公共 Prompt 文件、operation 名和 parser 调用改为 v4；保留 `XVerificationReplayRuntime` 使用 v3 文件与 v3 parser。

- [ ] **Step 4: 扩展 Prompt 与 Runtime 回归。**

  在 `test_x_prompts.py` 断言三份 v4 Prompt 存在、包含 v4 schema/version、`action_scope_status`、对象缺失规则、直接陈述规则和注入防护。更新 `test_x_windowed_runtime.py` 的 Recording Provider：正常路径的 operation 序列必须为 `v4_x_post_analysis → v4_x_window`，完成 payload 的 v4 schema/prompt/version 与每个分析/窗口输出一致；v3 verification replay 测试保持 v3 operation 不变。

- [ ] **Step 5: 运行 Worker 聚焦测试，确认通过。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_structured_output.py' -v && PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_prompts.py' -v && PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_x_windowed_runtime.py' -v`

  Expected: 所有聚焦 Worker 测试通过，且 replay 仍固定 v3。

- [ ] **Step 6: 提交本任务。**

  ```bash
  git add workers/v0/prompts/v4_x_post_analysis.md workers/v0/prompts/v4_x_window.md workers/v0/prompts/v4_x_cross_blogger.md workers/v0/src/invest_hub_worker/structured.py workers/v0/src/invest_hub_worker/runtime.py workers/v0/tests/test_x_structured_output.py workers/v0/tests/test_x_prompts.py workers/v0/tests/test_x_windowed_runtime.py
  git commit -m "feat: add v4 X judgement scope contract"
  ```

### Task 2: 将正常持久化与判断上下文升级为 v4

**Files:**
- Create: 由 `supabase migration new x_judgement_scope_v4` 生成的 `supabase/migrations/*_x_judgement_scope_v4.sql`
- Create: `supabase/tests/036_x_judgement_scope_v4.sql`
- Modify: `workers/v0/tests/test_x_windowed_runtime.py`

**Interfaces:**
- Consumes: Task 1 的 v4 completion payload 与既有 `complete_windowed_capture_range`、`get_x_daily_judgement_context`、`complete_x_daily_judgement` RPC 名称。
- Produces: 正常采集仅将 v4 单帖/窗口输出持久化，daily context 仅为全 v4 冻结输入生成 `v4-x-cross-blogger-1`，并以 v4 validator 写入 daily version。

- [ ] **Step 1: 用 CLI 创建 migration 与 pgTAP 红灯用例。**

  Run: `supabase migration new x_judgement_scope_v4`

  在 CLI 新建的 migration 中只替换相关 check constraint 与函数定义；在 `036_x_judgement_scope_v4.sql` 建立公开合成 source/post/window/batch。先写 pgTAP：有效 `unspecified` 正常完成并生成 v4 context；三种非法组合被拒绝；v3 冻结 batch 仍走旧 v3 分支或被新 normal v4 path 安全拒绝，不发生写入。

- [ ] **Step 2: 运行新增 pgTAP，确认 v4 尚未被数据库接受。**

  Run: `supabase test db --file supabase/tests/036_x_judgement_scope_v4.sql`

  Expected: v4 schema/prompt 或 `action_scope_status` 尚不被允许，新增成功用例失败。

- [ ] **Step 3: 最小化改造正常 RPC。**

  在新 migration 中：

  - 扩展 `x_post_analyses` 与 `x_daily_viewpoint_segments` 的版本化 check constraint，使其接受既有 v2/v3 与新 v4 JSON，不改变已有行。
  - 增加 `complete_windowed_capture_range_v4_x_core`，严格接受 v4 单帖/窗口 field 集和 v4 Prompt/version；将普通 `complete_windowed_capture_range` 按 v4 → v3 → v2 分派，旧分支不变。
  - 增加 v4 judgement output/authority validator；校验每个 item 的 `action_scope_status`、范围组合、ID 同源、安全文本与强共识边界。
  - 只在 batch 的 included segments 和 analyses 全部为 v4 时返回 v4 daily context；否则保留既有 v2/v3 历史分支，绝不能拼接混合版本输入。
  - 将普通 `complete_x_daily_judgement`、daily version trigger/authority 分支扩展为 v4；持久化 `schema_version = 'v4-x-cross-blogger'` 和 `prompt_version = 'v4-x-cross-blogger-1'`。
  - 维持 service-role grants/revokes，且不修改 v3 verification replay RPC/table/function。

- [ ] **Step 4: 完成 SQL 合同回归。**

  在 pgTAP 中额外断言：v4 payload 的对象缺失文本在 `uncertainties` 可存、在 `action_scope` 必拒绝；`specified` 条目保留 scope；`none/not_applicable` 不能携带 scope；非法的 extra field、未知 enum、跨分析/帖子证据和 opaque ID 均失败。断言已有 v3 fixture 继续可读。

- [ ] **Step 5: 运行全部数据库相关回归。**

  Run: `supabase test db --file supabase/tests/032_x_upstream_prompt_v3_alignment.sql && supabase test db --file supabase/tests/036_x_judgement_scope_v4.sql && supabase test db`

  Expected: v3 兼容测试、v4 新测试和全量 pgTAP 均通过。

- [ ] **Step 6: 提交本任务。**

  ```bash
  git add supabase/migrations/*_x_judgement_scope_v4.sql supabase/tests/036_x_judgement_scope_v4.sql workers/v0/tests/test_x_windowed_runtime.py
  git commit -m "feat: persist v4 X judgement scope state"
  ```

### Task 3: 对齐 Worker Protocol 与控制面正常 completion 接口

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/protocol.py`
- Modify: `workers/v0/tests/test_protocol.py`
- Modify: `apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`

**Interfaces:**
- Consumes: Task 2 返回的 v4 daily context 和 Task 1 的 v4 runtime completion。
- Produces: 正常 Worker endpoint 只接受 `v4-x-cross-blogger` / `v4-x-cross-blogger-1` 且严格校验每个 v4 judgement item；独立 v3 replay endpoint 不变。

- [ ] **Step 1: 写出 Worker 与 HTTP 边界的失败测试。**

  在 `test_protocol.py` 构造完整公开合成 v4 context/completion，包含 `unspecified` 条目，断言本地解析与 completion 校验通过。再断言缺 `action_scope_status`、非法三态组合、v3 context/completion、额外字段和不安全 `model_reported` 在发 HTTP 前抛出 `ProtocolError`。在 `api.integration.test.ts` 为 normal completion route 加等价的 422 拒绝和一次 200 成功断言。

- [ ] **Step 2: 运行聚焦测试，确认现有 v3 normal endpoint 拒绝 v4。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_protocol.py' -v && npm --prefix apps/control-plane test -- src/app/api/api.integration.test.ts`

  Expected: 有效 v4 fixture 因 v3 version/field 集被拒绝。

- [ ] **Step 3: 实现 normal v4 Protocol/route 校验。**

  把 normal daily judgement 的 context version、segment/analysis version、completion version和 item field 集切换为 v4，并以同一三态规则验证。保留当前 source/analysis/evidence ownership、opaque-ID、强共识和 lease 错误处理；不要放宽为 JSON 透传。只修改 normal daily endpoint；`x-v3-verification-replays` 路由与 replay Protocol 分支继续严格接受 v3。

- [ ] **Step 4: 运行聚焦边界回归。**

  Run: `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_protocol.py' -v && npm --prefix apps/control-plane test -- src/app/api/api.integration.test.ts`

  Expected: 有效 v4 completion 成功；所有非法组合与 v3 normal completion 拒绝；v3 replay 相关测试仍通过。

- [ ] **Step 5: 提交本任务。**

  ```bash
  git add workers/v0/src/invest_hub_worker/protocol.py workers/v0/tests/test_protocol.py apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts apps/control-plane/src/app/api/api.integration.test.ts
  git commit -m "feat: validate v4 X judgement completion"
  ```

### Task 4: 实现统一 Reader 投影与编辑式展示

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Modify: `apps/control-plane/src/app/globals.css`
- Modify: `apps/control-plane/src/app/api/reader/x/route.ts`
- Modify: `apps/control-plane/src/components/reader/XReader.test.tsx`（如不存在则新建）
- Modify: `apps/control-plane/src/app/api/reader/x/route.test.ts`

**Interfaces:**
- Consumes: v2/v3/v4 Reader output JSON，以及 v4 `action_scope_status`。
- Produces: `ReaderJudgement` 的安全 `actionScopeStatus: "specified" | "unspecified" | "not_applicable"` 投影和统一的观点显示组件。

- [ ] **Step 1: 先写 Reader DTO 与组件失败测试。**

  为 repository/route fixture 添加 v4 `unspecified` item，断言 API 只输出安全展示字段、不会输出内部 ID，且 `actionScope` 为空。添加已存 v3 fixture：scope 为对象缺失占位说明、uncertainty 明确对象缺失，断言投影为 `unspecified`，而没有证据的 v3 item 不被猜测。组件测试断言：显示“操作表述：建仓”“对象：未明确，不可据此执行”；对象明确时显示对象；正文不显示精确可剥离的“博主认为”前缀。

- [ ] **Step 2: 运行 Reader 测试，确认当前组件直出伪对象且布局不一致。**

  Run: `npm --prefix apps/control-plane test -- src/app/api/reader/x/route.test.ts src/components/reader/XReader.test.tsx`

  Expected: 新的 v4 字段未投影，`unspecified` 显示和统一观点结构断言失败。

- [ ] **Step 3: 实现安全投影与展示 helper。**

  在 `reader.ts` 解析 `action_scope_status`；只接受 v4 三态组合。为历史 v3 设计单一、可测试的 `legacyActionScopeStatus` helper：只有 scope 本身为明确占位标记，或 uncertainty 明确对象/资产/范围缺失时才返回 `unspecified`；否则不推断。将页面和 API DTO 都携带最小的 `actionIntent/actionScope/actionScopeStatus/conditions` 展示字段。

  在 `XReader.tsx` 将当日判断和单博主窗口改为同一个观点条目组件：主题 → `观点 NN` → 直接陈述正文 → 元信息。仅剥离完全匹配的纯归因前缀；不改动其他文本。`unspecified` 显示不可执行对象提示，不显示占位 scope。保留原始链接、折叠窗口、筛选和时间排序。

  在 `globals.css` 将连环 `.topic-card`/作者卡片改为平铺编辑式布局：两个全宽、浅色中文模块标题带；细分割线与留白；单博主标题行加粗；没有嵌套卡片、粗边线或新的横向滚动。

- [ ] **Step 4: 运行 UI/API 测试、lint 与 production build。**

  Run: `npm --prefix apps/control-plane test -- src/app/api/reader/x/route.test.ts src/components/reader/XReader.test.tsx src/app/api/api.integration.test.ts && npm --prefix apps/control-plane run lint && npm --prefix apps/control-plane run build`

  Expected: Reader safe DTO、v2/v3 兼容、v4 三态和布局组件测试均通过；lint 与 production build 成功。

- [ ] **Step 5: 提交本任务。**

  ```bash
  git add apps/control-plane/src/lib/db/repositories/reader.ts apps/control-plane/src/components/reader/XReader.tsx apps/control-plane/src/app/globals.css apps/control-plane/src/app/api/reader/x/route.ts apps/control-plane/src/components/reader/XReader.test.tsx apps/control-plane/src/app/api/reader/x/route.test.ts
  git commit -m "feat: clarify X judgement scope in reader"
  ```

### Task 5: 全链路验证、生产发布与审计记录

**Files:**
- Modify: `docs/project-status.md`
- Create: `docs/engineering-journal/2026-08-05-x-judgement-scope-and-reader-presentation.md`
- Modify: `docs/superpowers/plans/2026-08-05-x-judgement-scope-and-reader-presentation.md`

**Interfaces:**
- Consumes: Tasks 1–4 的已提交工作树、v4 migration、Worker 与 control-plane 构件。
- Produces: 已部署的 normal v4 路径、已重启的 X Worker、稳定 `/x` 只读验收和可审计发布记录。

- [ ] **Step 1: 执行全量本地验证并保存命令/结果。**

  Run:

  ```bash
  supabase test db
  PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
  npm --prefix apps/control-plane test
  npm --prefix apps/control-plane run lint
  npm --prefix apps/control-plane run build
  git diff --check
  bash scripts/v0/redact-check.sh
  ```

  Expected: 所有命令成功；若既有环境问题阻断默认 build，记录准确失败原因并仅在与上次已知基线一致、独立 webpack build 成功时继续评估，不将其误报为本次功能回归。

- [ ] **Step 2: 在同一待发布提交上应用 v4 migration。**

  先以只读 `supabase migration list` 确认远端 history 和目标项目；运行本地 dry-run/测试后应用仅 Task 2 新生成的 migration。随后只读查询 migration history 与 v4 function/constraint 存在性；不得使用 `migration repair`、`db pull` 或直接 DML 修改历史 judgement。

- [ ] **Step 3: 发布控制面并重启同一提交的 X Worker。**

  将已验证提交推送 `origin/main`，从 `apps/control-plane` 使用 `npx --yes vercel@latest --prod --yes` 部署，确认 deployment 为 `READY` 且稳定 `/x` 指向该版本。随后仅重启 `com.investhub.x-worker` 并核对它从同一 checkout 加载；不手工调用 Provider、不触发采集或回刷。

- [ ] **Step 4: 完成生产只读验收。**

  在已登录普通用户会话打开稳定 `/x`，核对桌面与 375px：两个模块标题带、加粗博主行、统一观点层级、历史 v3 的对象未明确降级显示、博主/日期筛选与最新窗口优先。等待下一次正常 v4 scheduler window 作为新持久化合同的唯一生产证据；只读检查其 status、schema/prompt version、Reader 输出和无对象动作的显示。若没有正常窗口，不宣称 v4 正常链路已被生产证明。

- [ ] **Step 5: 写工程记录与状态，并提交。**

  工程记录必须写明 migration 版本、提交、部署、Worker reload、各 gate 结果、普通用户页面验收、是否已有正常 v4 window；`docs/project-status.md` 只能据此更新，不能把“READY”替代端到端 Scheduler 证据。勾选 Plan 中实际完成的步骤。

  ```bash
  git add docs/project-status.md docs/engineering-journal/2026-08-05-x-judgement-scope-and-reader-presentation.md docs/superpowers/plans/2026-08-05-x-judgement-scope-and-reader-presentation.md
  git commit -m "docs: record X judgement scope v4 release"
  git push origin main
  ```
