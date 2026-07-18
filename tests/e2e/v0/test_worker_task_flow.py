from __future__ import annotations

import unittest

from fixtures import InMemoryControlPlane, build_fixture_worker


class WorkerTaskFlowTests(unittest.TestCase):
    def test_invite_enrol_heartbeat_claim_execute_result_succeeds(self) -> None:
        control = InMemoryControlPlane()
        control.create_task("discord-source-1")
        worker, protocol, execution = build_fixture_worker(control)

        outcome = worker.run_once()

        self.assertEqual(outcome.status, "succeeded")
        task = control.tasks["task-1"]
        self.assertEqual(task["status"], "succeeded")
        self.assertEqual(task["checkpoint"], "cursor-1")
        self.assertEqual(task["raw_count"], 2)
        self.assertEqual(task["canonical_count"], 2)
        self.assertEqual(task["duplicate_count"], 0)
        self.assertEqual(task["unresolved_count"], 1)
        self.assertEqual(task["unparsed_media_count"], 1)
        self.assertEqual(len(task["structured_run_ids"]), 1)
        evidence = control.evidence_refs[task["structured_run_ids"][0]]
        self.assertEqual(evidence["canonical_message_ids"], ["message-1", "message-2"])
        self.assertEqual(evidence["media_source_message_ids"], ["message-2"])
        self.assertTrue(protocol.credential)
        self.assertGreater(execution.calls, 0)
        self.assertNotIn("fixture-enrolment-code", protocol.credential_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
