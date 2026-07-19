from __future__ import annotations

import unittest

from fixtures import V1FixtureControlPlane, build_v1_fixture_worker


class ScheduleAndRecoveryTests(unittest.TestCase):
    def test_two_sources_are_scheduled_once_and_a_failure_does_not_advance_its_checkpoint(self) -> None:
        control = V1FixtureControlPlane()
        control.configure_source("source-a", worker_id="worker-a")
        control.configure_source("source-b", worker_id="worker-a")

        first = control.schedule_tick("worker-a", "2026-07-19T08:00+08:00")
        duplicate = control.schedule_tick("worker-a", "2026-07-19T08:00+08:00")

        self.assertEqual(len(first), 2)
        self.assertEqual([task["id"] for task in duplicate], [task["id"] for task in first])
        worker_a = build_v1_fixture_worker(control, source_id="source-a", failure_class="provider_failure")
        worker_b = build_v1_fixture_worker(control, source_id="source-b")

        self.assertEqual(worker_a.run_once().status, "recovering")
        self.assertEqual(worker_b.run_once().status, "succeeded")
        self.assertIsNone(control.checkpoints["source-a"])
        self.assertEqual(control.checkpoints["source-b"], "source-b-cursor-1")
        self.assertEqual(control.tasks_for("source-a")[0]["status"], "retryable_failed")

    def test_offline_recovery_enqueues_each_recent_window_once(self) -> None:
        control = V1FixtureControlPlane()
        control.configure_source("source-a", worker_id="worker-a")

        first = control.schedule_due("worker-a", "2026-07-21T20:50+08:00", "2026-07-19T20:50+08:00")
        duplicate = control.schedule_due("worker-a", "2026-07-21T20:50+08:00", "2026-07-19T20:50+08:00")

        self.assertEqual(len(first), 4)
        self.assertEqual([task["id"] for task in duplicate], [task["id"] for task in first])
        self.assertEqual(len(control.tasks_for("source-a")), 4)


if __name__ == "__main__":
    unittest.main()
