# X 当日判断总结最终审查修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Plan status:** **已批准（用户确认 2026-08-01 并要求执行）**。本 Plan 仅授权本地代码、migration、测试与治理记录修复；remote migration、部署、Worker 重启、真实 X/OpenCLI/Browser/Codex 调用和生产验收仍须另行明确授权。

**Goal:** 闭合最终整分支审查确认的 Worker 授权、无新增 regeneration、opaque ID、共识语义、可观测性与治理真值缺口。

**Architecture:** 数据库、HTTP 与 Worker parser 继续是同一 judgement authority 的三道防线；无输入批次不进入 Provider；所有模型上下文身份在展示文本中禁用。运行日志只增加安全 boolean，治理文件补齐用户已批准的 regeneration Plan，不执行任何生产动作。

**Tech Stack:** Supabase SQL/pgTAP、Next.js/Vitest、Python unittest、现有 V2 runner。

## Global Constraints

- judgement ensure/claim 只接受 `online`、具有 `x_sync` capability 且获 X 来源授权的 Worker；拒绝 enrolled 与 stale heartbeat。
- `no_new_information` batch 绝不调用 Provider 或产生将 coverage 改为 complete/partial 的 regeneration version。
- Worker/HTTP/DB 都拒绝 batch/run/segment/source/analysis/evidence 任一 opaque ID 出现在 statement 或顶层/条目 uncertainty。
- 强共识措辞至少两位独立 supporting sources，且没有 dissenting sources；不得依赖 Prompt 作为唯一防线。
- 不改变 source task、coverage、checkpoint、不可变旧 version，不执行远端、部署、重启或真实调用。

---

### Task 1: Final judgement authority hardening

**Files:**
- Create: `supabase/migrations/20260801170000_x_daily_judgement_final_authority.sql`
- Create: `supabase/tests/029_v2_x_daily_judgement_final_authority.sql`
- Modify: `apps/control-plane/src/app/api/worker/x-daily-judgements/[runId]/complete/route.ts` and tests
- Modify: `workers/v0/src/invest_hub_worker/{runtime,structured}.py`
- Modify: `workers/v0/prompts/v2_x_cross_blogger.md`
- Modify: `workers/v0/tests/test_x_cross_blogger_judgements.py`

- [ ] Write RED tests for enrolled/stale Worker rejection; no-new regeneration rejection/provider-not-called/coverage unchanged; batch/run/segment opaque tokens in every natural-language field; and single-source/dissenting strong-consensus rejection at DB/HTTP/Worker.
- [ ] Implement only the final authorities: online + heartbeat eligibility; reject no-new regeneration before queueing; add all context-exposed IDs to opaque sets; enforce consensus phrase threshold in prompt and three deterministic validators.
- [ ] Run clean DB reset/pgTAP, focused Node/Worker tests, lint/diff; commit `fix(v2): harden final X judgement authority`.

### Task 2: Observability, governance and final evidence

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/cli.py` and CLI tests
- Modify: `docs/project-status.md`
- Modify: `docs/engineering-journal/2026-08-01-x-cross-blogger-daily-judgements.md`
- Modify: `scripts/v2/run-v2-e2e.sh` only if new real tests require inclusion

- [ ] Add RED/Green CLI test proving safe `judgement_dispatch_failed` telemetry survives schedule output without details.
- [ ] Add regeneration Plan to approved/status/journal chain; update exact local test counts and preserve default Turbopack build failure/production-not-executed truth.
- [ ] Run local DB/Worker/V2 runner/control-plane/lint/default build/Webpack/redact/diff gates; commit `test(v2): record final judgement authority evidence`.

## Plan self-review

Task 1 covers every P1 from final review at all final authorities. Task 2 covers its two P2s and truthful evidence. No production action, new collector or provider is introduced.
