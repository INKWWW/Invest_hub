from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from invest_hub_worker.canonical import Canonicalizer
from invest_hub_worker.config import LocalWorkerConfigSet
from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.evidence import LocalEvidenceStore
from invest_hub_worker.protocol import DeviceCredential, WorkerProtocol
from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
from invest_hub_worker.retry import RetryPolicy
from invest_hub_worker.runtime import XWindowedRuntime
from invest_hub_worker.sequential import run_sequential_x_fixed_window
from invest_hub_worker.worker import Worker


DEMO_RUN_ID = "11111111-1111-4111-8111-111111111111"
JUDGEMENT_RUN_ID = "22222222-2222-4222-8222-222222222222"
TASK_ID = "33333333-3333-4333-8333-333333333333"
SOURCE_ID = "44444444-4444-4444-8444-444444444444"
CUTOFF = "2026-08-18T16:00:00+08:00"


def _task_claim() -> dict[str, object]:
    return {
        "contract_version": "v0",
        "task_id": TASK_ID,
        "attempt": 1,
        "task_type": "x_sync",
        "source_id": SOURCE_ID,
        "parameter_version": "x-standard-v2",
        "lease_expires_at": "2099-01-01T00:10:00Z",
        "safe_checkpoint": None,
        "collection_scope": {"mode": "incremental", "max_pages": 1},
        "source_snapshot": {
            "source_type": "x",
            "account_id": "fixture-account",
            "display_name": "Synthetic source",
            "parameter_version": "x-standard-v2",
        },
    }


class _ProductionShapeTransport:
    def __init__(self, *, judgement_failure_mode: bool = False) -> None:
        self.task_claimed = False
        self.judgement_claimed = False
        self.judgement_failure_mode = judgement_failure_mode
        self.judgement_attempt = 0
        self.claimed_judgement_id: str | None = None
        self.provider_calls = 0
        self.judgement_failure_calls: list[tuple[str, int, str]] = []
        self.terminalization_calls: list[tuple[str, str]] = []
        self.judgement_status = "queued"

    def __call__(self, method: str, url: str, body: object | None, headers: dict[str, str], timeout: float) -> tuple[int, object | None]:
        del method, headers, timeout
        action = body.get("action") if isinstance(body, dict) else None
        if url.endswith("/api/worker/heartbeat"):
            return 200, {"status": "online"}
        if url.endswith("/api/worker/x-fixed-windows/run"):
            if action == "start":
                return 200, {
                    "run_id": DEMO_RUN_ID,
                    "status": "running",
                    "idempotent": False,
                    "cutoff_at": CUTOFF,
                    "sources": [{
                        "source_id": SOURCE_ID,
                        "display_name": "Synthetic source",
                        "resolution_status": "resolved",
                        "account_id": "fixture-account",
                    }],
                }
            if action == "bind_task":
                return 200, {"status": "attached", "run_id": DEMO_RUN_ID, "source_id": SOURCE_ID, "task_id": TASK_ID}
            if action == "create_task":
                return 200, {"id": TASK_ID, "source_id": SOURCE_ID, "idempotent": False, "demo_fixed_window": {}}
            if action == "settle":
                return 200, {"status": "judgement_pending", "coverage_status": "partial", "run_id": DEMO_RUN_ID}
            if action == "judgement_failure":
                self.terminalization_calls.append((str(body["run_id"]), str(body["judgement_run_id"])))
                return 200, {
                    "status": "failed", "demo_run_id": DEMO_RUN_ID,
                    "judgement_run_id": JUDGEMENT_RUN_ID, "idempotent": False,
                }
            if action == "claim_judgement":
                if self.judgement_failure_mode:
                    if self.judgement_attempt >= 2:
                        return 204, None
                    self.judgement_attempt += 1
                    self.claimed_judgement_id = JUDGEMENT_RUN_ID
                    self.judgement_status = "leased"
                    return 200, {
                        "run_id": JUDGEMENT_RUN_ID,
                        "attempt": self.judgement_attempt,
                        "lease_expires_at": "2099-01-01T00:10:00Z",
                        "batch": {
                            "id": "55555555-5555-4555-8555-555555555555",
                            "natural_date": "2026-08-18",
                            "cutoff_at": CUTOFF,
                            "coverage_status": "partial",
                        },
                    }
                if self.judgement_claimed:
                    return 204, None
                self.judgement_claimed = True
                self.claimed_judgement_id = JUDGEMENT_RUN_ID
                self.judgement_status = "leased"
                return 200, {
                    "run_id": JUDGEMENT_RUN_ID,
                    "attempt": 1,
                    "lease_expires_at": "2099-01-01T00:10:00Z",
                    "batch": {
                        "id": "55555555-5555-4555-8555-555555555555",
                        "natural_date": "2026-08-18",
                        "cutoff_at": CUTOFF,
                        "coverage_status": "partial",
                    },
                }
        if url.endswith("/api/worker/x-fixed-windows"):
            return 201, {"id": TASK_ID, "source_id": SOURCE_ID, "idempotent": False, "demo_fixed_window": {}}
        if url.endswith(f"/api/worker/x-fixed-windows/{TASK_ID}/claim"):
            if self.task_claimed:
                return 204, None
            self.task_claimed = True
            return 200, _task_claim()
        if url.endswith(f"/api/worker/tasks/{TASK_ID}/result"):
            return 200, {"status": "succeeded", "task_id": TASK_ID}
        if url.endswith(f"/api/worker/x-daily-judgements/{JUDGEMENT_RUN_ID}/context"):
            attempt = int(body["attempt"]) if isinstance(body, dict) else 1
            return 200, {
                "run_id": JUDGEMENT_RUN_ID,
                "batch_id": "55555555-5555-4555-8555-555555555555",
                "attempt": attempt,
                "prompt_version": "v4-x-cross-blogger-1",
                "sources": [],
                "excluded_sources": [],
            }
        if url.endswith(f"/api/worker/x-daily-judgements/{JUDGEMENT_RUN_ID}/complete"):
            self.judgement_status = "succeeded"
            return 200, {"status": "succeeded"}
        if "/api/worker/x-daily-judgements/" in url and url.endswith("/failure"):
            attempt = int(body["attempt"]) if isinstance(body, dict) else 0
            failure_class = str(body["failure_class"]) if isinstance(body, dict) else ""
            self.judgement_failure_calls.append((JUDGEMENT_RUN_ID, attempt, failure_class))
            return 200, {"status": "retryable_failed"}
        raise AssertionError(f"unexpected transport request: {url}")


