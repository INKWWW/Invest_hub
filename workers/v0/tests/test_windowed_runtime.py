from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from invest_hub_worker.canonical import Canonicalizer
from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.evidence import LocalEvidenceStore
from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
from invest_hub_worker.runtime import AuthorizedDiscordRuntime, RuntimeExecutionError, WindowedCaptureRange
from invest_hub_worker.worker import Worker


def source_config() -> LocalWorkerConfig:
    return LocalWorkerConfig.from_mapping({
        "control_plane_url": "https://control.example.invalid",
        "source_id": "discord-source",
        "channel_url": "https://discord.com/channels/1/2",
        "profile_ref": "/private/profile",
        "opencli_contract_version": "v0",
        "parameter_version": "v1-1-test",
    })


class EmptyTopicsProvider:
    def complete(self, _chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
        if context.operation == "v1_1_chunk":
            output = {
                "schema_version": "v1.1-chunk",
                "facts": [],
                "media_source_message_ids": sorted(context.unparsed_media_message_ids),
                "warnings": ["存在未解析媒体"] if context.unparsed_media_message_ids else [],
            }
        elif context.operation == "v1_1_daily":
            output = {
                "schema_version": "v1.1",
                "natural_date": context.expected_natural_date,
                "as_of": context.expected_as_of,
                "author_cards": [],
                "topic_discussions": [],
                "warnings": ["存在未解析媒体"] if context.unparsed_media_message_ids else [],
            }
        else:
            output = {"topics": [], "warnings": []}
        return ProviderResponse(
            status="success",
            provider="mock",
            model_reported=None,
            prompt_version=context.prompt_version,
            elapsed_ms=1,
            attempt=context.attempt,
            raw_ref=None,
            parsed_output_ref=None,
            parsed_output=output,
        )


class MoreThanOneHundredPagesConnector:
    def __init__(self) -> None:
        self.calls: list[tuple[str | None, datetime]] = []

    def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
        self.calls.append((cursor, end_at))
        index = len(self.calls) - 1
        occurred_at = datetime(2026, 7, 21, 17, tzinfo=timezone.utc) - timedelta(minutes=index)
        return RawPage(
            page_id=f"page-{index}",
            source_id="discord-source",
            cursor_before=cursor,
            cursor_after=None if index == 100 else f"cursor-{index + 1}",
            messages=(
                {
                    "id": f"message-{index}",
                    "published_at": occurred_at.isoformat().replace("+00:00", "Z"),
                    "author": {"id": "author-1", "name": "Author One"},
                    "content": f"message {index}",
                },
            ),
            raw_payload_ref=f"local://discord/page-{index}",
            telemetry={"match_state": "matched_new", "network_attempts": 1},
        )


def window_claim() -> dict[str, object]:
    return {
        "task_id": "window-task-1",
        "attempt": 1,
        "source_id": "discord-source",
        "parameter_version": "v1-1-test",
        "safe_checkpoint": None,
        "rule_snapshot": {"version": 2, "target_author_ids": []},
        "collection_scope": {"mode": "window"},
        "capture_range": {
            "mode": "window",
            "trigger": "manual",
            "timezone": "Asia/Shanghai",
            "start_at": "2026-07-21T15:20:00Z",
            "end_at": "2026-07-21T17:01:00Z",
            "scheduled_window_key": None,
        },
        "coverage_snapshot": {
            "coverage_start_at": "2026-07-21T15:20:00Z",
            "coverage_through_at": "2026-07-21T15:20:00Z",
            "last_completed_task_id": None,
        },
        "capture_progress": {"resume_cursor": None, "page_count": 0, "range_complete": False},
        "author_profile_snapshot": [],
    }


class WindowedRuntimeTests(unittest.TestCase):
    def test_recovery_window_claim_is_a_valid_non_scheduled_window(self) -> None:
        claim = window_claim()
        capture_range = dict(claim["capture_range"])
        capture_range["trigger"] = "recovery"
        claim["capture_range"] = capture_range

        parsed = WindowedCaptureRange.from_claim(claim)

        self.assertEqual(parsed.capture_range["trigger"], "recovery")

    def test_windowed_runtime_generates_a_v1_1_fact_batch_and_author_daily_summary(self) -> None:
        class OnePageConnector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                return RawPage(
                    page_id="insight-page",
                    source_id="discord-source",
                    cursor_before=cursor,
                    cursor_after=None,
                    messages=(
                        {"id": "insight-1", "published_at": "2026-07-21T16:59:00Z", "author": {"id": "author-1", "name": "Author One"}, "content": "market fixture"},
                        {"id": "boundary", "published_at": "2026-07-21T15:20:00Z", "author": {"id": "author-1", "name": "Author One"}, "content": "boundary fixture"},
                    ),
                    raw_payload_ref="local://discord/insight-page",
                    telemetry={"match_state": "matched_new", "network_attempts": 1},
                )

        class InsightProvider:
            def __init__(self) -> None:
                self.operations: list[str] = []
                self.daily_fact_counts: list[int] = []

            def complete(self, _chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
                self.operations.append(context.operation)
                if context.operation == "v1_1_chunk":
                    message_id, author_id, _display = context.input_message_authors[0]
                    output = {
                        "schema_version": "v1.1-chunk",
                        "facts": [{
                            "author_id": author_id,
                            "topic": "市场",
                            "viewpoint": "风险偏好改善",
                            "reasoning": None,
                            "operation_tendency": None,
                            "methodology": [],
                            "uncertainty": [],
                            "source_message_ids": [message_id],
                        }],
                        "media_source_message_ids": [],
                        "warnings": [],
                    }
                else:
                    self.daily_fact_counts.append(len(_chunk))
                    message_id, author_id, display = context.input_message_authors[0]
                    output = {
                        "schema_version": "v1.1",
                        "natural_date": context.expected_natural_date,
                        "as_of": context.expected_as_of,
                        "author_cards": [{
                            "author_id": author_id,
                            "author_display": display,
                            "core_logic": {"market_trend": "偏多", "stock_judgments": []},
                            "operation_tendency": {"market": None, "stocks": None},
                            "methodology": [],
                            "uncertainty": [],
                            "source_message_ids": [message_id],
                        }],
                        "topic_discussions": [],
                        "warnings": [],
                    }
                return ProviderResponse(
                    status="success", provider="mock", model_reported=None,
                    prompt_version=context.prompt_version, elapsed_ms=1, attempt=context.attempt,
                    raw_ref=None, parsed_output_ref=None, parsed_output=output,
                )

        claim = window_claim()
        claim["author_profile_snapshot"] = [{
            "profile_id": "profile-1",
            "requested_author": "Author One",
            "resolution_status": "pending",
            "author_id": None,
            "author_display": "Author One",
            "author_handle": None,
            "enabled": True,
        }]
        resolver_calls: list[bool] = []
        provider = InsightProvider()
        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=source_config(), connector=OnePageConnector(), evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(), provider=provider, prompt_template="private prompt",
            )
            bundle = runtime.execute_windowed(claim, load_daily_fact_context=lambda: {
                "message_catalog": [{
                    "external_message_id": "prior-1",
                    "natural_date": "2026-07-22",
                    "author_id": "author-1",
                    "author_display": "Author One",
                    "has_unparsed_media": False,
                }],
                "prior_batches": [{
                    "natural_date": "2026-07-22",
                    "facts": [{
                        "author_id": "author-1",
                        "topic": "市场",
                        "viewpoint": "早盘判断",
                        "reasoning": None,
                        "operation_tendency": None,
                        "methodology": [],
                        "uncertainty": [],
                        "source_message_ids": ["prior-1"],
                    }],
                    "warnings": [],
                    "unparsed_media_message_ids": [],
                }],
            }, resolve_author_profiles=lambda: {
                "author_profiles": [{
                    "profile_id": "profile-1",
                    "requested_author": "Author One",
                    "resolution_status": "resolved",
                    "author_id": "author-1",
                    "author_display": "Author One",
                    "author_handle": None,
                    "enabled": True,
                }],
            } if not resolver_calls.append(True) else {})

        self.assertEqual(resolver_calls, [True])
        self.assertEqual(provider.operations, ["v1_1_chunk", "v1_1_daily"])
        self.assertEqual(provider.daily_fact_counts, [2])
        self.assertEqual(bundle["persistence"]["structured_runs"][0]["output"]["schema_version"], "v1.1-chunk")
        output = bundle["persistence"]["batch_summaries"][0]["output"]
        self.assertEqual(output["schema_version"], "v1.1-batch")
        self.assertEqual(output["daily_summary"]["author_cards"][0]["author_display"], "Author One")

    def test_window_collection_reaches_the_time_boundary_after_more_than_one_hundred_pages(self) -> None:
        connector = MoreThanOneHundredPagesConnector()
        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=source_config(),
                connector=connector,
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=EmptyTopicsProvider(),
                prompt_template="private prompt",
            )

            bundle = runtime.execute(window_claim())

        self.assertEqual(len(connector.calls), 101)
        self.assertEqual(len(bundle["capture_segments"]), 101)
        self.assertEqual(bundle["range_completion"]["boundary"], {
            "kind": "oldest_at_or_before_start",
            "observed_at": "2026-07-21T15:20:00Z",
        })
        structured_ids = [
            message_id
            for run in bundle["persistence"]["structured_runs"]
            for message_id in run["input_message_ids"]
        ]
        self.assertEqual(len(structured_ids), 100)
        self.assertIn("message-99", structured_ids)
        self.assertNotIn("message-100", structured_ids)

    def test_invalid_page_timestamp_fails_before_emitting_a_recovery_segment(self) -> None:
        class InvalidTimestampConnector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                return RawPage(
                    page_id="invalid-page",
                    source_id="discord-source",
                    cursor_before=cursor,
                    cursor_after=None,
                    messages=({
                        "id": "invalid-message",
                        "published_at": "not-a-timestamp",
                        "author": {"id": "author-1", "name": "Author One"},
                        "content": "invalid fixture",
                    },),
                    raw_payload_ref="local://discord/invalid-page",
                    telemetry={"match_state": "matched_new", "network_attempts": 1},
                )

        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=source_config(),
                connector=InvalidTimestampConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=EmptyTopicsProvider(),
                prompt_template="private prompt",
            )
            with self.assertRaises(RuntimeExecutionError) as caught:
                runtime.execute(window_claim())

        self.assertEqual(caught.exception.failure_class, "schema_error")

    def test_window_claim_rejects_a_scheduled_range_without_its_schedule_boundary(self) -> None:
        class NoFetchConnector:
            def fetch_page(self, *_args: object, **_kwargs: object) -> RawPage:
                raise AssertionError("an invalid claim must fail before Discord collection")

        claim = window_claim()
        claim["capture_range"] = {
            **claim["capture_range"],  # type: ignore[arg-type]
            "trigger": "scheduled",
            "scheduled_window_key": None,
        }
        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=source_config(),
                connector=NoFetchConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=EmptyTopicsProvider(),
                prompt_template="private prompt",
            )
            with self.assertRaises(RuntimeExecutionError) as caught:
                runtime.execute(claim)

        self.assertEqual(caught.exception.failure_class, "preflight")

    def test_resume_cursor_is_acknowledged_per_page_and_messages_after_end_are_excluded(self) -> None:
        test_case = self

        class ResumingConnector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                test_case.assertEqual(cursor, "cursor-1")
                test_case.assertEqual(end_at, datetime(2026, 7, 21, 17, 1, tzinfo=timezone.utc))
                return RawPage(
                    page_id="resumed-page",
                    source_id="discord-source",
                    cursor_before="cursor-1",
                    cursor_after="cursor-2",
                    messages=(
                        {"id": "late", "published_at": "2026-07-21T17:02:00Z", "author": {"id": "author-1", "name": "Author"}, "content": "too late"},
                        {"id": "in-window", "published_at": "2026-07-21T16:59:00Z", "author": {"id": "author-1", "name": "Author"}, "content": "included"},
                        {"id": "at-start", "published_at": "2026-07-21T15:20:00Z", "author": {"id": "author-1", "name": "Author"}, "content": "boundary only"},
                    ),
                    raw_payload_ref="local://discord/resumed-page",
                    telemetry={"match_state": "matched_new", "network_attempts": 1},
                )

        claim = window_claim()
        claim["capture_progress"] = {"resume_cursor": "cursor-1", "page_count": 1, "range_complete": False}
        page_events: list[dict[str, object]] = []
        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=source_config(),
                connector=ResumingConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=EmptyTopicsProvider(),
                prompt_template="private prompt",
            )
            bundle = runtime.execute_windowed(claim, on_capture_page=page_events.append)

        self.assertEqual(len(page_events), 1)
        page_persistence = page_events[0]["persistence"]
        self.assertEqual(page_persistence["capture_segment"]["request_cursor"], "cursor-1")
        self.assertEqual(page_persistence["capture_segment"]["next_cursor"], "cursor-2")
        self.assertEqual({item["external_message_id"] for item in page_persistence["canonical_messages"]}, {"late", "in-window", "at-start"})
        self.assertEqual(bundle["capture_segments"], [])
        self.assertEqual(bundle["persistence"]["structured_runs"][0]["input_message_ids"], ["in-window"])
        self.assertEqual(bundle["range_completion"]["boundary"], {
            "kind": "oldest_at_or_before_start",
            "observed_at": "2026-07-21T15:20:00Z",
        })

    def test_verified_empty_page_completes_an_empty_range_with_history_evidence(self) -> None:
        class EmptyHistoryConnector:
            def fetch_page(self, _source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime) -> RawPage:
                return RawPage(
                    page_id="empty-page",
                    source_id="discord-source",
                    cursor_before=cursor,
                    cursor_after=None,
                    messages=(),
                    raw_payload_ref="local://discord/empty-page",
                    telemetry={"match_state": "matched_new", "network_attempts": 1},
                )

        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=source_config(),
                connector=EmptyHistoryConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=EmptyTopicsProvider(),
                prompt_template="private prompt",
                clock=lambda: datetime(2026, 7, 21, 19, tzinfo=timezone.utc),
            )
            bundle = runtime.execute(window_claim())

        self.assertTrue(bundle["range_completion"]["no_new_data"])
        self.assertEqual(bundle["range_completion"]["boundary"], {
            "kind": "history_exhausted",
            "observed_at": "2026-07-21T19:00:00Z",
        })
        self.assertEqual(len(bundle["capture_segments"]), 1)

    def test_worker_confirms_each_page_segment_before_renewing_and_finalizing_the_range(self) -> None:
        events: list[str] = []
        claim = {**window_claim(), "lease_expires_at": "2099-01-01T00:10:00Z"}
        test_case = self

        class Protocol:
            def heartbeat(self, *_args: object) -> dict[str, object]:
                return {"status": "idle"}

            def claim(self) -> dict[str, object]:
                return claim

            def persist(self, payload: dict[str, object]) -> dict[str, object]:
                if "capture_segment" in payload:
                    events.append("page-persist")
                    return {"persisted": True, "resume_cursor": "cursor-1"}
                events.append("final-persist")
                return {"persisted": True, "structured_run_ids": [], "summary_batch_ids": [], "daily_summary_ids": []}

            def renew(self, task_id: str, attempt: int) -> dict[str, object]:
                test_case.assertEqual(task_id, "window-task-1")
                test_case.assertEqual(attempt, 1)
                events.append("renew")
                return {"lease_expires_at": "2099-01-01T00:20:00Z"}

            def complete_capture_range(self, _payload: dict[str, object]) -> dict[str, object]:
                events.append("complete")
                return {"status": "succeeded"}

            def report_failure(self, _payload: dict[str, object]) -> dict[str, object]:
                raise AssertionError("windowed success must not report failure")

        class StreamingRuntime:
            def execute_windowed(self, _claim: dict[str, object], *, on_capture_page: object) -> dict[str, object]:
                on_capture_page({
                    "persistence": {
                        "contract_version": "v0", "task_id": "window-task-1", "attempt": 1,
                        "source_id": "discord-source", "raw_messages": [], "canonical_messages": [], "structured_runs": [],
                        "capture_segment": {
                            "idempotency_key": "page:1", "request_cursor": None, "next_cursor": "cursor-1",
                            "oldest_occurred_at": None, "newest_occurred_at": None,
                            "response_matched": True, "response_fresh": True,
                        },
                    },
                    "capture_segment": {"contract_version": "v0", "task_id": "window-task-1", "attempt": 1, "capture_segment": {
                        "idempotency_key": "page:1", "request_cursor": None, "next_cursor": "cursor-1",
                        "oldest_occurred_at": None, "newest_occurred_at": None,
                        "response_matched": True, "response_fresh": True,
                    }},
                })
                return {
                    "persistence": {
                        "contract_version": "v0", "task_id": "window-task-1", "attempt": 1,
                        "source_id": "discord-source", "raw_messages": [], "canonical_messages": [], "structured_runs": [],
                    },
                    "capture_segments": [],
                    "range_completion": {
                        "contract_version": "v0", "task_id": "window-task-1", "attempt": 1, "range_complete": True,
                        "capture_range": claim["capture_range"],
                        "boundary": {"kind": "history_exhausted", "observed_at": "2026-07-21T17:01:00Z"},
                        "summary_batch_ids": [], "daily_summary_ids": [], "no_new_data": True,
                    },
                }

        worker = Worker(Protocol(), execute_windowed=StreamingRuntime().execute_windowed)

        outcome = worker.run_once()

        self.assertEqual(outcome.status, "succeeded")
        self.assertEqual(events, ["page-persist", "renew", "final-persist", "complete"])

    def test_worker_refuses_a_window_claim_when_no_streaming_executor_is_configured(self) -> None:
        failures: list[dict[str, object]] = []
        claim = {**window_claim(), "lease_expires_at": "2099-01-01T00:10:00Z"}

        class Protocol:
            def heartbeat(self, *_args: object) -> dict[str, object]:
                return {"status": "idle"}

            def claim(self) -> dict[str, object]:
                return claim

            def persist(self, _payload: dict[str, object]) -> dict[str, object]:
                raise AssertionError("a non-streaming executor must not persist a window")

            def report_failure(self, payload: dict[str, object]) -> dict[str, object]:
                failures.append(payload)
                return {"status": "retryable_failed"}

        executed: list[bool] = []
        outcome = Worker(Protocol(), execute=lambda _claim: executed.append(True) or {}).run_once()

        self.assertEqual(outcome.status, "recovering")
        self.assertEqual(executed, [])
        self.assertEqual(failures[0]["failure_class"], "unknown")


if __name__ == "__main__":
    unittest.main()
