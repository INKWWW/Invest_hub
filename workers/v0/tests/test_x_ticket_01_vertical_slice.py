from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from invest_hub_worker.activation import activate_one_x_source
from invest_hub_worker.canonical import Canonicalizer
from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.evidence import LocalEvidenceStore
from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
from invest_hub_worker.runtime import XWindowedRuntime
from invest_hub_worker.worker import Worker


CLAIM = {
    "task_id": "ticket-01-vertical-task", "attempt": 1, "task_type": "x_sync", "source_id": "ticket-01-source",
    "parameter_version": "x-standard-v2", "lease_expires_at": "2099-01-01T00:10:00Z", "safe_checkpoint": None,
    "rule_snapshot": {"version": 0, "target_author_ids": []}, "collection_scope": {"mode": "window"},
    "capture_range": {
        "mode": "window", "trigger": "scheduled", "timezone": "Asia/Shanghai",
        "start_at": "2026-08-17T04:00:00Z", "end_at": "2026-08-17T08:00:00Z",
        "scheduled_window_key": "2026-08-17T16:00+08:00", "overlap_start_at": "2026-08-17T04:00:00Z",
    },
    "coverage_snapshot": {"coverage_start_at": "2026-08-16T08:00:00Z", "coverage_through_at": "2026-08-16T08:00:00Z", "last_completed_task_id": None},
    "capture_progress": {"resume_cursor": None, "page_count": 0, "range_complete": False},
    "author_profile_snapshot": [],
    "source_snapshot": {"source_type": "x", "account_id": "vertical_fixture", "display_name": "Ticket 01 blogger", "parameter_version": "x-standard-v2"},
}


class MockOpenCLI:
    def resolve(self, requested_handle: str) -> str:
        if requested_handle != "vertical_fixture":
            raise AssertionError("unexpected identity handle")
        return "vertical_fixture"


class MockConnector:
    def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
        if cursor is not None or lower_bound_at != datetime(2026, 8, 17, 4, tzinfo=timezone.utc) or end_at != datetime(2026, 8, 17, 8, tzinfo=timezone.utc):
            raise AssertionError("the fixed target range was not preserved")
        return RawPage(
            page_id="ticket-01-page", source_id="ticket-01-source", source_type="x", cursor_before=None, cursor_after=None,
            raw_payload_ref="local://ticket-01/page", telemetry={
                "match_state": "collection_receipt_verified", "collection_receipt_verified": True,
                "collection_stop_reason": "time_boundary_reached", "collection_requested_until": "2026-08-17T04:00:00Z",
                "collection_oldest_seen_at": "2026-08-17T03:59:00Z", "collection_pages_fetched": 1, "history_exhausted": False,
            }, messages=({
                "id": "ticket-01-post", "author": {"id": "vertical_fixture", "name": "Ticket 01 blogger"},
                "text": "公开 synthetic 观点", "created_at": "2026-08-17T05:00:00Z",
                "url": "https://x.com/vertical_fixture/status/1", "post_type": "original", "context_status": "complete", "attachments": [],
            },),
        )


