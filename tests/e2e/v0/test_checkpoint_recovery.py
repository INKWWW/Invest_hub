from __future__ import annotations

import unittest

from fixtures import InMemoryControlPlane, build_fixture_worker, run_fixture_sync


class CheckpointRecoveryTests(unittest.TestCase):
    def test_raw_canonical_and_provider_failures_keep_checkpoint_safe(self) -> None:
        for failure_stage in ("raw", "canonical", "provider"):
            with self.subTest(failure_stage=failure_stage):
                control = InMemoryControlPlane()
                control.create_task("discord-source-1")
                _worker, protocol, execution = build_fixture_worker(control, failure_stage=failure_stage)
                claim = protocol.claim()
                self.assertIsNotNone(claim)

                failed = run_fixture_sync(control, execution, claim)

                self.assertEqual(failed["status"], "retryable_failed")
                self.assertIsNone(failed["safe_checkpoint"])
                self.assertIsNone(control.checkpoints["discord-source-1"])
                control.requeue("task-1")
                execution.failure_stage = None
                claim = protocol.claim()
                succeeded = run_fixture_sync(control, execution, claim)

                self.assertEqual(succeeded["status"], "succeeded")
                self.assertEqual(control.checkpoints["discord-source-1"], "cursor-1")
                self.assertEqual(len(execution.evidence.canonical), 2)
                expected_duplicates = 2 if failure_stage == "provider" else 0
                self.assertEqual(succeeded["duplicate_count"], expected_duplicates)

    def test_expired_lease_rejects_result_without_advancing_checkpoint(self) -> None:
        control = InMemoryControlPlane()
        control.create_task("discord-source-1")
        _worker, protocol, execution = build_fixture_worker(control)
        claim = protocol.claim()
        self.assertIsNotNone(claim)
        control.expire_lease("task-1")

        result = run_fixture_sync(control, execution, claim)

        self.assertEqual(result["status"], "retryable_failed")
        self.assertEqual(result["failure_class"], "lease_expired")
        self.assertIsNone(control.checkpoints["discord-source-1"])
        self.assertNotEqual(control.tasks["task-1"]["status"], "succeeded")


if __name__ == "__main__":
    unittest.main()
