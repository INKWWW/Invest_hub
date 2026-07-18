from __future__ import annotations

import unittest

from invest_hub_worker.errors import RemoteConflict
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
        self.reported_results: list[dict[str, object]] = []
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

    def report_failure(self, _failure: dict[str, object]) -> dict[str, object]:
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


if __name__ == "__main__":
    unittest.main()
