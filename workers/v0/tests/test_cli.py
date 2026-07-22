from __future__ import annotations

import unittest

from invest_hub_worker.cli import _run_scheduled, build_parser
from invest_hub_worker.worker import RunOutcome


class ScheduledWorker:
    def __init__(self) -> None:
        self.schedule_calls = 0
        self.run_calls = 0

    def schedule_tick(self) -> dict[str, object]:
        self.schedule_calls += 1
        return {"scheduled_at": "2099-01-01T00:00:00Z", "tasks": []}

    def run_once(self) -> RunOutcome:
        self.run_calls += 1
        return RunOutcome("no_task")


class WorkerCliTests(unittest.TestCase):
    def test_run_once_requires_private_runtime_inputs_as_cli_arguments(self) -> None:
        parser = build_parser()
        args = parser.parse_args(
            [
                "run-once",
                "--config", "/private/config.toml",
                "--credential", "/private/credentials.json",
                "--opencli-contract", "/private/contract.json",
                "--prompt-path", "/private/prompt.md",
                "--evidence-dir", "/private/evidence",
            ]
        )
        self.assertEqual(args.command, "run-once")
        self.assertEqual(args.prompt_path, "/private/prompt.md")

    def test_scheduled_once_asks_control_plane_for_due_ranges_without_a_local_window_key(self) -> None:
        worker = ScheduledWorker()

        self.assertEqual(_run_scheduled(worker, once=True, poll_seconds=60), 0)

        self.assertEqual(worker.schedule_calls, 1)
        self.assertEqual(worker.run_calls, 1)


if __name__ == "__main__":
    unittest.main()