class _NestedRetryProtocol:
    def __init__(self) -> None:
        self.claim_attempt = 0
        self.provider_failures: list[dict[str, object]] = []
        self.task_terminal = False

    def begin_x_demo_fixed_window_run(self, _cutoff: str) -> dict[str, object]:
        return {
            "run_id": DEMO_RUN_ID, "status": "running", "idempotent": False, "cutoff_at": CUTOFF,
            "sources": [{"source_id": SOURCE_ID, "display_name": "Synthetic source", "resolution_status": "resolved", "account_id": "fixture_account"}],
        }

    def create_x_demo_fixed_window_task_for_run(self, _run_id: str, source_id: str, _cutoff: str, _account_id: str) -> dict[str, object]:
        return {"id": TASK_ID, "source_id": source_id, "idempotent": False, "demo_fixed_window": {}}

    def attach_x_demo_fixed_window_task(self, *_args: str) -> dict[str, object]:
        return {"status": "attached"}

    def heartbeat(self, *_args: object) -> dict[str, object]:
        return {"status": "online"}

    def claim_x_demo_fixed_window_task(self, task_id: str) -> dict[str, object] | None:
        if self.task_terminal:
            return None
        self.claim_attempt += 1
        return {
            "task_id": task_id, "attempt": self.claim_attempt, "task_type": "x_sync", "source_id": SOURCE_ID,
            "parameter_version": "x-standard-v2", "lease_expires_at": "2099-01-01T00:10:00Z", "safe_checkpoint": None,
            "collection_scope": {"mode": "window"}, "capture_range": {
                "mode": "window", "trigger": "scheduled", "timezone": "Asia/Shanghai",
                "start_at": "2026-08-18T04:00:00Z", "end_at": "2026-08-18T08:00:00Z",
                "scheduled_window_key": "2026-08-18T16:00+08:00", "overlap_start_at": "2026-08-18T03:30:00Z",
            }, "coverage_snapshot": {"coverage_start_at": "2026-08-18T04:00:00Z", "coverage_through_at": "2026-08-18T04:00:00Z", "last_completed_task_id": None},
            "capture_progress": {"resume_cursor": None, "page_count": 0, "range_complete": False}, "author_profile_snapshot": [],
            "source_snapshot": {"source_type": "x", "account_id": "fixture_account", "display_name": "Synthetic source", "parameter_version": "x-standard-v2"},
        }

    def persist(self, _payload: dict[str, object]) -> dict[str, object]:
        return {"persisted": True, "resume_cursor": None}

    def renew(self, *_args: object) -> dict[str, object]:
        return {"status": "leased"}

    def report_failure(self, payload: dict[str, object]) -> dict[str, object]:
        self.provider_failures.append(dict(payload))
        self.task_terminal = payload.get("retryable") is False
        return {"status": "retryable_failed"}

    def mark_x_demo_fixed_window_source_failed(self, _run_id: str, _source_id: str, _reason: str) -> dict[str, object]:
        return {"status": "excluded"}

    def settle_x_demo_fixed_window_run(self, _run_id: str) -> dict[str, object]:
        return {"status": "failed", "error": "no_available_input"}


