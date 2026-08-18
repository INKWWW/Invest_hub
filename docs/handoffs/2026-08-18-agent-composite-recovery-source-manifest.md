# Agent Composite Recovery Source Manifest

Date: 2026-08-18
Candidate branch: `codex/agent-composite-recovery`
Plan source: `docs/superpowers/plans/2026-08-18-agent-composite-recovery.md`
Plan commit: `7b11be66651948a9c9086379554bae20f1a02b13`

## Execution boundary

Tasks 1–7 are authorized. Tasks 8–9 remain unauthorized. This manifest records read-only source and environment evidence; it does not authorize production writes, deployment, Worker restart, remote migration, or production test identities.

## Code and frozen sources

| Lane | Source | Evidence | Decision |
| --- | --- | --- | --- |
| Release/migration base | Git commit `9747f75` | Resolved as a commit and is an ancestor of the candidate HEAD | Use as the recovery base |
| Worker fixes | `c4930e3`, `4fad8af`, `06fa100` | All three resolve as commits | Port only the plan-scoped timeout/diagnostic semantics |
| Agent frontend | `/private/tmp/invest-hub-agent-deploy.N9J2MC` | All eight plan-pinned SHA-256 values match | Use only the hash-pinned Agent artifacts |
| Non-Agent registration source | `/private/tmp/invest-hub-invited-registration-ticket-01` | Source is dirty; inventory is recorded below | Port only the enumerated non-Agent files; exclude the release journal |
| Frozen Skill | `skills/upstream/d64751635308d1920bcdae234e6dd957fd79e736/` | To be verified again at Task 4 before execution | Preserve the complete bundle and provenance validation |

The verified frontend hashes are:

```text
d198d3af3433d0a593ac0519d4045adb9ffe444b21dd2b1ed78d4d89ac4b5bc1  apps/control-plane/src/app/globals.css
3bf90f8fbe2a620f76ab1743d0687cf3936715a228aeacad901bd53322f914b8  apps/control-plane/src/components/agent/ResearchAgentShell.tsx
086bbf5f94cef3ddec4adeee37c5671dd00ebc51bd85f6bc20ac27bc0d4f9836  apps/control-plane/src/components/agent/ResearchAgentShell.test.tsx
7ece4fc54192a64e206523e6df6ae03e1f45172a4e29dd11d3c4d0bf2dc065db  apps/control-plane/src/components/agent/SafeMarkdown.tsx
eaf10f4cbc21d9de57556aef4f9c5d3c5a8ce0c025c43df5414b0f0f74f9dcc6  apps/control-plane/src/lib/agent-demo/markdown.ts
8ebc15c4bb949c5eebb11ed6c79b6479684d3ce9dfce34df3bb82a2d4beb9f79  apps/control-plane/src/lib/agent-demo/markdown.test.ts
362d8751e494f951f19d1af533aeaa5e2296dad05f0486e49398e2cd12f1351f  apps/control-plane/src/components/reader/ReaderSourceNavigation.tsx
eb08f3c578c69f7dc02e388beda3ea8f44a48dd4ad7a2ed096f0d8fdc5191ac4  apps/control-plane/src/components/reader/reader-source-navigation.test.tsx
```

## Dirty registration source inventory

Feature logic: `apps/control-plane/src/app/(auth)/invite/page.tsx`, `apps/control-plane/src/app/(auth)/login/page.tsx`, `apps/control-plane/src/app/api/auth/invite/route.ts`, `apps/control-plane/src/lib/auth/invites.ts`, `apps/control-plane/src/lib/auth/password.ts`, and `apps/control-plane/src/lib/db/repositories/invites.ts`.

Focused tests and non-Agent regression repairs: `apps/control-plane/src/app/(auth)/invite/page.test.tsx`, `apps/control-plane/src/app/(auth)/login/page.test.tsx`, `apps/control-plane/src/app/api/api.integration.test.ts`, `apps/control-plane/src/lib/auth/current-user.test.ts`, `apps/control-plane/src/lib/auth/invites.test.ts`, `apps/control-plane/src/lib/auth/password.test.ts`, `apps/control-plane/src/components/admin/source-author-profiles-form.test.tsx`, `apps/control-plane/src/components/reader/x-reader-client.test.tsx`, and `apps/control-plane/src/components/reader/x-reader.test.tsx`.

Shared type/config: `apps/control-plane/src/lib/db/types.ts` and `supabase/config.toml`.

Forward-only migration and database test: `supabase/migrations/20260817090000_invited_user_registration_consistency.sql` and `supabase/tests/040_invited_user_registration_consistency.sql`.

Excluded release journal: `docs/engineering-journal/2026-08-17-invited-user-registration-demo-ticket-03-release-candidate.md`. No Agent component or Agent API file is copied from this source.

## Environment and rollback facts

| Surface | Read-only result on 2026-08-18 | Consequence |
| --- | --- | --- |
| Vercel project binding | No root `.vercel/project.json`; Vercel CLI is not installed in this environment | Current alias and immutable deployment cannot be independently identified here; do not claim a Preview or rollback target |
| Supabase project binding | `supabase migration list` reports no linked project; only local `project_id = "Invest_hub"` is present in `supabase/config.toml` | No remote migration comparison was performed; no link, pull, repair, push, or remote SQL is allowed in Tasks 1–7 |
| Local Supabase | `supabase status` could not inspect Docker because the Docker socket is not available to this sandbox | Task 6 must use an authorized environment with local Supabase access, or stop and record the exact gate failure |
| Production Worker | Read-only `launchctl list` exposed no `com.investhub.x-worker` entry in this environment | No Worker operation was attempted; absence here is not evidence about production state |

Historical deployment IDs and aliases in older project documents are not treated as current rollback truth. A Vercel rollback changes only the web deployment; it cannot restore Supabase schema/data or the standalone Worker.

## Scope guard

No Agent-Reach, Jina Reader, Exa, Codex native Web Search, or new search adapter is included. No production migration, production data write, Auth modification, Vercel deployment, stable-alias change, Worker install/restart, Git push, merge, or tag was performed while collecting this manifest.
