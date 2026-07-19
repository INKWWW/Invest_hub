from __future__ import annotations

import unittest

from fixtures import V1FixtureControlPlane, build_v1_fixture_worker


class MultiSourceReaderFlowTests(unittest.TestCase):
    def test_admin_configuration_worker_summary_reader_and_permission_boundaries(self) -> None:
        control = V1FixtureControlPlane()
        control.configure_source("source-a", worker_id="worker-a", target_authors=("author-a",))
        control.configure_source("source-b", worker_id="worker-b", target_authors=("author-b",))
        control.schedule_tick("worker-a", "2026-07-19T08:00+08:00")
        control.schedule_tick("worker-b", "2026-07-19T08:00+08:00")

        self.assertEqual(build_v1_fixture_worker(control, source_id="source-a").run_once().status, "succeeded")
        self.assertEqual(build_v1_fixture_worker(control, source_id="source-b").run_once().status, "succeeded")

        days = control.read_as_user("user-1")
        self.assertEqual([day["source_key"] for day in days], ["source-a", "source-b"])
        self.assertTrue(all(day["daily_summary"]["version"] == 1 for day in days))
        self.assertTrue(all(day["batches"] for day in days))
        self.assertNotIn("local_raw_ref", str(days))
        with self.assertRaises(PermissionError):
            control.list_admin_tasks("user-1")


if __name__ == "__main__":
    unittest.main()
