from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from invest_hub_worker.canonical import Canonicalizer
from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.evidence import LocalEvidenceStore
from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
from invest_hub_worker.runtime import RuntimeExecutionError, XWindowedRuntime


LOWER_BOUND = datetime(2026, 7, 22, 23, 30, tzinfo=timezone.utc)
END_AT = datetime(2026, 7, 23, 8, tzinfo=timezone.utc)


def source_config() -> LocalWorkerConfig:
    return LocalWorkerConfig.from_mapping({
        "control_plane_url": "https://control.example.invalid", "source_id": "x-source",
        "source_type": "x", "source_url": "https://x.com/fixture", "profile_ref": "/private/x-profile",
        "opencli_contract_version": "v2", "parameter_version": "v2-test",
    })


def claim() -> dict[str, object]:
    return {
        "task_id": "x-window-1", "attempt": 1, "task_type": "x_sync", "source_id": "x-source",
        "parameter_version": "v2-test", "safe_checkpoint": None, "rule_snapshot": {"version": 0, "target_author_ids": []},
        "collection_scope": {"mode": "window"},
        "capture_range": {
            "mode": "window", "trigger": "scheduled", "timezone": "Asia/Shanghai",
            "start_at": "2026-07-23T00:00:00Z", "end_at": "2026-07-23T08:00:00Z",
            "scheduled_window_key": "2026-07-23T16:00+08:00", "overlap_start_at": "2026-07-22T23:30:00Z",
        },
        "coverage_snapshot": {"coverage_start_at": "2026-07-23T00:00:00Z", "coverage_through_at": "2026-07-23T00:00:00Z", "last_completed_task_id": None},
        "capture_progress": {"resume_cursor": None, "page_count": 0, "range_complete": False},
        "author_profile_snapshot": [],
        "source_snapshot": {"source_type": "x", "account_id": "account-1", "display_name": "Fixture", "parameter_version": "v2-test"},
    }


def history_claim() -> dict[str, object]:
    value = claim()
    value["collection_scope"] = {"mode": "history"}
    value["capture_range"] = {
        "mode": "history", "trigger": "history", "timezone": "Asia/Shanghai",
        "start_at": "2026-07-23T00:00:00Z", "end_at": "2026-07-23T08:00:00Z",
    }
    return value


def receipt_telemetry(
    stop_reason: str,
    oldest_seen_at: str | None,
    requested_until: str = "2026-07-22T23:30:00Z",
) -> dict[str, object]:
    return {
        "match_state": "collection_receipt_verified",
        "collection_receipt_verified": True,
        "collection_stop_reason": stop_reason,
        "collection_requested_until": requested_until,
        "collection_oldest_seen_at": oldest_seen_at,
        "collection_pages_fetched": 2,
        "history_exhausted": stop_reason == "cursor_exhausted",
    }


def quote_post() -> dict[str, object]:
    return {
        "id": "post-new", "author": {"id": "account-1", "name": "Fixture"}, "text": "作者评论",
        "created_at": "2026-07-23T00:10:00Z", "url": "https://x.com/fixture/status/1",
        "post_type": "quote", "quoted_post_id": "context-1", "context_status": "complete",
        "context_post": {"id": "context-1", "author": {"id": "other", "name": "Other"}, "text": "引用帖子正文", "url": "https://x.com/other/status/2"},
        "attachments": [],
    }


