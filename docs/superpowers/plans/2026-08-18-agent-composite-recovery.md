# Agent Composite Recovery Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task. Use `superpowers:test-driven-development` for code changes and `superpowers:verification-before-completion` before claiming a gate has passed.

**Goal:** Produce a clean, reproducible Agent recovery candidate that matches the approved 2026-08-17 Agent UI, restores the approved Agent Worker/API behavior, preserves the currently released invitation, X, and Discord functionality, and stops at a user-testable webpage without changing production.

**Architecture:** Use commit `9747f75` as the release and migration baseline, explicitly layer the missing answer-preservation/provider-diagnostic fixes from `c4930e3`, `4fad8af`, and `06fa100`, restore the exact frontend artifact from `/private/tmp/invest-hub-agent-deploy.N9J2MC`, and overlay only the non-Agent registration changes from `/private/tmp/invest-hub-invited-registration-ticket-01`. Resolve shared files deliberately and add the smallest DTO compatibility layer required by the frontend. Database history is forward-only.

**Tech Stack:** Next.js 16, React 19, TypeScript, Vitest, Supabase/Postgres/pgTAP, Python 3.11, Codex CLI Agent Worker, Vercel Preview/Promote.

---

## Authorization and non-negotiable boundaries

The user has authorized Tasks 1-7 only. Those tasks end with an isolated test webpage and acceptance checklist. Tasks 8-9 are documented for continuity but are not authorized until the user explicitly says `符合预期，可以上线`.

- Start from the committed `codex/agent-composite-recovery` plan branch and work only in the explicit task's assigned isolated worktree. Do not edit, clean, reset, stage, or deploy from the dirty main checkout or another feature worktree.
- Do not push, merge, tag, promote a Vercel deployment, move the stable alias, apply or reverse a remote migration, change production Supabase Auth, install/restart a production Worker, create production test identities, or write production data during Tasks 1-7.
- Do not add Agent-Reach, Jina Reader, Exa, Codex native Web Search, or any other web-search path. The relevant experiments were Spikes, not an approved production integration.
- Do not delete or reverse any production migration. Treat `20260817090000_invited_user_registration_consistency.sql` and the already-applied RPC/Auth configuration as forward-compatible state to preserve.
- Never expose prompts, credentials, cookies, raw Provider stdout/stderr, private paths, test identities, full invite codes, or production data in logs or handoffs.
- A generic `vercel rollback` is not an acceptable formal recovery. The immediately preceding deployment `ca907bb` had already begun the UI regression. An emergency rollback must target a specifically identified immutable deployment and still would not roll back Supabase or the standalone Worker.

## Frozen sources and acceptance truth

| Lane | Frozen source | Required truth |
| --- | --- | --- |
| Release/migration base | `9747f75 fix(agent): finalize production demo release` | Agent API, Run admission, capability isolation, quotas/RLS, X rebaseline, and baseline migrations |
| Missing Worker fixes | `c4930e3`, `4fad8af`, `06fa100` | Preserve a completed answer across CLI timeout; safely capture and classify diagnostics without leaking raw stderr |
| Agent frontend | `/private/tmp/invest-hub-agent-deploy.N9J2MC` | Exact 1200px workbench, internal message scrolling, Skill interaction, message rendering, titles, and run state |
| Current non-Agent release | `/private/tmp/invest-hub-invited-registration-ticket-01` | Invitation registration, login/password behavior, X and Discord behavior, and forward migration set |
| Visual baseline | `/var/folders/9j/fbk2z63937zb_bxfmlw4yplw0000gn/T/codex-clipboard-567d0f65-dab1-4fbe-b620-e36203cd3d86.png` | Same desktop layout, typography, colors, two-column geometry, controls, Skill row, and composer at the same viewport |

Frontend artifact hashes must equal:

- `apps/control-plane/src/app/globals.css`: `d198d3af3433d0a593ac0519d4045adb9ffe444b21dd2b1ed78d4d89ac4b5bc1`
- `apps/control-plane/src/components/agent/ResearchAgentShell.tsx`: `3bf90f8fbe2a620f76ab1743d0687cf3936715a228aeacad901bd53322f914b8`
- `apps/control-plane/src/components/agent/ResearchAgentShell.test.tsx`: `086bbf5f94cef3ddec4adeee37c5671dd00ebc51bd85f6bc20ac27bc0d4f9836`

