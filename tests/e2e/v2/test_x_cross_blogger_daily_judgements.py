from __future__ import annotations

import unittest
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo


SHANGHAI = ZoneInfo("Asia/Shanghai")


class SyntheticScheduleStateFixture:
    """Public schedule-state contract; it does not imitate Reader routes."""

    def __init__(self) -> None:
        self.batches: dict[str, dict[str, object]] = {}

    def tick(self, cutoff_at: str) -> dict[str, object]:
        local_cutoff = datetime.fromisoformat(cutoff_at).astimezone(SHANGHAI)
        logical_date = local_cutoff.date() - timedelta(days=1) if local_cutoff.time() == time(0, 0) else local_cutoff.date()
        return self.batches.setdefault(cutoff_at, {
            "cutoff_at": cutoff_at,
            "natural_date": logical_date.isoformat(),
            "coverage_status": "complete",
            "source_snapshot": {},
            "status": "judgement_pending",
            "run_kind": "initial",
            "run_status": "queued",
            "lease": None,
            "next_attempt": 1,
            "versions": [],
            "current_revision": None,
        })

    def settle_source(self, cutoff_at: str, source_id: str, settlement_status: str, *, reason: str | None = None) -> None:
        if settlement_status not in {"included", "excluded", "no_new_information"}:
            raise ValueError("invalid_settlement_status")
        batch = self.tick(cutoff_at)
        snapshot = batch["source_snapshot"]
        assert isinstance(snapshot, dict)
        snapshot[source_id] = {"settlement_status": settlement_status, "reason": reason}
        statuses = {entry["settlement_status"] for entry in snapshot.values()}
        batch["coverage_status"] = (
            "partial" if "excluded" in statuses
            else "no_new_information" if statuses == {"no_new_information"}
            else "complete"
        )

    def claim(self, cutoff_at: str) -> dict[str, int]:
        batch = self.tick(cutoff_at)
        if batch["lease"] is not None or batch["run_status"] != "queued":
            raise ValueError("no_ready_judgement")
        attempt = batch["next_attempt"]
        assert isinstance(attempt, int)
        if attempt > 3:
            raise ValueError("no_ready_judgement")
        batch["next_attempt"] = attempt + 1
        batch["lease"] = attempt
        batch["run_status"] = "leased"
        return {"attempt": attempt}

    def expire_lease(self, cutoff_at: str, attempt: int) -> None:
        batch = self.tick(cutoff_at)
        if batch["lease"] != attempt:
            raise ValueError("stale_lease")
        batch["lease"] = None
        if attempt >= 3:
            batch["run_status"] = "failed"
            if batch["run_kind"] == "initial":
                batch["status"] = "judgement_failed"
        else:
            batch["run_status"] = "queued"

    def complete(self, cutoff_at: str, attempt: int, *, output: str | None = None) -> None:
        batch = self.tick(cutoff_at)
        if batch["lease"] != attempt:
            raise ValueError("stale_completion")
        batch["lease"] = "completed"
        batch["run_status"] = "succeeded"
        batch["status"] = "succeeded"
        versions = batch["versions"]
        assert isinstance(versions, list)
        revision = len(versions) + 1
        versions.append({"revision": revision, "output": output})
        batch["current_revision"] = revision

    def request_regeneration(self, cutoff_at: str, *, actor_role: str) -> None:
        if actor_role != "admin":
            raise PermissionError("forbidden")
        batch = self.tick(cutoff_at)
        if batch["status"] != "succeeded" or batch["run_status"] != "succeeded":
            raise ValueError("regeneration_not_available")
        batch["run_kind"] = "regeneration"
        batch["run_status"] = "queued"
        batch["lease"] = None
        batch["next_attempt"] = 1


class XCrossBloggerDailyJudgementE2ETests(unittest.TestCase):
    def test_midnight_cutoff_maps_to_prior_day_and_keeps_lagging_source_partial(self) -> None:
        fixture = SyntheticScheduleStateFixture()
        cutoff = "2026-08-01T00:00:00+08:00"

        batch = fixture.tick(cutoff)
        self.assertEqual(batch.get("natural_date"), "2026-07-31")
        fixture.settle_source(cutoff, "source-healthy", "included")
        fixture.settle_source(cutoff, "source-lagging", "excluded", reason="coverage_lagging")

        self.assertEqual(batch["coverage_status"], "partial")
        self.assertEqual(
            batch["source_snapshot"],
            {
                "source-healthy": {"settlement_status": "included", "reason": None},
                "source-lagging": {"settlement_status": "excluded", "reason": "coverage_lagging"},
            },
        )

    def test_expired_leases_stop_at_three_and_terminal_initial_failure_fails_batch(self) -> None:
        fixture = SyntheticScheduleStateFixture()
        cutoff = "2026-08-01T08:00:00+08:00"

        for expected_attempt in (1, 2, 3):
            claim = fixture.claim(cutoff)
            self.assertEqual(claim["attempt"], expected_attempt)
            fixture.expire_lease(cutoff, expected_attempt)

        batch = fixture.tick(cutoff)
        self.assertEqual(batch["run_status"], "failed")
        self.assertEqual(batch["status"], "judgement_failed")
        with self.assertRaisesRegex(ValueError, "no_ready_judgement"):
            fixture.claim(cutoff)

    def test_terminal_regeneration_failure_preserves_succeeded_revision_one(self) -> None:
        fixture = SyntheticScheduleStateFixture()
        cutoff = "2026-08-01T12:00:00+08:00"
        first_claim = fixture.claim(cutoff)
        fixture.complete(cutoff, first_claim["attempt"], output="revision one")
        fixture.request_regeneration(cutoff, actor_role="admin")

        for expected_attempt in (1, 2, 3):
            claim = fixture.claim(cutoff)
            self.assertEqual(claim["attempt"], expected_attempt)
            fixture.expire_lease(cutoff, expected_attempt)

        batch = fixture.tick(cutoff)
        self.assertEqual(batch["status"], "succeeded")
        self.assertEqual(batch["run_kind"], "regeneration")
        self.assertEqual(batch["run_status"], "failed")
        self.assertEqual(batch["versions"], [{"revision": 1, "output": "revision one"}])

    def test_admin_regeneration_appends_revision_two_without_rewriting_revision_one(self) -> None:
        fixture = SyntheticScheduleStateFixture()
        cutoff = "2026-08-01T16:00:00+08:00"
        first_claim = fixture.claim(cutoff)
        fixture.complete(cutoff, first_claim["attempt"], output="revision one")

        with self.assertRaises(PermissionError):
            fixture.request_regeneration(cutoff, actor_role="user")
        fixture.request_regeneration(cutoff, actor_role="admin")
        second_claim = fixture.claim(cutoff)
        fixture.complete(cutoff, second_claim["attempt"], output="revision two")

        batch = fixture.tick(cutoff)
        self.assertEqual(
            batch["versions"],
            [
                {"revision": 1, "output": "revision one"},
                {"revision": 2, "output": "revision two"},
            ],
        )
        self.assertEqual(batch["current_revision"], 2)

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
