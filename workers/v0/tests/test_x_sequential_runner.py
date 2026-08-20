from __future__ import annotations

import unittest

from invest_hub_worker.config import LocalWorkerConfigSet
from invest_hub_worker.sequential import run_sequential_x_fixed_window
from invest_hub_worker.worker import RunOutcome


def source(source_id: str) -> dict[str, str]:
    return {
        "source_id": source_id,
        "source_type": "x",
        "source_url": f"https://x.com/{source_id}",
        "profile_ref": f"/synthetic/{source_id}",
        "opencli_contract_version": "v2",
        "parameter_version": "x-standard-v2",
    }


class Protocol:
    def __init__(self) -> None:
        self.created: list[tuple[str, str, str]] = []
        self.attached: list[tuple[str, str, str]] = []
        self.failed: list[tuple[str, str, str]] = []

    def begin_x_demo_fixed_window_run(self, cutoff_at: str) -> dict[str, object]:
        return {
            "run_id": "run-1",
            "status": "running",
            "idempotent": False,
            # Deliberately not in processing order: the runner owns stability.
            "sources": [
                {"source_id": "source-d", "display_name": "D", "resolution_status": "resolved", "account_id": "d"},
                {"source_id": "source-a", "display_name": "A", "resolution_status": "resolved", "account_id": "a"},
                {"source_id": "source-c", "display_name": "C", "resolution_status": "resolved", "account_id": "c"},
                {"source_id": "source-b", "display_name": "B", "resolution_status": "resolved", "account_id": "b"},
            ],
        }

    def create_x_demo_fixed_window_task(self, source_id: str, cutoff_at: str, account_id: str) -> dict[str, object]:
        task_id = f"task-{source_id[-1]}"
        self.created.append((source_id, cutoff_at, account_id))
        return {"id": task_id, "source_id": source_id, "idempotent": False, "demo_fixed_window": {}}

    def attach_x_demo_fixed_window_task(self, run_id: str, source_id: str, task_id: str) -> dict[str, object]:
        self.attached.append((run_id, source_id, task_id))
        return {"status": "attached"}

    def mark_x_demo_fixed_window_source_failed(self, run_id: str, source_id: str, reason: str) -> dict[str, object]:
        self.failed.append((run_id, source_id, reason))
        return {"status": "excluded"}

    def settle_x_demo_fixed_window_run(self, run_id: str) -> dict[str, object]:
        return {"status": "judgement_pending", "coverage_status": "partial"}


class DuplicateProtocol(Protocol):
    def begin_x_demo_fixed_window_run(self, _cutoff_at: str) -> dict[str, object]:
        return {"run_id": "run-existing", "status": "partial", "idempotent": True, "cutoff_at": "2026-08-18T16:00:00+08:00", "sources": []}


class NoNewProtocol(Protocol):
    def settle_x_demo_fixed_window_run(self, _run_id: str) -> dict[str, object]:
        return {"status": "no_new", "coverage_status": "no_new_information"}


class FailedProtocol(Protocol):
    def begin_x_demo_fixed_window_run(self, _cutoff_at: str) -> dict[str, object]:
        return {
            "run_id": "run-1", "status": "running", "idempotent": False,
            "sources": [
                {"source_id": "source-a", "display_name": "A", "resolution_status": "resolved", "account_id": "a"},
                {"source_id": "source-b", "display_name": "B", "resolution_status": "resolved", "account_id": "b"},
            ],
        }

    def settle_x_demo_fixed_window_run(self, _run_id: str) -> dict[str, object]:
        return {"status": "failed", "error": "no_available_input"}


class SingleProtocol(Protocol):
    def begin_x_demo_fixed_window_run(self, _cutoff_at: str) -> dict[str, object]:
        return {
            "run_id": "run-1", "status": "running", "idempotent": False,
            "sources": [{"source_id": "source-a", "display_name": "A", "resolution_status": "resolved", "account_id": "a"}],
        }


class ServerSnapshotOnlyProtocol(Protocol):
    def begin_x_demo_fixed_window_run(self, _cutoff_at: str) -> dict[str, object]:
        return {
            "run_id": "run-server-snapshot", "status": "running", "idempotent": False,
            "sources": [{"source_id": "source-server-only", "display_name": "Server only", "resolution_status": "resolved", "account_id": "server-account"}],
        }

    def create_x_demo_fixed_window_task_for_run(self, run_id: str, source_id: str, cutoff_at: str, account_id: str) -> dict[str, object]:
        self.created.append((source_id, cutoff_at, account_id))
        return {"id": "task-server-only", "source_id": source_id, "idempotent": False, "demo_fixed_window": {}}

    def settle_x_demo_fixed_window_run(self, _run_id: str) -> dict[str, object]:
        return {"status": "complete", "coverage_status": "complete"}


class Worker:
    def __init__(self, protocol: Protocol) -> None:
        self.protocol = protocol
        self.calls: list[str] = []

    def run_once_for_task(self, task_id: str, *, x_external_max_attempts: int | None = None) -> RunOutcome:
        del x_external_max_attempts
        self.calls.append(task_id)
        if task_id == "task-d":
            return RunOutcome("recovering", task_id, "provider_failure")
        if task_id == "task-c":
            return RunOutcome("succeeded", task_id, acknowledgement={"no_new_data": True})
        return RunOutcome("succeeded", task_id, acknowledgement={"status": "succeeded"})

    def run_x_daily_judgement_for_run(self, run_id: str, _execute: object) -> RunOutcome:
        return RunOutcome("succeeded", "judgement-1")