The screenshot is a static visual contract, not a requirement to fake runtime state. Account name, thread titles, messages, selected Skill, and input text may differ. `Agent 暂时不可用` must appear only when the Worker is actually unavailable; it must not be hard-coded into the healthy candidate.

### Task 1: Freeze the source manifest and rollback evidence

**Files:**
- Create: `docs/handoffs/2026-08-18-agent-composite-recovery-source-manifest.md`
- Verify: `.vercel/project.json`
- Verify: `supabase/migrations/*`

- [ ] **Step 1: Assert the clean execution base**

Run:

```bash
git status --short --branch
git branch --show-current
git rev-parse HEAD
git merge-base --is-ancestor 9747f75 HEAD
```

Expected: the task started from the plan commit on `codex/agent-composite-recovery`, its isolated branch/base includes `9747f75`, and no unexpected file is modified. Stop if any assertion fails.

- [ ] **Step 2: Verify all frozen sources before copying anything**

Run exact existence and SHA-256 checks for the frontend artifact, `git cat-file -e` for all four commits, and `git status --short` in the registration source. Record the registration source as dirty and inventory every file; never treat it as a reproducible commit.

- [ ] **Step 3: Capture read-only production rollback facts**

Using the Vercel deployment inspection tooling and Supabase read-only migration/config tooling, record:

- current stable alias and immutable Deployment ID;
- registration deployment `dpl_3QAMAUu1CDeyfurKTGQWj392CXYH` if it remains current;
- the exact 15:17 approved UI deployment if it is still retained;
- immediately preceding deployment and source metadata;
- production migration names and Auth settings relevant to signup/login;
- standalone Agent Worker installation/status without restarting it.

If Vercel inspection returns 403, record the connector failure and use authenticated read-only CLI inspection. If no method can identify the current rollback target, stop before any Preview or release action.

- [ ] **Step 4: Write and commit the manifest**

The manifest must distinguish code, Vercel alias, Supabase schema/config, and Worker state. It must state that a Vercel rollback changes only the web deployment and cannot restore Supabase or Worker state.

```bash
git add docs/handoffs/2026-08-18-agent-composite-recovery-source-manifest.md
git commit -m "docs: freeze agent recovery sources"
```

### Task 2: Restore the approved Worker timeout and diagnostic semantics

**Files:**
- Modify: `workers/v0/src/invest_hub_worker/agent_demo.py`
- Modify: `workers/v0/src/invest_hub_worker/cli.py`
- Modify: `workers/v0/tests/test_agent_demo.py`
- Modify: `workers/v0/tests/test_cli.py`

- [ ] **Step 1: Add failing tests for the missing behavior**

Tests must prove:

- the default CLI execution timeout is 360 seconds at both the CLI and provider boundary;
- a final answer already written by Codex is returned even when the process later reaches the timeout boundary;
- stale answer/diagnostic files are cleared before a run;
- diagnostics are stored with mode `0600` and reduced to safe classifications;
- raw stderr, prompts, secrets, and local paths never enter the user-visible failure envelope.

Run:

```bash
PYTHONPATH=workers/v0/src .venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_agent_demo.py' -v
PYTHONPATH=workers/v0/src .venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_cli.py' -v
```

Expected: new assertions fail against the `9747f75` baseline for the intended reasons.

- [ ] **Step 2: Reconcile the three backend commits**

Port the semantics of `c4930e3`, `4fad8af`, and `06fa100`. Do not blindly cherry-pick conflict markers or unrelated documentation. Do not change Run admission, quota, RLS, task claiming, Skill capability guards, X, or Discord provider semantics.

- [ ] **Step 3: Run focused and full Worker tests**

```bash
PYTHONPATH=workers/v0/src .venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_agent_demo.py' -v
PYTHONPATH=workers/v0/src .venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_cli.py' -v
PYTHONPATH=workers/v0/src .venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
```

Expected: all pass with no raw Provider output printed.

