from __future__ import annotations

import unittest
from datetime import datetime, timezone

from invest_hub_worker.scheduler import due_windows, due_x_windows, fixed_x_window, is_x_schedule_window_key


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

    def test_x_windows_use_five_fixed_boundaries_including_noon_and_twenty(self) -> None:
        coverage = datetime(2026, 7, 22, 16, tzinfo=timezone.utc)  # Shanghai midnight
        now = datetime(2026, 7, 23, 16, 5, tzinfo=timezone.utc)  # Shanghai 00:05 next day

        self.assertEqual(due_x_windows(now, coverage), (
            "2026-07-23T08:00+08:00",
            "2026-07-23T12:00+08:00",
            "2026-07-23T16:00+08:00",
            "2026-07-23T20:00+08:00",
            "2026-07-24T00:00+08:00",
        ))
        self.assertTrue(is_x_schedule_window_key("2026-07-23T12:00+08:00"))
        self.assertFalse(is_x_schedule_window_key("2026-07-23T20:50+08:00"))

    def test_fixed_x_window_uses_the_unique_previous_shanghai_cutoff(self) -> None:
        self.assertEqual(
            fixed_x_window("2026-08-18T00:00+08:00"),
            {
                "start_at": "2026-08-17T12:00:00+00:00",
                "end_at": "2026-08-17T16:00:00+00:00",
                "scheduled_window_key": "2026-08-18T00:00+08:00",
                "natural_date": "2026-08-17",
            },
        )


if __name__ == "__main__":
    unittest.main()
