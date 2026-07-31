from __future__ import annotations

import unittest


class SyntheticScheduleStateFixture:
    """Public schedule-state contract; it does not imitate Reader routes."""

    def __init__(self) -> None:
        self.batches: dict[str, dict[str, object]] = {}

    def tick(self, cutoff_at: str) -> dict[str, object]:
        return self.batches.setdefault(cutoff_at, {"cutoff_at": cutoff_at, "lease": None, "next_attempt": 1})

    def claim(self, cutoff_at: str) -> dict[str, int]:
        batch = self.tick(cutoff_at)
        if batch["lease"] is not None:
            raise ValueError("no_ready_judgement")
        attempt = batch["next_attempt"]
        assert isinstance(attempt, int)
        batch["next_attempt"] = attempt + 1
        batch["lease"] = attempt
        return {"attempt": attempt}

    def expire_lease(self, cutoff_at: str, attempt: int) -> None:
        batch = self.tick(cutoff_at)
        if batch["lease"] != attempt:
            raise ValueError("stale_lease")
        batch["lease"] = None

    def complete(self, cutoff_at: str, attempt: int) -> None:
        batch = self.tick(cutoff_at)
        if batch["lease"] != attempt:
            raise ValueError("stale_completion")
        batch["lease"] = "completed"


class XCrossBloggerDailyJudgementE2ETests(unittest.TestCase):
    def test_duplicate_ticks_share_schedule_state_and_expired_lease_cannot_complete(self) -> None:
        fixture = SyntheticScheduleStateFixture()
        cutoff = "2026-08-01T08:00:00+08:00"

        first_batch = fixture.tick(cutoff)
        self.assertIs(first_batch, fixture.tick(cutoff))
        first_attempt = fixture.claim(cutoff)
        fixture.expire_lease(cutoff, first_attempt["attempt"])
        second_attempt = fixture.claim(cutoff)

        self.assertEqual(second_attempt["attempt"], 2)
        with self.assertRaisesRegex(ValueError, "stale_completion"):
            fixture.complete(cutoff, first_attempt["attempt"])
        fixture.complete(cutoff, second_attempt["attempt"])


if __name__ == "__main__":
    unittest.main()