class _AlwaysFailingProvider:
    def __init__(self) -> None:
        self.calls = 0

    def complete(self, _chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
        self.calls += 1
        return ProviderResponse(
            status="provider_failure", provider="fixture", model_reported=None, prompt_version=context.prompt_version,
            elapsed_ms=1, attempt=context.attempt, raw_ref=None, parsed_output_ref=None, parsed_output=None,
            failure_class="provider_failure", error_code="provider_failure",
        )


class _OnePageConnector:
    def fetch_page(self, _source: LocalWorkerConfig, _cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
        return RawPage(
            page_id="nested-retry-page", source_id=SOURCE_ID, source_type="x", cursor_before=None, cursor_after=None,
            raw_payload_ref="local://nested-retry/page", telemetry={
                "match_state": "collection_receipt_verified", "collection_receipt_verified": True,
                "collection_stop_reason": "time_boundary_reached", "collection_requested_until": "2026-08-18T03:30:00Z",
                "collection_oldest_seen_at": "2026-08-18T03:29:00Z", "collection_pages_fetched": 1, "history_exhausted": False,
            }, messages=({
                "id": "nested-retry-post", "author": {"id": "fixture_account", "name": "Synthetic source"}, "text": "公开 synthetic 内容",
                "created_at": "2026-08-18T05:00:00Z", "url": "https://x.com/fixture_account/status/1", "post_type": "original",
                "context_status": "complete", "attachments": [],
            },),
        )


def _config(source_id: str = SOURCE_ID) -> LocalWorkerConfigSet:
    return LocalWorkerConfigSet.from_mapping({
        "control_plane_url": "https://control.example.invalid",
        "sources": [{
            "source_id": source_id,
            "source_type": "x",
            "source_url": "https://x.com/synthetic",
            "profile_ref": "/synthetic/x-profile",
            "opencli_contract_version": "v2",
            "parameter_version": "x-standard-v2",
        }],
    })


class Ticket02RRepairTests(unittest.TestCase):
    def test_real_worker_uses_claimed_judgement_identity(self) -> None:
        transport = _ProductionShapeTransport()
        with tempfile.TemporaryDirectory(prefix="ticket-02r-worker-") as directory:
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.store.save(DeviceCredential("v0", "66666666-6666-4666-8666-666666666666", "s" * 32, "2099-01-01T00:00:00Z"))
            worker = Worker(
                protocol,
                execute=lambda claim: {
                    "contract_version": "v0", "task_id": claim["task_id"], "attempt": claim["attempt"],
                    "status": "succeeded", "safe_checkpoint": None, "raw_count": 1,
                    "canonical_count": 1, "duplicate_count": 0, "unresolved_count": 0,
                    "unparsed_media_count": 0, "structured_run_ids": [],
                    "telemetry": {"elapsed_ms": 1, "retry_count": 0, "failure_class": None},
                },
                clock=lambda: datetime(2026, 8, 18, 9, tzinfo=timezone.utc),
                capabilities=["x_sync"],
            )
            outcome = run_sequential_x_fixed_window(
                worker, _config(), CUTOFF,
                lambda claim, _context: {
                    "run_id": str(claim["run_id"]), "attempt": int(claim["attempt"]),
                    "schema_version": "v4-x-cross-blogger", "provider": "codex_cli", "model_reported": None,
                    "prompt_version": "v4-x-cross-blogger-1", "security_industry_viewpoints": [],
                    "market_structure_viewpoints": [], "strategy_mindset_viewpoints": [], "uncertainties": [],
                },
            )
        self.assertIn(outcome.status, {"complete", "partial"})
        self.assertEqual(transport.claimed_judgement_id, JUDGEMENT_RUN_ID)
        self.assertEqual(transport.judgement_status, "succeeded")

    def test_empty_frozen_snapshot_is_not_no_new(self) -> None:
        class EmptyProtocol:
            def begin_x_demo_fixed_window_run(self, _cutoff: str) -> dict[str, Any]:
                return {"run_id": DEMO_RUN_ID, "status": "running", "idempotent": False, "cutoff_at": CUTOFF, "sources": []}

            def settle_x_demo_fixed_window_run(self, _run_id: str) -> dict[str, Any]:
                return {"run_id": DEMO_RUN_ID, "status": "no_new", "coverage_status": "no_new_information"}

        worker = Worker(EmptyProtocol(), capabilities=["x_sync"])
        outcome = run_sequential_x_fixed_window(worker, _config(), CUTOFF)
        self.assertEqual(outcome.status, "failed")

    def test_ordinary_x_retry_policy_keeps_three_attempts(self) -> None:
        self.assertEqual(RetryPolicy().max_attempts, 3)

    def test_nested_real_worker_runtime_task_retry_is_bounded_to_two_external_provider_calls(self) -> None:
        protocol = _NestedRetryProtocol()
        provider = _AlwaysFailingProvider()
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{
                "source_id": SOURCE_ID, "source_type": "x", "source_url": "https://x.com/synthetic",
                "profile_ref": "/synthetic/x-profile", "opencli_contract_version": "v2", "parameter_version": "x-standard-v2",
            }],
        })
        local_config = config.sources[0]
        with tempfile.TemporaryDirectory(prefix="ticket-02r-nested-retry-") as directory:
            runtime = XWindowedRuntime(
                config=local_config, connector=_OnePageConnector(), evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(), provider=provider, prompt_template="fixture",
            )
            worker = Worker(protocol, execute_windowed=runtime.execute_windowed, capabilities=["x_sync"], clock=lambda: datetime(2026, 8, 18, 9, tzinfo=timezone.utc))
            outcome = run_sequential_x_fixed_window(worker, config, CUTOFF)

        self.assertEqual(outcome.status, "failed")
        self.assertEqual(protocol.provider_failures[0]["retryable"], False)
        self.assertLessEqual(provider.calls, 2)
        self.assertEqual(worker.run_once_for_task(TASK_ID).status, "no_task")
        self.assertEqual(provider.calls, 2)

    def test_second_judgement_failure_terminalizes_exact_identity_once(self) -> None:
        transport = _ProductionShapeTransport(judgement_failure_mode=True)
        with tempfile.TemporaryDirectory(prefix="ticket-02r-worker-failure-") as directory:
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.store.save(DeviceCredential("v0", "66666666-6666-4666-8666-666666666666", "s" * 32, "2099-01-01T00:00:00Z"))
            worker = Worker(
                protocol,
                execute=lambda claim: {
                    "contract_version": "v0", "task_id": claim["task_id"], "attempt": claim["attempt"],
                    "status": "succeeded", "safe_checkpoint": None, "raw_count": 1,
                    "canonical_count": 1, "duplicate_count": 0, "unresolved_count": 0,
                    "unparsed_media_count": 0, "structured_run_ids": [],
                    "telemetry": {"elapsed_ms": 1, "retry_count": 0, "failure_class": None},
                },
                clock=lambda: datetime(2026, 8, 18, 9, tzinfo=timezone.utc),
                capabilities=["x_sync"],
            )

            def provider_failure(_claim: dict[str, object], _context: dict[str, object]) -> dict[str, object]:
                transport.provider_calls += 1
                raise RuntimeError("synthetic provider failure")

            outcome = run_sequential_x_fixed_window(
                worker, _config(), CUTOFF, provider_failure,
            )

        self.assertEqual(outcome.status, "failed")
        self.assertEqual(transport.provider_calls, 2)
        self.assertEqual(
            transport.judgement_failure_calls,
            [(JUDGEMENT_RUN_ID, 1, "persistence_failure"), (JUDGEMENT_RUN_ID, 2, "persistence_failure")],
        )
        self.assertEqual(transport.terminalization_calls, [(DEMO_RUN_ID, JUDGEMENT_RUN_ID)])
        self.assertNotEqual(DEMO_RUN_ID, JUDGEMENT_RUN_ID)


if __name__ == "__main__":
    unittest.main()
