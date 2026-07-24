from __future__ import annotations

import unittest

from invest_hub_worker.errors import RemoteConflict
from invest_hub_worker.runtime import RuntimeExecutionError
from invest_hub_worker.worker import Worker, WorkerState


CLAIM = {
    "contract_version": "v0",
    "task_id": "task-1",
    "attempt": 1,
    "task_type": "discord_sync",
    "source_id": "source-1",
    "parameter_version": "v0-default",
    "lease_expires_at": "2099-01-01T00:10:00Z",
    "safe_checkpoint": None,
}

RESULT = {
    "contract_version": "v0",
    "task_id": "task-1",
    "attempt": 1,
    "status": "succeeded",
    "safe_checkpoint": "message-1",
    "raw_count": 1,
    "canonical_count": 1,
    "duplicate_count": 0,
    "unresolved_count": 0,
    "unparsed_media_count": 0,
    "structured_run_ids": [],
    "telemetry": {"elapsed_ms": 1, "retry_count": 0, "failure_class": None},
}


class FakeProtocol:
    def __init__(self) -> None:
        self.heartbeat_error: Exception | None = None
        self.claim_value: dict[str, object] | None = CLAIM
        self.persisted_payloads: list[dict[str, object]] = []
        self.capture_segments: list[dict[str, object]] = []
        self.range_completions: list[dict[str, object]] = []
        self.reported_results: list[dict[str, object]] = []
        self.reported_failures: list[dict[str, object]] = []
        self.report_result_value: dict[str, object] = {"status": "succeeded", "idempotent": False}
        self.report_result_error: Exception | None = None

    def heartbeat(self, *_args: object, **_kwargs: object) -> dict[str, object]:
        if self.heartbeat_error:
            raise self.heartbeat_error
        return {"status": "idle"}

    def claim(self) -> dict[str, object] | None:
        return self.claim_value

    def report_result(self, result: dict[str, object]) -> dict[str, object]:
        self.reported_results.append(result)
        if self.report_result_error:
            raise self.report_result_error
        return self.report_result_value

    def persist(self, payload: dict[str, object]) -> dict[str, object]:
        self.persisted_payloads.append(payload)
        return {
            "persisted": True,
            "structured_run_ids": ["run-1"],
            "summary_batch_ids": [],
            "daily_summary_ids": [],
        }

    def record_capture_segment(self, payload: dict[str, object]) -> dict[str, object]:
        self.capture_segments.append(payload)
        return {"task_id": payload["task_id"], "idempotent": False, "resume_cursor": "cursor-001"}

    def renew(self, _task_id: str, _attempt: int) -> dict[str, object]:
        return {"lease_expires_at": "2099-01-01T00:20:00Z"}

    def complete_capture_range(self, payload: dict[str, object]) -> dict[str, object]:
        self.range_completions.append(payload)
        return {"status": "succeeded", "idempotent": False, "task_id": payload["task_id"], "attempt": payload["attempt"]}

    def report_failure(self, failure: dict[str, object]) -> dict[str, object]:
        self.reported_failures.append(failure)
        return {"status": "retryable_failed"}