- [ ] **Step 4: Commit only the Worker repair**

```bash
git add workers/v0/src/invest_hub_worker/agent_demo.py workers/v0/src/invest_hub_worker/cli.py workers/v0/tests/test_agent_demo.py workers/v0/tests/test_cli.py
git commit -m "fix(agent): restore timeout answer preservation"
```

### Task 3: Restore the exact approved Agent frontend

**Files:**
- Modify: `apps/control-plane/src/app/globals.css`
- Modify: `apps/control-plane/src/app/globals.test.ts`
- Modify: `apps/control-plane/src/components/agent/ResearchAgentShell.tsx`
- Modify: `apps/control-plane/src/components/agent/ResearchAgentShell.test.tsx`
- Verify/Modify if required by the frozen artifact: `apps/control-plane/src/components/agent/SafeMarkdown.tsx`

- [ ] **Step 1: Strengthen failing UI contract tests before replacement**

Tests must assert the 1200px desktop height, mobile viewport cap, `minmax(0, 1fr)`, internal message scrolling, absence of visible `研究额度` and `发送纯文本消息`, presence of the four Skill controls, selected `/Skill` token, run-status rendering, and `点击发送（回车仅换行）`.

```bash
cd apps/control-plane && ./node_modules/.bin/vitest run src/app/globals.test.ts src/components/agent/ResearchAgentShell.test.tsx
```

Expected: at least the new 1200px/static contract assertions fail before restoration.

- [ ] **Step 2: Restore from the hash-pinned frontend artifact**

Copy the exact target component/test/CSS content, then merge rather than overwrite non-Agent CSS added by registration. The Agent selectors and declarations must remain semantically identical to the frozen artifact. Do not add screenshot-specific fake data or special-case the current user.

- [ ] **Step 3: Pass focused UI tests**

Run the same Vitest command. Expected: pass.

- [ ] **Step 4: Commit the frontend restoration**

```bash
git add apps/control-plane/src/app/globals.css apps/control-plane/src/app/globals.test.ts apps/control-plane/src/components/agent/ResearchAgentShell.tsx apps/control-plane/src/components/agent/ResearchAgentShell.test.tsx apps/control-plane/src/components/agent/SafeMarkdown.tsx
git commit -m "fix(agent): restore approved research workspace ui"
```

### Task 4: Add only the frontend/backend compatibility contract

**Files:**
- Modify: `apps/control-plane/src/lib/db/repositories/research-threads.ts`
- Modify: `apps/control-plane/src/app/api/agent/threads/[threadId]/route.ts`
- Modify: `apps/control-plane/src/app/api/agent/threads/[threadId]/route.test.ts`
- Modify or create focused repository test beside `research-threads.ts`
- Verify: `apps/control-plane/src/lib/db/repositories/agent-demo-runs.ts`
- Verify: `apps/control-plane/src/app/api/agent/runs/[runId]/route.ts`

- [ ] **Step 1: Add failing DTO/repository tests**

Prove that thread detail returns `skill_id` on the associated user message and preserves message order/title behavior. Prove the run detail continues to expose `skill_id`, `created_at`, `started_at`, and `completed_at`.

- [ ] **Step 2: Implement the minimal mapping**

Add `skillId` to `ResearchMessage`, query `agent_demo_runs` by `user_message_id`, map Skill metadata to the corresponding user message, and serialize it as `skill_id`. Do not change Worker execution, admission, quota, task claiming, or Provider behavior.

- [ ] **Step 3: Run focused API, repository, and component tests**

```bash
cd apps/control-plane && ./node_modules/.bin/vitest run 'src/app/api/agent/threads/[threadId]/route.test.ts' src/components/agent/ResearchAgentShell.test.tsx
```

Expected: pass.

- [ ] **Step 4: Commit the compatibility layer**

```bash
git add apps/control-plane/src/lib/db/repositories/research-threads.ts 'apps/control-plane/src/app/api/agent/threads/[threadId]/route.ts' 'apps/control-plane/src/app/api/agent/threads/[threadId]/route.test.ts'
git add apps/control-plane/src/lib/db/repositories/*research*test*
git commit -m "fix(agent): restore thread skill metadata contract"
```

