# X 连续恢复与手动完整运行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement task-by-task.

**Goal:** 自动让停滞的 X 来源安全追平连续水位，并让管理员可请求一次完整补采和新的 X 总结。

**Architecture:** 在既有 scheduler 中对精确水位阻塞的 terminal root task 创建至多一次 system replacement；成功后继续复用既有逐窗口 enqueue。新增很小的 manual-run parent 与 frozen source map；它等待同一连续队列追平，再用既有任务证据建立独立 batch，并复用 settlement 与 v3 daily-judgement pipeline。

**Tech Stack:** PostgreSQL/Supabase RPC + pgTAP、Next.js App Router、TypeScript/Vitest、Python unittest。

## Global Constraints

- 不改写原 failed task、attempt、coverage、scheduled batch 或 judgement version。
- 每个 terminal root task 最多一个 replacement；replacement 失败后不得创建第三个 task。
- 新 public table 启用 RLS；管理员入口由 server route 鉴权，浏览器不持有 service key。
- 手动 run 的 cutoff 与来源集合在创建时冻结；按钮不连接 X 或本机 Chrome。

### Task 1: 数据库连续恢复与手动 run 契约

**Files:**

- Create: `supabase/migrations/<generated>_x_continuous_recovery_manual_run.sql`
- Create: `supabase/tests/035_x_continuous_recovery_manual_run.sql`
- Modify: `apps/control-plane/src/lib/db/types.ts`

**Interfaces:** `advance_x_manual_recovery_runs(p_worker_id uuid, p_now timestamptz)` 推进冻结 run；`create_x_manual_recovery_run(p_requested_by uuid, p_now timestamptz)` 创建或复用一个 run；`enqueue_due_x_tasks` 只为 terminal root task 创建一次 replacement。

- [ ] 写 pgTAP RED：普通用户不能创建 run；同一 cutoff 幂等；root terminal 只有一个 replacement；complete run 生成 manual batch；replacement 失败不会生成第二个 replacement 或 summary。
- [ ] 运行 `supabase test db --local supabase/tests/035_x_continuous_recovery_manual_run.sql`，确认因缺少 table/function 失败。
- [ ] 用 `supabase migration new x_continuous_recovery_manual_run` 创建 migration；增加 parent/source-map、RLS、受限 RPC、manual batch identity 与 scheduler advance。
- [ ] 重置本地库并重跑该 pgTAP；生成 DB 类型；提交 `feat: recover stalled X sources continuously`。

### Task 2: Worker schedule 路径与 repository

**Files:**

- Modify: `apps/control-plane/src/lib/db/repositories/tasks.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/tasks.test.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts`
- Modify: `workers/v0/tests/test_cli.py`

**Interfaces:** `scheduleDueSourceTasks` 在既有 source enqueue 和 batch dispatcher 后调用 `advanceXManualRecoveryRuns`；结果只包含安全计数和状态。

- [ ] 写 RED：repository 对 `advance_x_manual_recovery_runs` 的 RPC 调用，以及 scheduler failure 不阻止现有 task claim。
- [ ] 运行 focused Vitest 与 `PYTHONPATH=workers/v0/src workers/v0/.venv/bin/python -m unittest workers/v0/tests/test_cli.py -v`，确认 RED。
- [ ] 写最小 repository 调用与安全结果映射；不改变 Worker 每 tick 只 claim 一个 task 的约束。
- [ ] 重跑 focused tests；提交 `feat: advance manual X recovery runs in scheduler`。

### Task 3: 管理员按钮、route 与状态

**Files:**

- Create: `apps/control-plane/src/app/api/admin/x/manual-recovery/route.ts`
- Create: `apps/control-plane/src/app/api/admin/x/manual-recovery/route.test.ts`
- Create: `apps/control-plane/src/components/admin/XManualRecoveryRunForm.tsx`
- Modify: `apps/control-plane/src/app/admin/page.tsx`
- Modify: `apps/control-plane/src/app/globals.css`
- Modify: `apps/control-plane/src/lib/db/repositories/x-daily-judgements.ts`

**Interfaces:** `createManualXRecoveryRun(actorId)` 返回 `{id,status,targetCutoffAt,idempotent}`；route 仅接受 `{}` 并返回 HTTP 202。

- [ ] 写 RED：管理员获得 queued run；非管理员拒绝；无效 body 拒绝；重复请求返回同一个活动 run。
- [ ] 运行 `npm test -- manual-recovery/route.test.ts admin-ui.test.tsx`，确认 RED。
- [ ] 写 admin-only route 和紧凑 form：按钮“补采并重新生成 X 总结”，显示排队/进行中/失败状态，隐藏 IDs 与异常详情。
- [ ] 重跑 focused tests；提交 `feat: add manual X recovery control`。

### Task 4: 验证、上线和受控恢复

- [ ] 运行 `supabase db reset && supabase test db`、Worker unittest discovery、控制面 test/lint/build、redaction 与 `git diff --check`。
- [ ] 先应用 migration，再部署同一 `main` 的 control plane，随后 reload launchd Worker。
- [ ] 以已认证管理员页创建一次 manual run，验证重复点击幂等、离线时仅排队、完整后新建 manual batch；记录现有落后来源的恢复结果。
- [ ] 提交工程记录，push `main`，并在稳定域完成管理员和 Reader 验收。
