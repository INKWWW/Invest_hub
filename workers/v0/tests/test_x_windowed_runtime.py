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
    def test_explicit_history_range_uses_start_boundary_without_a_continuous_overlap(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                return RawPage(
                    page_id="history-page", source_id="x-source", source_type="x", cursor_before=cursor, cursor_after=None,
                    raw_payload_ref="local://x/history-page", telemetry={"match_state": "matched_new", "history_exhausted": True}, messages=(
                        {"id": "post-new", "author": {"id": "account-1", "name": "Fixture"}, "text": "作者评论", "created_at": "2026-07-23T00:10:00Z", "url": "https://x.com/fixture/status/1", "post_type": "quote", "quoted_post_id": "context-1", "context_status": "complete", "context_post": {"id": "context-1", "author": {"id": "other", "name": "Other"}, "text": "引用帖子正文", "url": "https://x.com/other/status/2"}, "attachments": []},
                        {"id": "post-before-history", "author": {"id": "account-1", "name": "Fixture"}, "text": "范围前帖子", "created_at": "2026-07-22T23:20:00Z", "url": "https://x.com/fixture/status/3", "post_type": "original", "context_status": "complete", "attachments": []},
                    ),
                )

        history_claim = claim()
        history_claim["collection_scope"] = {"mode": "history"}
        history_claim["capture_range"] = {
            "mode": "history", "trigger": "history", "timezone": "Asia/Shanghai",
            "start_at": "2026-07-23T00:00:00Z", "end_at": "2026-07-23T08:00:00Z",
        }
        with tempfile.TemporaryDirectory() as directory:
            runtime = XWindowedRuntime(config=source_config(), connector=Connector(), evidence=LocalEvidenceStore(Path(directory) / "evidence"), canonicalizer=Canonicalizer(), provider=Provider(), prompt_template="private")
            completion = runtime.execute_windowed(history_claim)["range_completion"]
        self.assertEqual(completion["capture_range"]["mode"], "history")
        self.assertEqual(completion["boundary"]["kind"], "oldest_at_or_before_start")

    def test_page_is_durable_before_per_post_analysis_and_completion_only_contains_new_posts(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                if cursor is not None or end_at != datetime(2026, 7, 23, 8, tzinfo=timezone.utc):
                    raise AssertionError("X runtime requested an unexpected collection page")
                return RawPage(
                    page_id="x-page-1", source_id="x-source", source_type="x", cursor_before=None, cursor_after=None,
                    raw_payload_ref="local://x/x-page-1", telemetry={"match_state": "matched_new", "history_exhausted": True},
                    messages=(
                        {"id": "post-new", "author": {"id": "account-1", "name": "Fixture"}, "text": "作者评论", "created_at": "2026-07-23T00:10:00Z", "url": "https://x.com/fixture/status/1", "post_type": "quote", "quoted_post_id": "context-1", "context_status": "complete", "context_post": {"id": "context-1", "author": {"id": "other", "name": "Other"}, "text": "引用帖子正文", "url": "https://x.com/other/status/2"}, "attachments": []},
                        {"id": "post-overlap", "author": {"id": "account-1", "name": "Fixture"}, "text": "重叠旧帖", "created_at": "2026-07-22T23:20:00Z", "url": "https://x.com/fixture/status/3", "post_type": "original", "context_status": "complete", "attachments": []},
                    ),
                )

        pages: list[dict[str, object]] = []
        provider = Provider()
        with tempfile.TemporaryDirectory() as directory:
            runtime = XWindowedRuntime(config=source_config(), connector=Connector(), evidence=LocalEvidenceStore(Path(directory) / "evidence"), canonicalizer=Canonicalizer(), provider=provider, prompt_template="private")
            bundle = runtime.execute_windowed(claim(), on_capture_page=pages.append)

        self.assertEqual(provider.operations, ["v2_x_chunk", "v2_x_window"])
        self.assertEqual(len(pages), 1)
        persistence = pages[0]["persistence"]
        self.assertEqual({row["external_message_id"] for row in persistence["x_post_contexts"]}, {"post-new", "post-overlap"})
        self.assertEqual(persistence["raw_messages"][0]["retention_expires_at"], "2027-07-23T00:10:00Z")
        completion = bundle["range_completion"]
        self.assertEqual([row["post_id"] for row in completion["x_post_analyses"]], ["post-new"])
        self.assertEqual(completion["x_daily_segments"][0]["analysis_ids"], ["post-new@1"])
        self.assertEqual(completion["boundary"]["kind"], "oldest_at_or_before_start")

    def test_post_after_fixed_end_is_rejected_without_advancing_the_range(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                return RawPage(page_id="future", source_id="x-source", source_type="x", cursor_before=cursor, cursor_after=None,
                               raw_payload_ref="local://x/future", telemetry={"match_state": "matched_new", "history_exhausted": True}, messages=(
                                   {"id": "future", "author": {"id": "account-1"}, "text": "future", "created_at": "2026-07-23T08:01:00Z", "url": "https://x.com/fixture/status/9", "post_type": "original", "context_status": "complete", "attachments": []},
                               ))

        with tempfile.TemporaryDirectory() as directory:
            runtime = XWindowedRuntime(config=source_config(), connector=Connector(), evidence=LocalEvidenceStore(Path(directory) / "evidence"), canonicalizer=Canonicalizer(), provider=Provider(), prompt_template="private")
            with self.assertRaisesRegex(RuntimeExecutionError, "fixed end_at"):
                runtime.execute_windowed(claim())

    def test_unproven_history_cap_does_not_advance_the_window(self) -> None:
        class Connector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                return RawPage(page_id="cap", source_id="x-source", source_type="x", cursor_before=cursor, cursor_after=None,
                               raw_payload_ref="local://x/cap", telemetry={"match_state": "matched_new", "history_exhausted": False}, messages=(
                                   {"id": "cap", "author": {"id": "account-1"}, "text": "cap", "created_at": "2026-07-23T00:10:00Z", "url": "https://x.com/fixture/status/10", "post_type": "original", "context_status": "complete", "attachments": []},
                               ))
        with tempfile.TemporaryDirectory() as directory:
            runtime = XWindowedRuntime(config=source_config(), connector=Connector(), evidence=LocalEvidenceStore(Path(directory) / "evidence"), canonicalizer=Canonicalizer(), provider=Provider(), prompt_template="private")
            with self.assertRaisesRegex(RuntimeExecutionError, "cannot prove"):
                runtime.execute_windowed(claim())


if __name__ == "__main__":
    unittest.main()
