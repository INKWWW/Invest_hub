# Investment Research Agent Demo Implementation Plan

> **For agentic workers:** This execution note is derived from the approved Matt Feature Contract and six-ticket Delivery Plan at `.scratch/investment-research-agent-demo/`. The Matt ticket graph remains the authority; this file only records the local execution checkpoints.

**Goal:** Deliver the smallest locally testable `/agent` chat path with persisted Markdown, three isolated Skill routes, one global admission slot, owner-bound access, and a deterministic release package.

**Architecture:** Keep the existing authenticated Research Thread tables and page shell, and add a separate `agent_demo_runs` seam so the Demo does not depend on legacy Quota, Trace, Memory, Artifact, or recovery machinery. Control Plane owns authenticated admission and read APIs; the Worker owns the scripted/real-provider-neutral execution boundary and returns only sanitized terminal data. Skill execution uses a pinned read-only bundle and an owner-only temporary Run directory.

**Tech Stack:** Next.js/React/TypeScript Control Plane, Supabase SQL/RLS/RPC, Python 3.11 Worker, Vitest, unittest, pgTAP.

## Global Constraints

- Implement only the approved six tickets in dependency order: `01 → (02, 03, 05) → 04 → 06`.
- Do not add Quota, Memory, Trace management, streaming, uploads, holdings database, cloud fallback, multi-Skill orchestration, automatic retry, cancellation, deployment, remote migration, Runner installation/restart, or real Codex execution.
- General-chat product instructions apply only to general Q&A; Skill execution loads only its frozen Skill instruction and explicit resources.
- Every accepted trimmed non-empty message up to 20,000 characters reaches the LLM boundary; no keyword, asset, or semantic pre-classifier is allowed.
- Keep user text, prompts, Codex JSONL, credentials, local paths, stderr, and real fixtures out of persisted user-facing evidence.

## Execution Checkpoints

### Ticket 01 — Vertical slice

Files: add one additive Demo migration and pgTAP contract, Control Plane Demo run repository/API seam, Worker Demo runtime/provider adapter and scripted fixtures, and focused page/API tests. First prove one representative browser/API/database/Worker scripted path, then add the remaining deterministic checks.

Verification: focused pgTAP, Control Plane Vitest, Worker unittest, and a local HTTP seam script; confirm exactly one user message, one Demo Run, and one persisted assistant message without reading Quota.

### Tickets 02, 03, and 05 — Independent bounded seams

Ticket 02 adds ordered Thread context, versioned general-chat instructions, post-provider source/advice validation, safe Markdown projection, and the no-prefilter boundary. Ticket 03 adds the three-button/command registry, explicit-vs-auto routing metadata, one-Skill validation, and composer reset. Ticket 05 adds atomic global admission, worker freshness rejection, request identity, busy/offline messages, and owner-bound guessed-ID tests. Each ticket changes disjoint primary files and runs its own focused red-green regression before integration.

### Ticket 04 — Isolated Skill runtime

Add the pinned public Skill bundle and provenance, runtime allowlist, temporary-directory guard, report extraction, portfolio missing-input clarification, and complete output-tree/symlink/path traversal tests. Do not add general-chat product instructions to Skill prompts.

### Ticket 06 — Local acceptance

Run the representative chain first, then the approved matrix across Control Plane, Worker, Supabase, page, Markdown, routing, isolation, admission, and RLS boundaries. Produce a sanitized local release package with commit/test results and explicit unexecuted release actions. Separate pre-existing failures from Feature failures.

## Stop Conditions

- If implementation needs to alter the Feature Contract, ticket graph, frozen Skill commit, or blocking edge, stop and restore the affected approvals before continuing.
- If the first automated feedback loop fails, use `diagnosing-bugs` to establish a red-capable reproduction and allow only one root-cause repair round.
- Stop before any real Codex call, remote Supabase write, deployment, Runner installation/restart, or production acceptance.