class FailingWorker(Worker):
    def run_once_for_task(self, task_id: str, *, x_external_max_attempts: int | None = None) -> RunOutcome:
        del x_external_max_attempts
        self.calls.append(task_id)
        return RunOutcome("recovering", task_id, "provider_failure")


class JudgementFailingWorker(Worker):
    def run_x_daily_judgement_for_run(self, run_id: str, _execute: object) -> RunOutcome:
        self.calls.append(f"judgement:{run_id}")
        return RunOutcome("recovering", run_id, "provider_failure")


class SequentialRunnerTests(unittest.TestCase):
    def test_freezes_all_sources_processes_stably_and_preserves_partial_results(self) -> None:
        protocol = Protocol()
        worker = Worker(protocol)
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [source("source-d"), source("source-a"), source("source-c"), source("source-b")],
        })

        outcome = run_sequential_x_fixed_window(
            worker, config, "2026-08-18T16:00:00+08:00", lambda _claim, _context: {},
        )

        self.assertEqual(outcome.status, "partial")
        self.assertEqual([source_id for source_id, _cutoff, _account in protocol.created], [
            "source-a", "source-b", "source-c", "source-d",
        ])
        self.assertEqual(worker.calls, ["task-a", "task-b", "task-c", "task-d"])
        self.assertEqual([result.status for result in outcome.sources], ["included", "included", "no_new", "excluded"])
        self.assertEqual(protocol.attached[-1], ("run-1", "source-d", "task-d"))
        self.assertEqual(protocol.failed, [("run-1", "source-d", "provider_failure")])

    def test_pending_source_is_rejected_without_runtime_activation(self) -> None:
        class PendingProtocol(Protocol):
            def begin_x_demo_fixed_window_run(self, _cutoff_at: str) -> dict[str, object]:
                return {"run_id": "run-pending", "status": "running", "idempotent": False, "sources": [{"source_id": "source-p", "display_name": "P", "resolution_status": "pending", "account_id": None}]}
        protocol = PendingProtocol()
        worker = Worker(protocol)
        config = LocalWorkerConfigSet.from_mapping({"control_plane_url": "https://control.example.invalid", "sources": [source("source-p")]})

        with self.assertRaisesRegex(ValueError, "x_demo_sources_not_ready"):
            run_sequential_x_fixed_window(worker, config, "2026-08-18T16:00:00+08:00")

    def test_duplicate_cutoff_returns_existing_identity_without_claiming_sources(self) -> None:
        protocol = DuplicateProtocol()
        worker = Worker(protocol)
        config = LocalWorkerConfigSet.from_mapping({"control_plane_url": "https://control.example.invalid", "sources": [source("source-a")]})

        outcome = run_sequential_x_fixed_window(worker, config, "2026-08-18T16:00:00+08:00", lambda _claim, _context: {})

        self.assertEqual(outcome.status, "partial")
        self.assertTrue(outcome.idempotent)
        self.assertEqual(protocol.created, [])
        self.assertEqual(worker.calls, [])

    def test_all_no_new_is_not_promoted_to_judgement(self) -> None:
        protocol = NoNewProtocol()
        worker = Worker(protocol)
        config = LocalWorkerConfigSet.from_mapping({"control_plane_url": "https://control.example.invalid", "sources": [source("source-c")]})

        outcome = run_sequential_x_fixed_window(worker, config, "2026-08-18T16:00:00+08:00", lambda _claim, _context: (_ for _ in ()).throw(AssertionError("no-new must not invoke judgement")))

        self.assertEqual(outcome.status, "no_new")

    def test_all_failed_is_failed_and_each_exact_task_is_attempted_at_most_twice(self) -> None:
        protocol = FailedProtocol()
        worker = FailingWorker(protocol)
        config = LocalWorkerConfigSet.from_mapping({"control_plane_url": "https://control.example.invalid", "sources": [source("source-a"), source("source-b")]})

        outcome = run_sequential_x_fixed_window(worker, config, "2026-08-18T16:00:00+08:00")

        self.assertEqual(outcome.status, "failed")
        self.assertEqual(worker.calls, ["task-a", "task-b"])
        self.assertEqual([result.status for result in outcome.sources], ["excluded", "excluded"])

    def test_judgement_failure_keeps_successful_source_results(self) -> None:
        protocol = SingleProtocol()
        worker = JudgementFailingWorker(protocol)
        config = LocalWorkerConfigSet.from_mapping({"control_plane_url": "https://control.example.invalid", "sources": [source("source-a")]})

        outcome = run_sequential_x_fixed_window(worker, config, "2026-08-18T16:00:00+08:00", lambda _claim, _context: {})

        self.assertEqual(outcome.status, "failed")
        self.assertEqual([result.status for result in outcome.sources], ["included"])
        self.assertEqual(worker.calls, ["task-a", "judgement:run-1", "judgement:run-1"])

    def test_frozen_server_source_runs_even_when_absent_from_local_source_list(self) -> None:
        protocol = ServerSnapshotOnlyProtocol()
        worker = Worker(protocol)
        config = LocalWorkerConfigSet.from_mapping({"control_plane_url": "https://control.example.invalid", "sources": [source("local-only")]})

        outcome = run_sequential_x_fixed_window(worker, config, "2026-08-18T16:00:00+08:00")

        self.assertEqual(outcome.status, "complete")
        self.assertEqual(outcome.sources[0].status, "included")
        self.assertEqual(protocol.created, [("source-server-only", "2026-08-18T16:00:00+08:00", "server-account")])
        self.assertEqual(worker.calls, ["task-server-only"])


if __name__ == "__main__":
    unittest.main()
