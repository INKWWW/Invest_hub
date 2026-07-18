from __future__ import annotations

import unittest

from invest_hub_worker.checkpoint import CheckpointGuard, CheckpointNotAdvanced


class CheckpointOrderTests(unittest.TestCase):
    def test_checkpoint_requires_accepted_persistence_ack(self) -> None:
        guard = CheckpointGuard(previous="cursor-1", allowed=("cursor-1", "cursor-2"))
        with self.assertRaises(CheckpointNotAdvanced):
            guard.commit("cursor-2", persistence_ack="pending")
        self.assertEqual(guard.current, "cursor-1")

    def test_checkpoint_candidate_must_be_in_current_input_range(self) -> None:
        guard = CheckpointGuard(previous=None, allowed=("cursor-1", "cursor-2"))
        with self.assertRaises(CheckpointNotAdvanced):
            guard.commit("cursor-outside", persistence_ack="accepted")

    def test_checkpoint_can_advance_only_forward_after_acceptance(self) -> None:
        guard = CheckpointGuard(previous="cursor-1", allowed=("cursor-1", "cursor-2"))
        self.assertEqual(guard.commit("cursor-2", persistence_ack="accepted"), "cursor-2")
        with self.assertRaises(CheckpointNotAdvanced):
            guard.commit("cursor-1", persistence_ack="accepted")


if __name__ == "__main__":
    unittest.main()
