from __future__ import annotations

import unittest

from fixtures import InMemoryControlPlane


class AuthAndRLSTests(unittest.TestCase):
    def test_user_invite_is_single_use_and_user_cannot_read_admin_data(self) -> None:
        control = InMemoryControlPlane()
        code = control.create_invite("admin-1", purpose="user")

        self.assertTrue(control.consume_user_invite(code, "user-1"))
        self.assertFalse(control.consume_user_invite(code, "user-2"))
        with self.assertRaises(PermissionError):
            control.list_tasks("user-1")
        self.assertEqual(control.list_tasks("admin-1"), [])

    def test_worker_enrolment_returns_secret_but_not_code_and_replay_fails(self) -> None:
        control = InMemoryControlPlane()
        code = control.create_invite("admin-1", purpose="worker")
        credential = control.enrol_worker(code, "fixture-worker")

        self.assertTrue(credential["device_secret"])
        self.assertNotIn(code, credential.values())
        with self.assertRaises(PermissionError):
            control.list_workers("user-1")
        with self.assertRaises(ValueError):
            control.enrol_worker(code, "replayed-worker")


if __name__ == "__main__":
    unittest.main()

