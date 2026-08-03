# X 当日判断 Prompt v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已确认的三类跨博主投资判断 Prompt v3 安全地贯通至 Worker、数据库和 X Reader。

**Architecture:** 保留 v2 历史记录和 Prompt 文件，新建版本化 v3 Prompt。所有新生成记录使用 v3；Python、HTTP 与 Postgres 均执行相同的字段、证据和操作倾向约束，Reader 仅投影已验证的安全字段。

**Tech Stack:** Python 3.12 Worker、Next.js/TypeScript、Supabase Postgres、Vitest、unittest、pgTAP。

## Global Constraints

- 只使用冻结的 `included` 来源；不暴露原文、Prompt、内部 ID、Cookie、Profile 或任务字段。
- `action_intent` 只能转述博主明确表达的倾向，不能成为系统建议。
- 不实现评测集、影子运行或采集调度改动。
- 旧 `v2-x-cross-blogger` 记录保持可读；新生成记录统一使用 `v3-x-cross-blogger-1`。

## Execution Record (2026-08-03)

Task 1、Task 2 和 Task 3 均已完成。Worker 的先失败后通过测试已记录；完整验证结果为 pgTAP 35 files / 580 tests、Worker 165 tests、control-plane 42 files / 232 tests、lint 与 production build 均通过。生产 migration `20260803100000`、deployment `dpl_EfqWarB463BqpLjEdeSXZx9nxkbU` 与已认证 `/x` 验收均已完成；历史 v2 判断保持不变，新 v3 判断在下一次正常生成时生效。

---

### Task 1: 建立 v3 Prompt 与 Worker 合同

**Files:**
- Create: `workers/v0/prompts/v3_x_cross_blogger.md`
- Modify: `workers/v0/src/invest_hub_worker/structured.py`
- Modify: `workers/v0/src/invest_hub_worker/runtime.py`
- Test: `workers/v0/tests/test_x_cross_blogger_judgements.py`

**Interfaces:**
- Produces: `parse_v3_x_cross_blogger_output(...) -> dict[str, object]`。
- Produces: Worker completion 的 `schema_version="v3-x-cross-blogger"` 与 `prompt_version="v3-x-cross-blogger-1"`。

- [ ] **Step 1: 写失败的 Worker 合同测试。**

  在 `test_x_cross_blogger_judgements.py` 增加 v3 fixture，覆盖三类数组、明确 `buy` 倾向、`none` 倾向、条件字段、非法枚举、缺失 `action_scope`、Prompt 版本与策略条目的跨来源证据拼接。

- [ ] **Step 2: 运行失败测试。**

  Run: `PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -p 'test_x_cross_blogger_judgements.py' -v`

  Expected: FAIL，因为 v3 parser 和 Prompt 尚不存在。

- [ ] **Step 3: 实现最小 v3 合同。**

  新增版本化公共 Prompt；实现 v3 严格字段校验、行动倾向枚举、条件/范围文本校验、opaque ID 与命令式系统建议拒绝；运行时只加载 v3 Prompt 并提交 v3 元数据。

- [ ] **Step 4: 运行 Worker 测试。**

  Run: `PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -p 'test_x_cross_blogger_judgements.py' -v`

  Expected: PASS。

### Task 2: 贯通数据库与 Worker HTTP 完成边界

**Files:**
- Create: `supabase/migrations/20260803100000_x_daily_judgement_prompt_v3.sql`
- Modify: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts`
- Modify: `apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts`
- Test: `supabase/tests/030_v3_x_daily_judgement_prompt_contract.sql`
- Test: `apps/control-plane/src/app/api/api.integration.test.ts`
- Test: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.test.ts`

**Interfaces:**
- Consumes: Task 1 的 v3 completion。
- Produces: 原子 RPC 只持久化有效 v3 输出，且 `get_x_daily_judgement_context` 返回 v3 Prompt 版本。

- [ ] **Step 1: 写失败的数据库与 HTTP 测试。**

  新增 pgTAP 用例，验证 v3 策略条目可提交、非法行动倾向被拒绝、策略条目的引用必须同源；新增 TypeScript 用例，验证 HTTP 接口拒绝 v2 metadata 并接受完整 v3 completion。

- [ ] **Step 2: 运行失败测试。**

  Run: `npm test -- --run src/app/api/api.integration.test.ts src/lib/db/repositories/x-daily-judgements.test.ts`

  Expected: FAIL，因为控制面仍只接受 v2 字段。

- [ ] **Step 3: 实现最小持久化边界。**

  迁移覆盖 v3 输出、权威证据、上下文与完成 RPC；控制面类型与 HTTP 校验改为同一 v3 合同；无新信息默认输出同步为 v3 空数组。

- [ ] **Step 4: 运行数据库与控制面测试。**

  Run: `supabase test db && npm test -- --run src/app/api/api.integration.test.ts src/lib/db/repositories/x-daily-judgements.test.ts`

  Expected: PASS。

### Task 3: 扩展安全阅读投影并完成验证记录

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/reader.ts`
- Modify: `apps/control-plane/src/components/reader/XReader.tsx`
- Test: `apps/control-plane/src/lib/db/repositories/reader-source-navigation.test.ts`
- Test: `apps/control-plane/src/components/reader/XReader.test.tsx`
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`

**Interfaces:**
- Consumes: Task 2 已持久化的 v3 输出与旧 v2 输出。
- Produces: 三类判断区块与安全的“博主倾向、适用范围、条件”展示。

- [ ] **Step 1: 写失败的 Reader 测试。**

  增加 v3 输出 fixture，断言三个主题均显示、行动倾向和条件可读、内部 ID 不出现；保留 v2 fixture，断言历史两类条目仍展示且没有伪造的新字段。

- [ ] **Step 2: 运行失败测试。**

  Run: `npm test -- --run src/lib/db/repositories/reader-source-navigation.test.ts src/components/reader/XReader.test.tsx`

  Expected: FAIL，因为 Reader 尚未投影第三类和行动字段。

- [ ] **Step 3: 实现最小 Reader 投影。**

  扩展 Reader DTO 与卡片；只读取并展示 schema 允许的自然语言字段和已映射显示名；调整“无判断”判断条件以包含第三类。

- [ ] **Step 4: 运行全量验证并记录。**

  Run: `PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v && npm test -- --run && npm run lint && npm run build && bash scripts/v0/redact-check.sh && git diff --check`

  Expected: PASS；随后记录实际测试结果、迁移、部署和生产页面验收证据。
