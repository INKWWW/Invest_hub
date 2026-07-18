# Spike-02 Media Source Linkage Implementation Plan

> For the implementation agent: REQUIRED SUB-SKILL: use `superpowers:test-driven-development` for every code task, and `superpowers:verification-before-completion` before reporting completion.

**Goal:** Make every unparsed-media input message explicitly traceable in the structured output, so the existing quality evaluator can distinguish “media was safely left unparsed” from “media was omitted from the result.”

**Approach:** Add `media_source_message_ids` to the output contract, validate it against the current chunk deterministically, ask Codex CLI to populate it, and let evaluation use the field for the media claim. Keep the change local to Spike-02; do not change providers, concurrency, chunk size, or media parsing.

**Worktree:** `/Users/hanyuec/Desktop/Invest_hub/.worktrees/spike-02-implementation`

**Specification:** `docs/superpowers/specs/2026-07-18-spike-02-media-source-linkage-design.md`

## Task 1: Lock the output contract in model and schema tests

**Files:**

- Modify: `spikes/spike_02/model.py`
- Modify: `spikes/spike_02/schema.py`
- Modify: `spikes/spike_02/tests/test_schema.py`

1. Extend the test helper JSON with `"media_source_message_ids": []`.
2. Add failing tests for the new contract:
   - missing top-level `media_source_message_ids` is rejected;
   - a media result must cite every unparsed-media input ID;
   - a cited ID must belong to the current input and be `unparsed_media`;
   - a non-media input ID is rejected;
   - a complete media citation is accepted.
3. Run the focused schema tests and confirm they fail for the missing field/behavior.
4. Add `media_source_message_ids: tuple[str, ...]` to `StructuredOutput`.
5. Parse the required string array in `parse_structured_output`.
6. Extend `validate_structured_output` with the current chunk’s unparsed-media ID set and enforce the specification’s exact-set rules.
7. Run the focused schema tests and confirm they pass.

## Task 2: Update prompt and offline response fixtures

**Files:**

- Modify: `spikes/spike_02/chunking.py`
- Modify: `spikes/spike_02/cli.py`
- Modify: `spikes/spike_02/providers.py` only if its fixture contract requires it
- Modify: `spikes/spike_02/tests/test_cli.py`
- Modify: `spikes/spike_02/tests/test_runner.py`
- Modify: `spikes/spike_02/tests/test_providers.py`

1. Update the prompt test to require `media_source_message_ids` and the instruction to cite every `unparsed_media` message.
2. Run the focused prompt/CLI tests and confirm the prompt assertion fails before implementation.
3. Change the prompt’s exact JSON shape and media instruction without changing any other task instruction.
4. Update `VALID_JSON` and fake Codex output fixtures to include the new field with `[]`.
5. Run CLI, runner, provider, and prompt tests.

## Task 3: Pass media IDs from runner into deterministic validation

**Files:**

- Modify: `spikes/spike_02/runner.py`
- Modify: `spikes/spike_02/tests/test_runner.py`

1. Add a runner test using a chunk containing `public-008` and an invalid response that omits or mis-cites its media source; assert it follows the existing schema-error/retry path.
2. Run the focused runner test and confirm it fails before the integration change.
3. Compute the unparsed-media IDs from the chunk input messages, including any context messages that are part of the request.
4. Pass those IDs into `validate_structured_output`.
5. Keep retry counts, chunk ordering, evidence writing, and split behavior unchanged.
6. Run all runner tests and confirm they pass.

## Task 4: Make evaluation recognize explicit media grounding

**Files:**

- Modify: `spikes/spike_02/evaluation.py`
- Modify: `spikes/spike_02/tests/test_evaluation.py`

1. Add a focused test with `media_unparsed=True`, warning text stating the media is unparsed, and `media_source_message_ids=("public-008",)`; assert the media claim is covered and grounded with zero media hallucinations.
2. Run the focused evaluation test and confirm it fails before implementation.
3. Treat the media metadata/warnings plus their explicit source IDs as one auxiliary evaluable result for the media claim.
4. Preserve topic-based attribution and the existing forbidden-term media hallucination check.
5. Run all evaluation tests and confirm they pass.

## Task 5: Run deterministic verification and fresh quality validation

**Files:**

- Modify: `spikes/spike_02/README.md` if the output contract is documented there
- Modify: `docs/project-status.md` only after fresh verification evidence is available
- Modify: `docs/engineering-journal/2026-07-15-spike-02.md` only after fresh verification evidence is available

1. Run the complete deterministic test suite for Spike-02.
2. Run the mock CLI smoke test and inspect generated metrics/evidence for the new field’s compatibility.
3. Run one fresh Codex CLI quality validation against public `public_small.json` using the existing approved harness and evidence directory convention.
4. Inspect the raw structured output and confirm `public-008` appears in `media_source_message_ids`; generate/update the review sheet and run the evaluator.
5. Accept the quality boundary only if the fresh run meets the Spec target: 6/6 coverage, 6/6 grounding, severe attribution 0, media hallucination 0. If the model fails the new contract after retries, record that as an honest validation failure rather than auto-repairing the result.
6. Update project status and the engineering journal with the result, remaining limitations, and evidence path.
7. Review `git diff`, worktree status, and the complete test/quality outputs.
8. Commit the implementation and documentation changes on `spike-02-implementation`; do not merge into main.

## Verification commands

Run from `/Users/hanyuec/Desktop/Invest_hub/.worktrees/spike-02-implementation`:

```bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_02/tests -v
PYTHONPATH=spikes python3 -m spike_02.cli mock \
  --fixture spikes/spike_02/fixtures/public_small.json \
  --evidence-dir /private/tmp/invest-hub-spike-02-evidence/media-linkage-mock \
  --chunk-size 3
```

The fresh Codex CLI command should reuse the already configured local Codex CLI harness and use a new evidence directory. Do not add credentials, private fixtures, or generated evidence to Git.
