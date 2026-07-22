from __future__ import annotations

import unittest
from datetime import datetime, timezone

from invest_hub_worker.scheduler import due_windows


class SchedulerTests(unittest.TestCase):
    def test_all_four_shanghai_boundaries_are_due_in_order(self) -> None:
        coverage = datetime(2026, 7, 19, 15, 50, tzinfo=timezone.utc)
        now = datetime(2026, 7, 20, 13, 0, tzinfo=timezone.utc)

        self.assertEqual(due_windows(now, coverage), (
            "2026-07-20T00:00+08:00",
            "2026-07-20T08:00+08:00",
            "2026-07-20T16:00+08:00",
            "2026-07-20T20:50+08:00",
        ))

    def test_offline_recovery_returns_all_twenty_missed_windows_without_a_cap(self) -> None:
        coverage = datetime(2026, 7, 16, 15, 50, tzinfo=timezone.utc)
        now = datetime(2026, 7, 21, 13, tzinfo=timezone.utc)

        windows = due_windows(now, coverage)

        self.assertEqual(len(windows), 20)
        self.assertEqual(windows[0], "2026-07-17T00:00+08:00")
        self.assertEqual(windows[-1], "2026-07-21T20:50+08:00")


if __name__ == "__main__":
    unittest.main()
