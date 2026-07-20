from __future__ import annotations

import unittest
from datetime import datetime, timezone

from invest_hub_worker.scheduler import due_windows, should_enqueue


class SchedulerTests(unittest.TestCase):
    def test_each_daily_window_is_emitted_once(self) -> None:
        morning = datetime(2026, 7, 19, 0, 5, tzinfo=timezone.utc)
        morning_key = "2026-07-19T08:00+08:00"
        self.assertEqual(should_enqueue(morning, None), morning_key)
        self.assertIsNone(should_enqueue(morning, morning_key))

        evening = datetime(2026, 7, 19, 12, 51, tzinfo=timezone.utc)
        evening_key = "2026-07-19T20:50+08:00"
        self.assertEqual(should_enqueue(evening, morning_key), evening_key)
        self.assertIsNone(should_enqueue(evening, evening_key))

    def test_offline_worker_uses_the_latest_missed_window_as_one_catch_up_tick(self) -> None:
        before_morning = datetime(2026, 7, 20, 22, 30, tzinfo=timezone.utc)
        missed_evening = "2026-07-20T20:50+08:00"
        self.assertEqual(should_enqueue(before_morning, None), missed_evening)
        self.assertIsNone(should_enqueue(before_morning, missed_evening))

    def test_offline_recovery_is_bounded_to_four_windows_and_preserves_order(self) -> None:
        now = datetime(2026, 7, 21, 12, 50, tzinfo=timezone.utc)

        windows, truncated = due_windows(now, None)

        self.assertEqual(windows, (
            "2026-07-20T08:00+08:00",
            "2026-07-20T20:50+08:00",
            "2026-07-21T08:00+08:00",
            "2026-07-21T20:50+08:00",
        ))
        self.assertTrue(truncated)

        after_morning, truncated_after_morning = due_windows(now, "2026-07-21T08:00+08:00")
        self.assertEqual(after_morning, ("2026-07-21T20:50+08:00",))
        self.assertFalse(truncated_after_morning)


if __name__ == "__main__":
    unittest.main()