class WorkerRecoveryTests(unittest.TestCase):
    def test_heartbeat_failure_stays_recovering_and_does_not_claim(self) -> None:
        protocol = FakeProtocol()
        protocol.heartbeat_error = OSError("control plane unavailable")
        worker = Worker(protocol)

        outcome = worker.run_once()

        self.assertEqual(outcome.status, "recovering")
        self.assertEqual(worker.state, WorkerState.RECOVERING)

    def test_interrupted_execution_does_not_report_success(self) -> None:
        protocol = FakeProtocol()
        worker = Worker(protocol, execute=lambda _claim: (_ for _ in ()).throw(RuntimeError("interrupted")))

        outcome = worker.run_once()

        self.assertEqual(outcome.status, "recovering")
        self.assertEqual(protocol.reported_results, [])
        self.assertEqual(protocol.reported_failures[0]["failure_class"], "unknown")

    def test_x_contract_failure_is_terminal_instead_of_reentering_the_claim_loop(self) -> None:
        protocol = FakeProtocol()
        protocol.claim_value = {**CLAIM, "task_type": "x_sync", "source_id": "x-source"}
        worker = Worker(
            protocol,
            execute=lambda _claim: (_ for _ in ()).throw(RuntimeExecutionError("opencli_contract", "invalid receipt")),
        )

        outcome = worker.run_once()

        self.assertEqual(outcome.status, "recovering")
        self.assertFalse(protocol.reported_failures[0]["retryable"])

    def test_x_transient_failure_stops_retrying_after_the_third_attempt(self) -> None:
        protocol = FakeProtocol()
        protocol.claim_value = {**CLAIM, "task_type": "x_sync", "source_id": "x-source", "attempt": 3}
        worker = Worker(
            protocol,
            execute=lambda _claim: (_ for _ in ()).throw(RuntimeExecutionError("timeout", "upstream timeout")),
        )

        worker.run_once()

        self.assertFalse(protocol.reported_failures[0]["retryable"])

    def test_expired_lease_stops_before_execution_or_result_report(self) -> None:
        protocol = FakeProtocol()
        protocol.claim_value = {**CLAIM, "lease_expires_at": "2000-01-01T00:00:00Z"}
        executed: list[bool] = []
        worker = Worker(protocol, execute=lambda _claim: executed.append(True) or RESULT)

        outcome = worker.run_once()

        self.assertEqual(outcome.status, "recovering")
        self.assertEqual(executed, [])
        self.assertEqual(protocol.reported_results, [])

    def test_duplicate_success_ack_is_safe_and_conflict_is_not_success(self) -> None:
        protocol = FakeProtocol()
        protocol.report_result_value = {"status": "succeeded", "idempotent": True}
        worker = Worker(protocol, execute=lambda _claim: RESULT)
        self.assertEqual(worker.run_once().status, "succeeded")

        protocol = FakeProtocol()
        protocol.report_result_error = RemoteConflict("conflicting duplicate result")
        worker = Worker(protocol, execute=lambda _claim: RESULT)
        outcome = worker.run_once()
        self.assertEqual(outcome.status, "recovering")
        self.assertNotEqual(outcome.status, "succeeded")

    def test_worker_persists_execution_before_reporting_the_checkpoint(self) -> None:
        protocol = FakeProtocol()
        execution = {
            "persistence": {
                "contract_version": "v0",
                "task_id": "task-1",
                "attempt": 1,
                "source_id": "source-1",
                "raw_messages": [],
                "canonical_messages": [],
                "structured_runs": [],
            },
            "result": dict(RESULT),
        }

        outcome = Worker(protocol, execute=lambda _claim: execution).run_once()

        self.assertEqual(outcome.status, "succeeded")
        self.assertEqual(len(protocol.persisted_payloads), 1)
        self.assertEqual(protocol.reported_results[0]["structured_run_ids"], ["run-1"])

    def test_window_completion_records_page_receipts_then_completes_without_safe_checkpoint_result(self) -> None:
        protocol = FakeProtocol()
        execution = {
            "persistence": {
                "contract_version": "v0",
                "task_id": "task-1",
                "attempt": 1,
                "source_id": "source-1",
                "raw_messages": [],
                "canonical_messages": [],
                "structured_runs": [],
            },
            "capture_segments": [{
                "contract_version": "v0",
                "task_id": "task-1",
                "attempt": 1,
                "capture_segment": {
                    "idempotency_key": "page-001",
                    "request_cursor": None,
                    "next_cursor": "cursor-001",
                    "oldest_occurred_at": "2099-01-01T00:00:00Z",
                    "newest_occurred_at": "2099-01-01T00:00:00Z",
                    "response_matched": True,
                    "response_fresh": True,
                },
            }],
            "range_completion": {
                "contract_version": "v0",
                "task_id": "task-1",
                "attempt": 1,
                "range_complete": True,
                "capture_range": {
                    "mode": "window",
                    "trigger": "manual",
                    "timezone": "Asia/Shanghai",
                    "start_at": "2099-01-01T00:00:00Z",
                    "end_at": "2099-01-01T08:00:00Z",
                    "scheduled_window_key": None,
                },
                "boundary": {"kind": "oldest_at_or_before_start", "observed_at": "2099-01-01T00:00:00Z"},
                "summary_batch_ids": [],
                "daily_summary_ids": [],
                "no_new_data": True,
            },
        }

        outcome = Worker(protocol, execute=lambda _claim: execution).run_once()

        self.assertEqual(outcome.status, "succeeded")
        self.assertEqual(len(protocol.persisted_payloads), 1)
        self.assertEqual(len(protocol.capture_segments), 1)
        self.assertEqual(len(protocol.range_completions), 1)
        self.assertEqual(protocol.reported_results, [])

    def test_x_history_claim_streams_page_persistence_before_range_completion(self) -> None:
        protocol = FakeProtocol()
        protocol.claim_value = {
            **CLAIM,
            "task_type": "x_sync",
            "source_id": "x-source",
            "collection_scope": {"mode": "history"},
            "capture_range": {
                "mode": "history", "trigger": "history", "timezone": "Asia/Shanghai",
                "start_at": "2099-01-01T00:00:00Z", "end_at": "2099-01-01T08:00:00Z",
            },
        }
        streamed: list[bool] = []

        def execute_windowed(claim: dict[str, object], *, on_capture_page: object) -> dict[str, object]:
            streamed.append(True)
            on_capture_page({
                "persistence": {
                    "contract_version": "v0", "task_id": "task-1", "attempt": 1, "source_id": "x-source",
                    "raw_messages": [], "canonical_messages": [], "structured_runs": [],
                    "capture_segment": {
                        "idempotency_key": "history-page-001", "request_cursor": None, "next_cursor": None,
                        "oldest_occurred_at": None, "newest_occurred_at": None,
                        "response_matched": True, "response_fresh": True,
                    },
                },
                "capture_segment": {
                    "contract_version": "v0", "task_id": "task-1", "attempt": 1,
                    "capture_segment": {
                        "idempotency_key": "history-page-001", "request_cursor": None, "next_cursor": None,
                        "oldest_occurred_at": None, "newest_occurred_at": None,
                        "response_matched": True, "response_fresh": True,
                    },
                },
            })
            return {
                "persistence": {
                    "contract_version": "v0", "task_id": "task-1", "attempt": 1, "source_id": "x-source",
                    "raw_messages": [], "canonical_messages": [], "structured_runs": [],
                },
                "capture_segments": [],
                "range_completion": {
                    "contract_version": "v0", "task_id": "task-1", "attempt": 1, "range_complete": True,
                    "capture_range": claim["capture_range"],
                    "boundary": {"kind": "history_exhausted", "observed_at": "2099-01-01T08:00:00Z"},
                    "summary_batch_ids": [], "daily_summary_ids": [], "x_post_analyses": [], "x_daily_segments": [], "no_new_data": True,
                },
            }

        outcome = Worker(
            protocol,
            execute=lambda _claim: (_ for _ in ()).throw(AssertionError("history must stream page persistence")),
            execute_windowed=execute_windowed,
        ).run_once()

        self.assertEqual(outcome.status, "succeeded")
        self.assertEqual(streamed, [True])
        self.assertEqual(len(protocol.persisted_payloads), 1)
        self.assertEqual(protocol.capture_segments, [])
        self.assertEqual(len(protocol.range_completions), 1)


if __name__ == "__main__":
    unittest.main()
