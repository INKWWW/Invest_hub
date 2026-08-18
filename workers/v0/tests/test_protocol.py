from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from invest_hub_worker.errors import AlreadyEnrolled, ProtocolError, RemoteConflict
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


def valid_v4_completion() -> dict[str, object]:
    return {
        "run_id": "judgement-run-1", "attempt": 1,
        "schema_version": "v4-x-cross-blogger", "provider": "codex_cli",
        "model_reported": None, "prompt_version": "v4-x-cross-blogger-1",
        "security_industry_viewpoints": [{
            "statement": "博主对公开 fixture 标的表达了条件性观点。",
            "action_intent": "watch", "action_scope_status": "specified", "action_scope": "公开 fixture 标的", "conditions": ["等待公开条件确认"],
            "supporting_source_ids": ["source-a"], "dissenting_source_ids": [],
            "analysis_ids": ["post-a@1"], "evidence_post_ids": ["post-a"], "uncertainties": [],
        }],
        "market_structure_viewpoints": [], "strategy_mindset_viewpoints": [],
        "uncertainties": ["公开 fixture 的覆盖限制"],
    }


def valid_v4_context() -> dict[str, object]:
    return {
        "run_id": "judgement-run-1", "batch_id": "batch-1", "attempt": 1,
        "prompt_version": "v4-x-cross-blogger-1",
        "sources": [{"source_id": "source-a", "display_name": "A", "window_segments": [{
            "id": "segment-1", "schema_version": "v4-x-window", "prompt_version": "v4-x-window-1",
            "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z",
            "segment_output": {
                "schema_version": "v4-x-window", "analysis_ids": ["post-a@2"], "evidence_post_ids": ["post-a"],
            },
            "analyses": [{
                "analysis_id": "post-a@2", "schema_version": "v4-x-post-analysis", "prompt_version": "v4-x-post-analysis-1",
                "analysis_output": {"post_id": "post-a", "evidence_post_ids": ["post-a"]}, "evidence_post_ids": ["post-a"],
            }],
        }]}],
        "excluded_sources": [{"source_id": "source-z", "display_name": "Z", "reason": "no_new_information"}],
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
                "trigger": "recovery",
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

            recovered_claim = protocol.claim()
            self.assertEqual(recovered_claim["coverage_snapshot"]["last_completed_task_id"], None)
            self.assertEqual(recovered_claim["capture_range"]["trigger"], "recovery")

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

    def test_x_activation_protocols_use_worker_only_endpoints(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"activation": {"source_id": "source-x", "requested_handle": "fixture", "parameter_version": "x-standard-v2", "initial_end_at": "2099-01-01T08:00:00Z", "idempotent": False}}),
                (200, {"activation": {"task_id": "task-x", "source_id": "source-x", "initial_end_at": "2099-01-01T08:00:00Z", "idempotent": False}}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            activation = protocol.claim_x_activation()
            initialized = protocol.initialize_x_activation("source-x")

            self.assertEqual(activation["requested_handle"], "fixture")
            self.assertEqual(initialized["task_id"], "task-x")
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/x-activations/claim"))
            self.assertTrue(str(transport.calls[2]["url"]).endswith("/api/worker/x-activations/source-x/initialize"))

    def test_fixed_window_creation_uses_the_activated_source_identity_and_cutoff(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"id": "task-x-window", "source_id": "source-x", "idempotent": False, "demo_fixed_window": {"natural_date": "2099-01-01"}}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            task = protocol.create_x_demo_fixed_window_task("source-x", "2099-01-01T16:00:00+08:00", "fixture-account")

            self.assertEqual(task["id"], "task-x-window")
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/x-fixed-windows"))
            self.assertEqual(transport.calls[1]["body"], {
                "source_id": "source-x", "cutoff_at": "2099-01-01T16:00:00+08:00", "account_id": "fixture-account",
            })

    def test_fixed_window_claim_is_bound_to_the_created_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"contract_version": "v0", "task_id": "task-x-window", "attempt": 1, "task_type": "x_sync", "source_id": "source-x", "parameter_version": "x-standard-v2", "lease_expires_at": "2099-01-01T00:10:00Z", "safe_checkpoint": None, "rule_snapshot": {"version": 0, "target_author_ids": []}, "collection_scope": {"mode": "window"}, "capture_range": {"mode": "window", "trigger": "scheduled", "timezone": "Asia/Shanghai", "start_at": "2099-01-01T00:00:00Z", "end_at": "2099-01-01T08:00:00Z", "scheduled_window_key": "2099-01-01T16:00+08:00", "overlap_start_at": "2099-01-01T00:00:00Z"}, "coverage_snapshot": {"coverage_start_at": "2099-01-01T00:00:00Z", "coverage_through_at": "2099-01-01T00:00:00Z", "last_completed_task_id": None}, "capture_progress": {"resume_cursor": None, "page_count": 0, "range_complete": False}, "author_profile_snapshot": [], "source_snapshot": {"source_type": "x", "account_id": "fixture-account", "display_name": "Fixture", "parameter_version": "x-standard-v2"}}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            claim = protocol.claim_x_demo_fixed_window_task("task-x-window")

            self.assertEqual(claim["task_id"], "task-x-window")
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/x-fixed-windows/task-x-window/claim"))
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

    def test_x_identity_resolution_uses_only_the_safe_identity_endpoint_and_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()),
                (200, {"identity": {
                    "resolution_status": "resolved",
                    "parameter_version": "v2-test",
                    "idempotent": False,
                }}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            identity = protocol.resolve_x_source_identity("x-source", "v2-test", "fixture_handle")

            self.assertEqual(identity, {
                "resolution_status": "resolved",
                "parameter_version": "v2-test",
                "idempotent": False,
            })
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/x-sources/x-source/resolve-identity"))
            self.assertEqual(transport.calls[1]["body"], {"parameter_version": "v2-test", "account_id": "fixture_handle"})
            self.assertEqual(transport.calls[1]["headers"].get("Authorization"), f"Bearer {enrolment_response()['device_secret']}")

    def test_x_identity_resolution_rejects_extra_response_fields_and_maps_conflict(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            credential_path = Path(directory) / "credentials.json"
            invalid = WorkerProtocol(
                "https://control.example.invalid", credential_path,
                transport=FakeTransport(
                    (201, enrolment_response()),
                    (200, {"identity": {
                        "resolution_status": "resolved", "parameter_version": "v2-test", "idempotent": False, "account_id": "fixture_handle",
                    }}),
                ),
            )
            invalid.enrol("one-time-enrolment-code")
            with self.assertRaisesRegex(ProtocolError, "invalid x identity resolution response"):
                invalid.resolve_x_source_identity("x-source", "v2-test", "fixture_handle")

            conflict = WorkerProtocol(
                "https://control.example.invalid", Path(directory) / "conflict.json",
                transport=FakeTransport((201, enrolment_response()), (409, {"error": "x_identity_conflict"})),
            )
            conflict.enrol("one-time-enrolment-code")
            with self.assertRaisesRegex(RemoteConflict, "x_identity_conflict"):
                conflict.resolve_x_source_identity("x-source", "v2-test", "fixture_handle")

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
            self.assertEqual(transport.calls[1]["timeout"], 30.0)
            self.assertEqual(transport.calls[2]["timeout"], 110.0)

    def test_x_daily_judgement_protocol_uses_only_safe_worker_endpoints(self) -> None:
        claim = {
            "run_id": "judgement-run-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z",
            "batch": {"id": "batch-1", "natural_date": "2099-01-01", "cutoff_at": "2099-01-01T08:00:00Z", "coverage_status": "complete"},
        }
        context = valid_v4_context()
        completion = valid_v4_completion()
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()), (200, claim), (200, context), (200, {"status": "succeeded"}), (200, {"status": "retryable_failed"}))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            self.assertEqual(protocol.claim_x_daily_judgement()["run_id"], "judgement-run-1")
            parsed_context = protocol.get_x_daily_judgement_context("judgement-run-1", 1)
            self.assertEqual(parsed_context["batch_id"], "batch-1")
            self.assertEqual(parsed_context["sources"][0]["source_id"], "source-a")
            self.assertEqual(protocol.complete_x_daily_judgement(completion)["status"], "succeeded")
            self.assertEqual(protocol.fail_x_daily_judgement("judgement-run-1", 1, "provider_failure")["status"], "retryable_failed")
            self.assertTrue(str(transport.calls[1]["url"]).endswith("/api/worker/x-daily-judgements/claim"))
            self.assertEqual(transport.calls[1]["body"], {})
            self.assertTrue(str(transport.calls[2]["url"]).endswith("/api/worker/x-daily-judgements/judgement-run-1/context"))
            self.assertEqual(transport.calls[2]["body"], {"attempt": 1})
            self.assertTrue(str(transport.calls[3]["url"]).endswith("/api/worker/x-daily-judgements/judgement-run-1/complete"))
            self.assertTrue(str(transport.calls[4]["url"]).endswith("/api/worker/x-daily-judgements/judgement-run-1/failure"))

    def test_x_daily_judgement_completion_rejects_unsafe_item_before_transport(self) -> None:
        completion = valid_v4_completion()
        completion["security_industry_viewpoints"] = [{"statement": "only this"}]
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            with self.assertRaisesRegex(ProtocolError, "invalid x daily judgement completion"):
                protocol.complete_x_daily_judgement(completion)

            self.assertEqual(len(transport.calls), 1)

    def test_x_daily_judgement_completion_rejects_unsafe_model_telemetry_before_transport(self) -> None:
        completion = valid_v4_completion()
        completion["model_reported"] = "C:\\private\\model"
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            with self.assertRaisesRegex(ProtocolError, "invalid x daily judgement completion"):
                protocol.complete_x_daily_judgement(completion)

            self.assertEqual(len(transport.calls), 1)

    def test_x_daily_judgement_completion_rejects_non_string_top_level_uncertainty_before_transport(self) -> None:
        completion = valid_v4_completion()
        completion["uncertainties"] = [1]
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            with self.assertRaisesRegex(ProtocolError, "invalid x daily judgement completion"):
                protocol.complete_x_daily_judgement(completion)

            self.assertEqual(len(transport.calls), 1)

    def test_x_daily_judgement_protocol_rejects_v2_context_and_completion_before_transport(self) -> None:
        v2_context = {
            "run_id": "judgement-run-1", "batch_id": "batch-1", "attempt": 1,
            "prompt_version": "v2-x-cross-blogger-1", "sources": [], "excluded_sources": [],
        }
        v2_completion = {
            "run_id": "judgement-run-1", "attempt": 1, "schema_version": "v2-x-cross-blogger", "provider": "codex_cli",
            "model_reported": None, "prompt_version": "v2-x-cross-blogger-1", "stock_viewpoints": [],
            "market_industry_viewpoints": [], "uncertainties": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport((201, enrolment_response()), (200, v2_context))
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            with self.assertRaisesRegex(ProtocolError, "invalid x daily judgement context"):
                protocol.get_x_daily_judgement_context("judgement-run-1", 1)
            with self.assertRaisesRegex(ProtocolError, "invalid x daily judgement completion"):
                protocol.complete_x_daily_judgement(v2_completion)

            self.assertEqual(len(transport.calls), 2)

    def test_x_verification_replay_protocol_uses_only_replay_scoped_endpoints(self) -> None:
        replay_id = "11111111-1111-4111-8111-111111111111"
        context = {
            "replay_id": replay_id, "attempt": 1, "sources": [{
                "source_id": "source-a", "display_name": "A", "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z", "posts": [{
                    "post_id": "post-a", "content": "fixture", "occurred_at": "2099-01-01T01:00:00Z", "post_url": "https://x.com/a/status/post-a", "post_type": "original",
                    "quoted_post_id": None, "reply_to_post_id": None, "reposted_post_id": None, "context_status": "complete", "attachments": [],
                }],
            }],
        }
        completion = {
            "replay_id": replay_id, "attempt": 1, "provider": "codex_cli", "model_reported": None,
            "sources": [{"source_id": "source-a", "analyses": [{
                "post_id": "post-a", "analysis_id": "post-a@2", "analysis_version": 2, "schema_version": "v3-x-post-analysis", "prompt_version": "v3-x-post-analysis-1",
                "analysis_output": {"post_id": "post-a"}, "blogger_viewpoint": None, "arguments": [], "quoted_post_viewpoint": None, "uncertainties": [], "evidence_post_ids": ["post-a"], "post_link": "https://x.com/a/status/post-a",
            }], "segment": {"occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z", "schema_version": "v3-x-window", "prompt_version": "v3-x-window-1", "segment_output": {"schema_version": "v3-x-window"}, "analysis_ids": ["post-a@2"], "evidence_post_ids": ["post-a"], "uncertainties": []}}],
            "daily": {"schema_version": "v3-x-cross-blogger", "prompt_version": "v3-x-cross-blogger-1", "security_industry_viewpoints": [], "market_structure_viewpoints": [], "strategy_mindset_viewpoints": [], "uncertainties": []},
        }
        with tempfile.TemporaryDirectory() as directory:
            transport = FakeTransport(
                (201, enrolment_response()), (200, {"replay_id": replay_id, "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z"}),
                (200, context), (200, {"status": "succeeded"}), (200, {"status": "failed"}),
            )
            protocol = WorkerProtocol("https://control.example.invalid", Path(directory) / "credentials.json", transport=transport)
            protocol.enrol("one-time-enrolment-code")

            self.assertEqual(protocol.claim_x_v3_verification_replay(replay_id)["attempt"], 1)
            self.assertEqual(protocol.get_x_v3_verification_replay_context(replay_id, 1)["sources"][0]["posts"][0]["post_id"], "post-a")
            self.assertEqual(protocol.complete_x_v3_verification_replay(completion)["status"], "succeeded")
            self.assertEqual(protocol.fail_x_v3_verification_replay(replay_id, 1, "schema_error")["status"], "failed")
            self.assertTrue(str(transport.calls[1]["url"]).endswith(f"/api/worker/x-v3-verification-replays/{replay_id}/claim"))
            self.assertTrue(str(transport.calls[2]["url"]).endswith(f"/api/worker/x-v3-verification-replays/{replay_id}/context"))
            self.assertTrue(str(transport.calls[3]["url"]).endswith(f"/api/worker/x-v3-verification-replays/{replay_id}/complete"))
            self.assertTrue(str(transport.calls[4]["url"]).endswith(f"/api/worker/x-v3-verification-replays/{replay_id}/failure"))


if __name__ == "__main__":
    unittest.main()
