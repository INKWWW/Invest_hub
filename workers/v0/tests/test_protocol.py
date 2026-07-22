from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from invest_hub_worker.errors import AlreadyEnrolled, ProtocolError
from invest_hub_worker.protocol import WorkerProtocol


class FakeTransport:
    def __init__(self, *responses: tuple[int, object]) -> None:
        self.responses = list(responses)
        self.calls: list[dict[str, object]] = []

    def __call__(self, method: str, url: str, body: object | None, headers: dict[str, str], timeout: float) -> tuple[int, object]:
        self.calls.append({"method": method, "url": url, "body": body, "headers": headers, "timeout": timeout})
        if not self.responses:
            raise AssertionError("unexpected transport call")
        return self.responses.pop(0)


def enrolment_response() -> dict[str, object]:
    return {
        "contract_version": "v0",
        "worker_id": "worker-1",
        "device_secret": "device-secret-that-is-long-enough-123456789",
        "expires_at": "2099-01-01T00:00:00Z",
    }


class WorkerProtocolTests(unittest.TestCase):
    def test_enrol_persists_secret_but_never_the_raw_code(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            credential_path = Path(directory) / "credentials.json"
            transport = FakeTransport((201, enrolment_response()))
            protocol = WorkerProtocol("https://control.example.invalid", credential_path, transport=transport)

            credential = protocol.enrol("one-time-enrolment-code")

            self.assertEqual(credential.worker_id, "worker-1")
            self.assertNotIn("one-time-enrolment-code", credential_path.read_text(encoding="utf-8"))
            self.assertEqual(os.stat(credential_path).st_mode & 0o777, 0o600)
            with self.assertRaises(AlreadyEnrolled):
                protocol.enrol("second-code")

    def test_heartbeat_and_claim_send_contract_and_bearer_secret(self) -> None:
        heartbeat = {
            "contract_version": "v0",
            "worker_id": "worker-1",
            "sent_at": "2099-01-01T00:00:00Z",
            "status": "idle",
            "capabilities": ["discord_sync"],
        }
        claim = {
            "contract_version": "v0",
            "task_id": "task-1",
            "attempt": 1,
            "task_type": "discord_sync",
            "source_id": "source-1",
            "parameter_version": "v0-default",
            "lease_expires_at": "2099-01-01T00:10:00Z",
            "safe_checkpoint": None,
        }
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()), (200, heartbeat), (200, claim))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")
            self.assertEqual(protocol.heartbeat("idle", ["discord_sync"], "2099-01-01T00:00:00Z")["status"], "idle")
            self.assertEqual(protocol.claim()["task_id"], "task-1")
            self.assertEqual(transport.calls[1]["headers"].get("Authorization"), f"Bearer {enrolment_response()['device_secret']}")
            self.assertEqual(transport.calls[1]["body"]["contract_version"], "v0")

    def test_optional_local_vercel_bypass_is_forwarded_without_persisting_it(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()))
            previous = os.environ.get("V0_VERCEL_PROTECTION_BYPASS")
            os.environ["V0_VERCEL_PROTECTION_BYPASS"] = "local-only-bypass-secret"
            try:
                protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
                protocol.enrol("one-time-enrolment-code")
            finally:
                if previous is None:
                    os.environ.pop("V0_VERCEL_PROTECTION_BYPASS", None)
                else:
                    os.environ["V0_VERCEL_PROTECTION_BYPASS"] = previous

            self.assertEqual(transport.calls[0]["headers"].get("x-vercel-protection-bypass"), "local-only-bypass-secret")
            self.assertNotIn("local-only-bypass-secret", (Path(directory) / "credentials.json").read_text(encoding="utf-8"))

    def test_empty_claim_is_none_and_invalid_response_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()), (204, None), (200, {"unexpected": True}))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")
            self.assertIsNone(protocol.claim())
            with self.assertRaises(ProtocolError):
                protocol.claim()

    def test_window_claim_preserves_nullable_coverage_state_and_resume_progress(self) -> None:
        claim = {
            "contract_version": "v0",
            "task_id": "task-window-1",
            "attempt": 1,
            "task_type": "discord_sync",
            "source_id": "source-1",
            "parameter_version": "v1.1-test",
            "lease_expires_at": "2099-01-01T00:10:00Z",
            "safe_checkpoint": "legacy-audit-only",
            "rule_snapshot": {"version": 0, "target_author_ids": []},
            "collection_scope": {"mode": "window"},
            "capture_range": {
                "mode": "window",
                "trigger": "manual",
                "timezone": "Asia/Shanghai",
                "start_at": "2099-01-01T00:00:00Z",
                "end_at": "2099-01-01T08:00:00Z",
                "scheduled_window_key": None,
            },
            "coverage_snapshot": {
                "coverage_start_at": "2099-01-01T00:00:00Z",
                "coverage_through_at": "2099-01-01T00:00:00Z",
                "last_completed_task_id": None,
            },
            "capture_progress": {"resume_cursor": None, "page_count": 0, "range_complete": False},
            "author_profile_snapshot": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()), (200, claim))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            self.assertEqual(protocol.claim()["coverage_snapshot"]["last_completed_task_id"], None)

    def test_persist_validates_contract_and_uses_the_task_scoped_endpoint(self) -> None:
        payload = {
            "contract_version": "v0",
            "task_id": "task-1",
            "attempt": 1,
            "source_id": "source-1",
            "raw_messages": [],
            "canonical_messages": [],
            "structured_runs": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"persisted": True, "idempotent": False, "structured_run_ids": []}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            acknowledgement = protocol.persist(payload)

            self.assertTrue(acknowledgement["persisted"])
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/tasks/task-1/persist"))

    def test_schedule_tick_is_authenticated_and_never_submits_a_client_window_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"scheduled_at": "2099-01-01T00:00:00Z", "tasks": [{"id": "task-1", "idempotent": False}]}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            response = protocol.schedule_tick()

            self.assertEqual(response["scheduled_at"], "2099-01-01T00:00:00Z")
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/schedule/tick"))
            self.assertEqual(transport.calls[1]["body"], {})

    def test_daily_fact_context_is_read_only_and_scoped_to_the_current_task_attempt(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"message_catalog": [], "prior_batches": []}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            self.assertEqual(protocol.get_daily_fact_context("task-window-1", 2), {"message_catalog": [], "prior_batches": []})
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/tasks/task-window-1/daily-fact-context?attempt=2"))
            self.assertIsNone(transport.calls[1]["body"])

    def test_author_profile_resolution_is_worker_scoped_and_returns_no_messages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"author_profiles": [{
                    "profile_id": "profile-1",
                    "requested_author": "Priority author",
                    "resolution_status": "resolved",
                    "author_id": "stable-author-1",
                    "author_display": "Priority author",
                    "author_handle": None,
                    "enabled": True,
                }]}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            resolved = protocol.resolve_author_profiles("task-window-1", 2)

            self.assertEqual(resolved["author_profiles"][0]["author_id"], "stable-author-1")
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/tasks/task-window-1/resolve-author-profiles"))
            self.assertEqual(transport.calls[1]["body"], {"attempt": 2})

    def test_window_page_and_range_protocols_use_task_scoped_endpoints(self) -> None:
        segment = {
            "contract_version": "v0",
            "task_id": "task-window-1",
            "attempt": 1,
            "capture_segment": {
                "idempotency_key": "page-001",
                "request_cursor": None,
                "next_cursor": "cursor-001",
                "oldest_occurred_at": "2026-07-22T00:00:00Z",
                "newest_occurred_at": "2026-07-22T08:00:00Z",
                "response_matched": True,
                "response_fresh": True,
            },
        }
        completion = {
            "contract_version": "v0",
            "task_id": "task-window-1",
            "attempt": 1,
            "range_complete": True,
            "capture_range": {
                "mode": "window",
                "trigger": "manual",
                "timezone": "Asia/Shanghai",
                "start_at": "2026-07-22T00:00:00Z",
                "end_at": "2026-07-22T08:00:00Z",
                "scheduled_window_key": None,
            },
            "boundary": {"kind": "oldest_at_or_before_start", "observed_at": "2026-07-22T00:00:00Z"},
            "summary_batch_ids": [],
            "daily_summary_ids": [],
            "no_new_data": True,
        }
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"task_id": "task-window-1", "idempotent": False, "resume_cursor": "cursor-001"}),
                (200, {"status": "succeeded", "idempotent": False, "task_id": "task-window-1", "attempt": 1}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            self.assertEqual(protocol.record_capture_segment(segment)["resume_cursor"], "cursor-001")
            self.assertEqual(protocol.complete_capture_range(completion)["status"], "succeeded")
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/tasks/task-window-1/capture-segments"))
            self.assertTrue(str(transport.calls[2]["url"]).endswith("/api/worker/tasks/task-window-1/range-complete"))


if __name__ == "__main__":
    unittest.main()