class MockProvider:
    def complete(self, _items: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
        if context.operation == "v4_x_post_analysis":
            output = {"schema_version": "v4-x-post-analysis", "analyses": [{
                "post_id": "ticket-01-post", "investment_relevance": "investment_related", "investment_categories": ["security_industry"],
                "blogger_viewpoint": "公开 synthetic 观点", "action_intent": "watch", "action_scope_status": "specified", "action_scope": "公开 synthetic 标的",
                "conditions": [], "arguments": ["公开 synthetic 论据"], "quoted_post_viewpoint": None, "uncertainties": [],
                "evidence_post_ids": ["ticket-01-post"], "post_link": "https://x.com/vertical_fixture/status/1",
            }]}
        elif context.operation == "v4_x_window":
            output = {"schema_version": "v4-x-window", "range_task_id": "ticket-01-vertical-task", "natural_date": "2026-08-17",
                      "occurred_from_at": "2026-08-17T05:00:00Z", "occurred_through_at": "2026-08-17T05:00:00Z",
                      "security_industry_viewpoints": [{"statement": "公开 synthetic 窗口观点", "action_intent": "watch", "action_scope_status": "specified", "action_scope": "公开 synthetic 标的", "conditions": [], "analysis_ids": ["ticket-01-post@2"], "evidence_post_ids": ["ticket-01-post"], "uncertainties": []}],
                      "market_structure_viewpoints": [], "strategy_mindset_viewpoints": [], "analysis_ids": ["ticket-01-post@2"], "evidence_post_ids": ["ticket-01-post"], "uncertainties": []}
        else:
            raise AssertionError(f"unexpected mock Provider operation: {context.operation}")
        return ProviderResponse(status="success", provider="mock", model_reported=None, prompt_version=context.prompt_version, elapsed_ms=1, attempt=context.attempt, raw_ref=None, parsed_output_ref=None, parsed_output=output)


class VerticalProtocol:
    def __init__(self) -> None:
        self.activation_claimed = False
        self.identity_resolved = False
        self.initialized = False
        self.claimed = False
        self.raw_messages: list[dict[str, object]] = []
        self.canonical_messages: list[dict[str, object]] = []
        self.contexts: list[dict[str, object]] = []
        self.analyses: list[dict[str, object]] = []
        self.segments: list[dict[str, object]] = []
        self.failed: list[dict[str, object]] = []

    def claim_x_activation(self) -> dict[str, object] | None:
        if self.activation_claimed:
            return None
        self.activation_claimed = True
        return {"source_id": "ticket-01-source", "requested_handle": "vertical_fixture", "parameter_version": "x-standard-v2", "initial_end_at": "2026-08-17T08:00:00Z", "idempotent": False}

    def resolve_x_source_identity(self, source_id: str, parameter_version: str, account_id: str) -> dict[str, object]:
        if (source_id, parameter_version, account_id) != ("ticket-01-source", "x-standard-v2", "vertical_fixture"):
            raise AssertionError("identity activation crossed the configured source boundary")
        self.identity_resolved = True
        return {"resolution_status": "resolved", "parameter_version": parameter_version, "idempotent": False}

    def initialize_x_activation(self, source_id: str) -> dict[str, object]:
        if not self.identity_resolved or source_id != "ticket-01-source":
            raise AssertionError("coverage initialized before identity")
        self.initialized = True
        return {"task_id": None, "source_id": source_id, "initial_end_at": "2026-08-17T08:00:00Z", "idempotent": False}

    def mark_x_activation_identity_failed(self, _source_id: str, error_code: str) -> dict[str, object]:
        self.failed.append({"stage": "identity", "error_code": error_code})
        return {"source_id": "ticket-01-source", "stage": "identity_failed"}

    def heartbeat(self, *_args: object) -> dict[str, object]:
        return {"status": "idle"}

    def claim(self) -> dict[str, object] | None:
        if not self.initialized or self.claimed:
            return None
        self.claimed = True
        return dict(CLAIM)

    def persist(self, payload: dict[str, object]) -> dict[str, object]:
        self.raw_messages.extend(payload["raw_messages"])  # type: ignore[arg-type]
        self.canonical_messages.extend(payload["canonical_messages"])  # type: ignore[arg-type]
        self.contexts.extend(payload["x_post_contexts"])  # type: ignore[arg-type]
        return {"persisted": True, "resume_cursor": None, "structured_run_ids": [], "summary_batch_ids": [], "daily_summary_ids": []}

    def renew(self, _task_id: str, _attempt: int) -> dict[str, object]:
        return {"status": "leased"}

    def record_capture_segment(self, payload: dict[str, object]) -> dict[str, object]:
        self.segments.append(dict(payload["capture_segment"]))  # type: ignore[arg-type]
        return {"persisted": True}

    def complete_capture_range(self, payload: dict[str, object]) -> dict[str, object]:
        self.analyses.extend(payload["x_post_analyses"])  # type: ignore[arg-type]
        self.segments.append(dict(payload["x_daily_segments"][0]))  # type: ignore[index,arg-type]
        return {"status": "succeeded", "demo_fixed_window": True}

    def report_failure(self, payload: dict[str, object]) -> dict[str, object]:
        self.failed.append(dict(payload))
        return {"status": "retryable_failed"}


class Ticket01VerticalSliceTests(unittest.TestCase):
    def test_offline_activation_to_reader_visible_fixed_window_uses_one_business_chain(self) -> None:
        protocol = VerticalProtocol()
        activation = activate_one_x_source(protocol, MockOpenCLI())
        self.assertEqual(activation.status, "initialized")
        self.assertTrue(protocol.identity_resolved)
        self.assertTrue(protocol.initialized)

        config = LocalWorkerConfig.from_mapping({
            "control_plane_url": "https://control.example.invalid", "source_id": "ticket-01-source", "source_type": "x",
            "source_url": "https://x.com/vertical_fixture", "profile_ref": "/synthetic/x-profile", "opencli_contract_version": "v2",
            "parameter_version": "x-standard-v2",
        })
        with tempfile.TemporaryDirectory() as directory:
            runtime = XWindowedRuntime(
                config=config, connector=MockConnector(), evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=MockProvider(), prompt_template="public synthetic prompt",
            )
            outcome = Worker(protocol, execute_windowed=runtime.execute_windowed, capabilities=["x_sync"], clock=lambda: datetime(2026, 8, 17, 9, tzinfo=timezone.utc)).run_once()

        self.assertEqual(outcome.status, "succeeded")
        self.assertEqual(len(protocol.raw_messages), 1)
        self.assertEqual(len(protocol.canonical_messages), 1)
        self.assertEqual(len(protocol.contexts), 1)
        self.assertEqual(len(protocol.analyses), 1)
        self.assertEqual(protocol.analyses[0]["analysis_id"], "ticket-01-post@2")
        self.assertEqual(len(protocol.segments), 1)
        reader_segment = protocol.segments[-1]
        self.assertEqual(reader_segment["natural_date"], "2026-08-17")
        self.assertEqual(reader_segment["segment_output"]["security_industry_viewpoints"][0]["statement"], "公开 synthetic 窗口观点")  # type: ignore[index]
        self.assertFalse(protocol.failed)


if __name__ == "__main__":
    unittest.main()