### Task 5: Preserve the released invitation and non-Agent functionality

**Files:**
- Modify: `apps/control-plane/src/app/(auth)/invite/page.tsx`
- Create: `apps/control-plane/src/app/(auth)/invite/page.test.tsx`
- Modify: `apps/control-plane/src/app/(auth)/login/page.tsx`
- Create: `apps/control-plane/src/app/(auth)/login/page.test.tsx`
- Modify: `apps/control-plane/src/app/api/api.integration.test.ts`
- Modify: `apps/control-plane/src/app/api/auth/invite/route.ts`
- Modify: `apps/control-plane/src/lib/auth/invites.ts`
- Modify: `apps/control-plane/src/lib/auth/invites.test.ts`
- Create: `apps/control-plane/src/lib/auth/current-user.test.ts`
- Create: `apps/control-plane/src/lib/auth/password.ts`
- Create: `apps/control-plane/src/lib/auth/password.test.ts`
- Modify: `apps/control-plane/src/lib/db/repositories/invites.ts`
- Modify: `apps/control-plane/src/lib/db/types.ts`
- Modify: `supabase/config.toml`
- Create: `supabase/migrations/20260817090000_invited_user_registration_consistency.sql`
- Create: `supabase/tests/040_invited_user_registration_consistency.sql`
- Modify only for existing type-test compatibility: the three registration-source reader/admin test files listed in the source manifest

- [ ] **Step 1: Inventory and classify the dirty registration diff**

For every source file, record whether it is feature logic, test-only baseline repair, shared CSS/type/config, migration, or release journal. Do not copy the release journal as product truth. Do not copy Agent component/API files from this source.

- [ ] **Step 2: Add/carry focused tests before feature files**

Bring over the exact registration tests and confirm they fail because the feature is absent. Preserve public signup disabled, email login enabled, four-field Chinese form, password rule/confirmation, invite consumption, Profile consistency, automatic login to `/agent`, and uniform failure envelopes.

- [ ] **Step 3: Port the smallest released registration implementation**

Resolve `globals.css`, `api.integration.test.ts`, and `db/types.ts` manually. The Agent UI contract from Task 3 wins for Agent selectors; registration classes and schema types must remain. Preserve existing X and Discord implementation from the release base.

- [ ] **Step 4: Run focused registration/non-Agent tests**

```bash
cd apps/control-plane && ./node_modules/.bin/vitest run 'src/app/(auth)/invite/page.test.tsx' 'src/app/(auth)/login/page.test.tsx' src/lib/auth/current-user.test.ts src/lib/auth/invites.test.ts src/lib/auth/password.test.ts src/app/api/api.integration.test.ts src/components/admin/source-author-profiles-form.test.tsx src/components/reader/x-reader-client.test.tsx src/components/reader/x-reader.test.tsx
```

Expected: pass.

- [ ] **Step 5: Commit the preserved non-Agent release**

Stage only the files enumerated by the source manifest and inspect `git diff --cached --stat` before committing.

```bash
git commit -m "feat(auth): preserve invited registration demo"
```

### Task 6: Prove forward-only database compatibility

**Files:**
- Verify: `supabase/migrations/*`
- Verify: `supabase/tests/001_v0_rls.sql`
- Verify: `supabase/tests/021_user_invite_duration_and_mask.sql`
- Verify: `supabase/tests/038_agent_research_threads.sql`
- Verify: `supabase/tests/039_agent_research_quota.sql`
- Verify: `supabase/tests/040_invited_user_registration_consistency.sql`
- Verify: `supabase/tests/054_agent_demo_vertical_slice.sql`
- Verify: `supabase/tests/055_agent_demo_admission_isolation.sql`
- Verify: `supabase/tests/056_agent_demo_skill_metadata.sql`

- [ ] **Step 1: Rebuild the local database from zero**

Discover CLI syntax with `supabase db reset --help`, then run:

```bash
supabase db reset
supabase test db
```

Expected: all migrations apply in filename order and all pgTAP files pass.

- [ ] **Step 2: Compare local and production migration names read-only**