class Provider:
    def __init__(self) -> None:
        self.operations: list[str] = []

    def complete(self, _chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
        self.operations.append(context.operation)
        if context.operation == "v2_x_chunk":
            post_id = next(iter(context.input_message_ids))
            output = {"schema_version": "v2-x-chunk", "analyses": [{
                "post_id": post_id, "blogger_viewpoint": "作者判断", "arguments": ["帖子论据"],
                "quoted_post_viewpoint": "被引用观点", "uncertainties": [],
                "evidence_post_ids": [post_id, "context-1"], "post_link": "https://x.com/fixture/status/1",
            }]}
        else:
            output = {"schema_version": "v2-x-window", "natural_date": "2026-07-23", "range_task_id": "x-window-1",
                      "occurred_from_at": "2026-07-23T00:10:00Z", "occurred_through_at": "2026-07-23T00:10:00Z",
                      "window_viewpoints": ["本窗口综合观点"], "analysis_ids": ["post-new@1"],
                      "evidence_post_ids": ["post-new", "context-1"], "uncertainties": []}
        return ProviderResponse(status="success", provider="mock", model_reported=None, prompt_version=context.prompt_version,
                                elapsed_ms=1, attempt=context.attempt, raw_ref=None, parsed_output_ref=None, parsed_output=output)


class XWindowedRuntimeTests(unittest.TestCase):
    def runtime(self, connector: object, directory: str) -> XWindowedRuntime:
        return XWindowedRuntime(
            config=source_config(), connector=connector, evidence=LocalEvidenceStore(Path(directory) / "evidence"),
            canonicalizer=Canonicalizer(), provider=Provider(), prompt_template="private",
        )

    def test_receipt_uses_overlap_start_as_lower_boundary_and_completes_the_window(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
                if cursor is not None or lower_bound_at != LOWER_BOUND or end_at != END_AT:
                    raise AssertionError("X runtime did not request the immutable Collection range")
                return RawPage(
                    page_id="x-page-1", source_id="x-source", source_type="x", cursor_before=None, cursor_after=None,
                    raw_payload_ref="local://x/x-page-1", telemetry=receipt_telemetry("time_boundary_reached", "2026-07-22T23:29:00Z"),
                    messages=(quote_post(),),
                )

        with tempfile.TemporaryDirectory() as directory:
            completion = self.runtime(Connector(), directory).execute_windowed(claim())["range_completion"]
        self.assertEqual(completion["boundary"]["kind"], "oldest_at_or_before_start")
        self.assertEqual(completion["boundary"]["observed_at"], "2026-07-22T23:29:00Z")
        self.assertEqual([row["post_id"] for row in completion["x_post_analyses"]], ["post-new"])

    def test_history_task_uses_the_same_bounded_execution_path(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
                if cursor is not None or lower_bound_at != datetime(2026, 7, 23, 0, tzinfo=timezone.utc) or end_at != END_AT:
                    raise AssertionError("history task did not preserve its immutable bounds")
                return RawPage(
                    page_id="x-history-1", source_id="x-source", source_type="x", cursor_before=None, cursor_after=None,
                    raw_payload_ref="local://x/x-history-1", telemetry=receipt_telemetry(
                        "time_boundary_reached", "2026-07-22T23:59:00Z", "2026-07-23T00:00:00Z",
                    ),
                    messages=(quote_post(),),
                )

        with tempfile.TemporaryDirectory() as directory:
            completion = self.runtime(Connector(), directory).execute(history_claim())["range_completion"]
        self.assertEqual(completion["capture_range"]["mode"], "history")
        self.assertEqual([row["post_id"] for row in completion["x_post_analyses"]], ["post-new"])

    def test_cursor_exhausted_empty_page_is_a_valid_no_new_data_completion(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
                return RawPage(
                    page_id="empty", source_id="x-source", source_type="x", cursor_before=None, cursor_after=None,
                    raw_payload_ref="local://x/empty", telemetry=receipt_telemetry("cursor_exhausted", None), messages=(),
                )

        with tempfile.TemporaryDirectory() as directory:
            completion = self.runtime(Connector(), directory).execute_windowed(claim())["range_completion"]
        self.assertEqual(completion["boundary"]["kind"], "history_exhausted")
        self.assertTrue(completion["no_new_data"])

    def test_unverified_receipt_cannot_advance_the_window(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
                return RawPage(
                    page_id="invalid", source_id="x-source", source_type="x", cursor_before=None, cursor_after=None,
                    raw_payload_ref="local://x/invalid", telemetry={"match_state": "matched_new", "history_exhausted": True}, messages=(quote_post(),),
                )

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeExecutionError, "receipt"):
                self.runtime(Connector(), directory).execute_windowed(claim())

    def test_invalid_page_mapping_reports_a_safe_stage_without_post_details(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
                malformed = {**quote_post(), "author": {}}
                return RawPage(
                    page_id="malformed", source_id="x-source", source_type="x", cursor_before=None, cursor_after=None,
                    raw_payload_ref="local://x/malformed", telemetry=receipt_telemetry("time_boundary_reached", "2026-07-22T23:29:00Z"),
                    messages=(malformed,),
                )

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeExecutionError, "page mapping failed"):
                self.runtime(Connector(), directory).execute_windowed(claim())

    def test_post_after_fixed_end_is_rejected_without_advancing_the_range(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, lower_bound_at: datetime, end_at: datetime) -> RawPage:
                future = {"id": "future", "author": {"id": "account-1"}, "text": "future", "created_at": "2026-07-23T08:01:00Z", "url": "https://x.com/fixture/status/9", "post_type": "original", "context_status": "complete", "attachments": []}
                return RawPage(page_id="future", source_id="x-source", source_type="x", cursor_before=None, cursor_after=None,
                               raw_payload_ref="local://x/future", telemetry=receipt_telemetry("time_boundary_reached", "2026-07-22T23:29:00Z"), messages=(future,))

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeExecutionError, "fixed end_at"):
                self.runtime(Connector(), directory).execute_windowed(claim())


if __name__ == "__main__":
    unittest.main()