No `migration repair`, remote `db push`, `db pull`, branch merge/reset, or direct DDL is allowed. If production contains a migration missing locally, or local history would require a downgrade/rewrite, stop and report the exact drift.

- [ ] **Step 3: Run Supabase security checks relevant to the RPC/RLS**

Confirm the registration RPC is not executable by `anon`/`authenticated`, Agent tables retain ownership RLS, and no service-role key is present in client code or the diff.

### Task 7: Full verification and isolated test webpage

**Files:**
- Create: `docs/handoffs/2026-08-18-agent-composite-recovery-preview.md`
- Verify: all changed files

- [ ] **Step 1: Run the complete local gate from the clean candidate**

```bash
cd apps/control-plane && ./node_modules/.bin/vitest run
cd apps/control-plane && ./node_modules/.bin/tsc --noEmit
cd apps/control-plane && ./node_modules/.bin/eslint .
cd apps/control-plane && ./node_modules/.bin/next build
PYTHONPATH=workers/v0/src .venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v
supabase test db
bash scripts/v0/redact-check.sh
git diff --check
git status --short --branch
```

Expected: every command passes; only intentional committed files exist; no secret or unrelated diff appears.

- [ ] **Step 2: Start an isolated full-stack candidate**

Use local Supabase, the candidate Control Plane, the candidate Agent Worker, synthetic invites, and disposable local identities. Do not point a public Preview at production Supabase. If a safe isolated public Preview cannot be created, deliver a localhost test URL and keep the services running for user acceptance.

- [ ] **Step 3: Run functional and visual browser verification**

At the screenshot viewport (approximately 1204x1280), capture a candidate screenshot and compare:

- header/navigation, typography, colors, borders, two-column geometry, sidebar controls, four Skill buttons, tokenized composer, and send button match the approved baseline;
- `.agent-workbench` is 1200px on desktop and messages scroll internally;
- `研究额度` and `发送纯文本消息` are absent;
- healthy Worker state does not show `Agent 暂时不可用`;
- deliberately stopped isolated Worker does show the unavailable state, then recovery clears it;
- intelligent chat and one Skill chat complete; refresh preserves messages, title, Skill metadata, and run status;
- a timeout after answer creation preserves the answer;
- invitation login/registration, X Reader, and Discord routes still render and their focused tests remain green;
- mobile height uses `min(1200px, calc(100dvh - 9rem))` without making this the previously deferred full 375px release gate.

- [ ] **Step 4: Write the preview handoff and stop**

The handoff must include candidate commit SHA, local/Preview URL, process start/stop commands, test-data scope, screenshot path, command results, known limitations, and exact production actions that were not performed. Commit it, then stop and wait for the user's visual acceptance.

```bash
git add docs/handoffs/2026-08-18-agent-composite-recovery-preview.md
git commit -m "docs: record agent recovery preview"
```

Do not enter Task 8 without the exact user authorization `符合预期，可以上线` or an equally explicit statement.

### Task 8: Promote the accepted immutable candidate (NOT YET AUTHORIZED)

- [ ] Re-run the complete gate on the exact accepted clean commit.
- [ ] Build one immutable Vercel candidate and record its Deployment ID and source SHA.
- [ ] Apply only missing additive migrations after a read-only migration comparison; never downgrade the database.
- [ ] Install/update the Agent Worker from the same source SHA and record its executable/config hash.
- [ ] Promote the already-tested Vercel artifact to the stable alias; do not rebuild from another directory.
- [ ] Run bounded production smoke tests. On failure, repoint the alias to the recorded previous Deployment and restore the previous Worker artifact/config; do not reverse database history or delete production identities automatically.

### Task 9: Complete release governance (NOT YET AUTHORIZED)

- [ ] Create the final release commit/tag and push only after production acceptance.
- [ ] Record frontend source hashes, backend commits, Worker hash, migration set, Vercel Deployment ID, rollback targets, and production acceptance evidence.
- [ ] Update `docs/project-status.md` and the release journal so one clean commit is the only production source.
- [ ] Document and enforce: clean commit → Preview → automated gates → human acceptance → Promote the same artifact. Feature worktrees may never directly claim the stable alias.
