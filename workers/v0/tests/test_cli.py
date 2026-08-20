from __future__ import annotations

import contextlib
import io
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from invest_hub_worker.cli import (
    IdentityResolutionError,
    _append_identity_evidence,
    _require_controlled_x_opencli_executable,
    _prepare_identity_evidence_dir,
    _run_scheduled,
    run_one_x_fixed_window,
    _scheduled_sleep_seconds,
    build_parser,
    main,
)
from invest_hub_worker.config import LocalWorkerConfig, LocalWorkerConfigSet
from invest_hub_worker.errors import ProtocolError
from invest_hub_worker.worker import RunOutcome


class ScheduledWorker:
    def __init__(self) -> None:
        self.schedule_calls = 0
        self.run_calls = 0
        self.judgement_calls = 0

    def schedule_tick(self) -> dict[str, object]:
        self.schedule_calls += 1
        return {"scheduled_at": "2099-01-01T00:00:00Z", "tasks": []}

    def run_once(self) -> RunOutcome:
        self.run_calls += 1
        return RunOutcome("no_task")

    def run_x_daily_judgement_once(self, _runtime: object) -> RunOutcome:
        self.judgement_calls += 1
        return RunOutcome("succeeded", "judgement-run-1")


class FixedWindowWorker:
    def __init__(self) -> None:
        self.protocol = FixedWindowProtocol()
        self.capabilities = ["x_sync"]
        self.calls: list[str] = []

    def run_once(self) -> RunOutcome:
        raise AssertionError("generic claim must not be used for an explicit fixed window")

    def run_once_for_task(self, task_id: str) -> RunOutcome:
        self.calls.append(f"claim:{task_id}")
        return RunOutcome("succeeded", task_id)


class FixedWindowProtocol:
    def __init__(self) -> None:
        self.events: list[object] = []

    def heartbeat(self, *_args: object) -> dict[str, object]:
        self.events.append("heartbeat")
        return {"status": "idle"}

    def claim_x_activation(self) -> dict[str, object]:
        self.events.append("claim_activation")
        return {"source_id": "source-x", "requested_handle": "fixture", "parameter_version": "x-standard-v2", "initial_end_at": "2099-01-01T08:00:00Z", "idempotent": False}

    def resolve_x_source_identity(self, source_id: str, parameter_version: str, account_id: str) -> dict[str, object]:
        self.events.append(("resolve", source_id, parameter_version, account_id))
        return {"resolution_status": "resolved", "parameter_version": parameter_version, "idempotent": False}

    def initialize_x_activation(self, source_id: str) -> dict[str, object]:
        self.events.append(("initialize", source_id))
        return {"task_id": None, "source_id": source_id, "initial_end_at": "2099-01-01T08:00:00Z", "idempotent": False}

    def create_x_demo_fixed_window_task(self, source_id: str, cutoff_at: str, account_id: str) -> dict[str, object]:
        self.events.append(("create", source_id, cutoff_at, account_id))
        return {"id": "task-fixed", "source_id": source_id, "idempotent": False, "demo_fixed_window": {}}


class FixedWindowInvoker:
    def resolve(self, handle: str) -> str:
        self.handle = handle
        return "fixture-account"


class ScheduleFailingWorker(ScheduledWorker):
    def schedule_tick(self) -> dict[str, object]:
        self.schedule_calls += 1
        raise ProtocolError("schedule_tick_failed")


class JudgementDispatchFailingWorker(ScheduledWorker):
    def schedule_tick(self) -> dict[str, object]:
        self.schedule_calls += 1
        return {
            "scheduled_at": "2099-01-01T00:00:00Z",
            "tasks": [],
            "judgement_dispatch_failed": True,
            "private_dispatch_detail": "/private/dispatcher/error.json",
        }


class WorkerCliTests(unittest.TestCase):
    def test_sequential_cli_preserves_safe_protocol_status_and_error_code(self) -> None:
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{
                "source_id": "x-source", "source_type": "x", "source_url": "https://x.com/fixture_handle",
                "profile_ref": "/private/profile", "opencli_contract_version": "v2", "parameter_version": "x-standard-v2",
            }],
        })
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"V2_REAL_X_ACK": "authorized"}, clear=False):
            with patch("invest_hub_worker.cli.LocalWorkerConfigSet.load", return_value=config), \
                 patch("invest_hub_worker.cli.WorkerProtocol", return_value=SimpleNamespace(credential=object())), \
                 patch("invest_hub_worker.cli.build_authorized_runtime_set", return_value=SimpleNamespace(execute=lambda *_args: None, execute_windowed=lambda *_args: None)), \
                 patch("invest_hub_worker.cli.build_authorized_x_daily_judgement_runtime", return_value=None), \
                 patch("invest_hub_worker.cli.Worker", return_value=object()), \
                 patch("invest_hub_worker.cli.run_sequential_x_fixed_window", side_effect=ProtocolError("x_demo_fixed_window_run_failed", status=503)), \
                 contextlib.redirect_stdout(output):
                code = main([
                    "run-x-fixed-window-sequential", "--config", "/private/config.toml", "--credential", "/private/credential.json",
                    "--opencli-contract", "/private/contract.json", "--prompt-path", "/private/prompt.md",
                    "--evidence-dir", str(Path(directory) / "evidence"), "--cutoff", "2026-08-20T20:00:00+08:00",
                    "--opencli-executable", "/private/opencli",
                ])

        self.assertEqual(code, 1)
        self.assertEqual(json.loads(output.getvalue()), {
            "status": "failed", "error": "ProtocolError", "http_status": 503,
            "error_code": "x_demo_fixed_window_run_failed",
        })

    def test_sequential_cli_does_not_emit_private_protocol_error_details(self) -> None:
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{
                "source_id": "x-source", "source_type": "x", "source_url": "https://x.com/fixture_handle",
                "profile_ref": "/private/profile", "opencli_contract_version": "v2", "parameter_version": "x-standard-v2",
            }],
        })
        output = io.StringIO()
        private_detail = "secret_token"
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"V2_REAL_X_ACK": "authorized"}, clear=False):
            with patch("invest_hub_worker.cli.LocalWorkerConfigSet.load", return_value=config), \
                 patch("invest_hub_worker.cli.WorkerProtocol", return_value=SimpleNamespace(credential=object())), \
                 patch("invest_hub_worker.cli.build_authorized_runtime_set", return_value=SimpleNamespace(execute=lambda *_args: None, execute_windowed=lambda *_args: None)), \
                 patch("invest_hub_worker.cli.build_authorized_x_daily_judgement_runtime", return_value=None), \
                 patch("invest_hub_worker.cli.Worker", return_value=object()), \
                 patch("invest_hub_worker.cli.run_sequential_x_fixed_window", side_effect=ProtocolError(private_detail, status=503)), \
                 contextlib.redirect_stdout(output):
                code = main([
                    "run-x-fixed-window-sequential", "--config", "/private/config.toml", "--credential", "/private/credential.json",
                    "--opencli-contract", "/private/contract.json", "--prompt-path", "/private/prompt.md",
                    "--evidence-dir", str(Path(directory) / "evidence"), "--cutoff", "2026-08-20T20:00:00+08:00",
                    "--opencli-executable", "/private/opencli",
                ])

        self.assertEqual(code, 1)
        self.assertEqual(json.loads(output.getvalue()), {"status": "failed", "error": "ProtocolError"})
        self.assertNotIn(private_detail, output.getvalue())

    def test_agent_demo_parser_requires_one_run_and_isolated_inputs(self) -> None:
        parser = build_parser()
        args = parser.parse_args([
            "run-agent-demo",
            "--control-plane-url", "https://control.example.invalid",
            "--credential", "/private/credentials.json",
            "--bundle", "/private/skills",
            "--run-root", "/private/runs",
            "--run-id", "00000000-0000-0000-0000-000000000101",
        ])
        self.assertEqual(args.command, "run-agent-demo")
        self.assertEqual(args.provider, "codex_cli")
        self.assertEqual(args.timeout_seconds, 360.0)

    def test_agent_demo_worker_parser_supports_polling_without_a_run_id(self) -> None:
        parser = build_parser()
        args = parser.parse_args([
            "run-agent-demo-worker",
            "--control-plane-url", "https://control.example.invalid",
            "--credential", "/private/credentials.json",
            "--bundle", "/private/skills",
            "--run-root", "/private/runs",
        ])
        self.assertEqual(args.command, "run-agent-demo-worker")
        self.assertEqual(args.poll_seconds, 5)
        self.assertFalse(args.once)
        self.assertEqual(args.timeout_seconds, 360.0)

    def test_fixed_window_orchestration_activates_creates_then_runs_one_claim(self) -> None:
        worker = FixedWindowWorker()
        source = LocalWorkerConfig.from_mapping({
            "control_plane_url": "https://control.example.invalid", "source_id": "source-x", "source_type": "x",
            "source_url": "https://x.com/fixture", "profile_ref": "/synthetic/profile", "opencli_contract_version": "v2",
            "parameter_version": "x-standard-v2",
        })

        outcome = run_one_x_fixed_window(worker, source, "2099-01-01T16:00:00+08:00", FixedWindowInvoker())

        self.assertEqual(outcome.status, "succeeded")
        self.assertEqual(worker.protocol.events, [
            "heartbeat", "claim_activation", ("resolve", "source-x", "x-standard-v2", "fixture-account"),
            ("initialize", "source-x"), ("create", "source-x", "2099-01-01T16:00:00+08:00", "fixture-account"),
        ])
        self.assertEqual(worker.calls, ["claim:task-fixed"])

    def test_run_once_requires_private_runtime_inputs_as_cli_arguments(self) -> None:
        parser = build_parser()
        args = parser.parse_args(
            [
                "run-once",
                "--config", "/private/config.toml",
                "--credential", "/private/credentials.json",
                "--opencli-contract", "/private/contract.json",
                "--prompt-path", "/private/prompt.md",
                "--evidence-dir", "/private/evidence",
            ]
        )
        self.assertEqual(args.command, "run-once")
        self.assertEqual(args.prompt_path, "/private/prompt.md")

    def test_scheduled_once_asks_control_plane_for_due_ranges_without_a_local_window_key(self) -> None:
        worker = ScheduledWorker()

        with patch("builtins.print") as emit:
            self.assertEqual(_run_scheduled(worker, once=True, poll_seconds=60, judgement_runtime=object()), 0)

        self.assertEqual(worker.schedule_calls, 1)
        self.assertEqual(worker.run_calls, 1)
        self.assertEqual(worker.judgement_calls, 1)
        self.assertTrue(emit.call_args.kwargs["flush"])

    def test_scheduled_output_keeps_safe_judgement_dispatch_failure_without_details(self) -> None:
        worker = JudgementDispatchFailingWorker()

        with patch("builtins.print") as emit:
            self.assertEqual(_run_scheduled(worker, once=True, poll_seconds=60), 0)

        output = json.loads(emit.call_args.args[0])
        self.assertEqual(output["judgement_dispatch_failed"], True)
        self.assertNotIn("private_dispatch_detail", output)
        self.assertNotIn("/private/dispatcher/error.json", json.dumps(output))

    def test_scheduled_x_failure_uses_a_bounded_backoff_before_the_next_claim(self) -> None:
        self.assertEqual(_scheduled_sleep_seconds(RunOutcome("recovering", "task-1"), 60), 300)
        self.assertEqual(_scheduled_sleep_seconds(RunOutcome("no_task"), 60), 60)

    def test_schedule_failure_still_attempts_to_recover_an_existing_task(self) -> None:
        worker = ScheduleFailingWorker()

        with patch("builtins.print"):
            self.assertEqual(_run_scheduled(worker, once=True, poll_seconds=60), 0)

        self.assertEqual(worker.schedule_calls, 1)
        self.assertEqual(worker.run_calls, 1)

    def test_resolve_x_identity_parser_requires_only_identity_inputs(self) -> None:
        parser = build_parser()
        args = parser.parse_args([
            "resolve-x-identity",
            "--config", "/private/config.toml",
            "--credential", "/private/credentials.json",
            "--source-id", "x-source",
            "--opencli-executable", "/private/opencli",
            "--evidence-dir", "/private/evidence",
            "--worker-name", "fixture-worker",
        ])
        self.assertEqual(args.command, "resolve-x-identity")
        self.assertFalse(hasattr(args, "prompt_path"))
        self.assertFalse(hasattr(args, "opencli_contract"))

    def test_resolve_x_identity_prints_only_safe_result_and_writes_minimal_evidence(self) -> None:
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{
                "source_id": "x-source", "source_type": "x", "source_url": "https://x.com/fixture_handle",
                "profile_ref": "/private/profile", "opencli_contract_version": "v2", "parameter_version": "v2-test",
            }],
        })
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"V2_REAL_X_ACK": "authorized"}, clear=False):
            evidence_dir = Path(directory) / "evidence"
            with patch("invest_hub_worker.cli.LocalWorkerConfigSet.load", return_value=config), \
                 patch("invest_hub_worker.cli.WorkerProtocol") as protocol_type, \
                 patch("invest_hub_worker.cli.resolve_configured_x_identity", return_value={
                     "resolution_status": "resolved", "parameter_version": "v2-test", "idempotent": False,
                 }) as resolve, \
                 patch("invest_hub_worker.cli._require_controlled_x_opencli_executable", return_value="/private/opencli"), \
                 patch("invest_hub_worker.cli.Worker", side_effect=AssertionError("Worker must not be constructed")), \
                 patch("invest_hub_worker.cli.build_authorized_runtime_set", side_effect=AssertionError("runtime must not be built")), \
                 contextlib.redirect_stdout(output):
                code = main([
                    "resolve-x-identity", "--config", "/private/config.toml", "--credential", "/private/credential.json",
                    "--source-id", "x-source", "--opencli-executable", "/private/opencli", "--evidence-dir", str(evidence_dir),
                ])

            self.assertEqual(code, 0)
            self.assertEqual(resolve.call_count, 1)
            self.assertEqual(protocol_type.call_count, 1)
            result = json.loads(output.getvalue())
            self.assertEqual(set(result), {"status", "resolution_status", "idempotent", "error"})
            self.assertEqual(result, {"status": "resolved", "resolution_status": "resolved", "idempotent": False, "error": None})
            self.assertNotIn("x-source", output.getvalue())
            self.assertNotIn("fixture_handle", output.getvalue())
            lines = (evidence_dir / "x-identity-events.jsonl").read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            event = json.loads(lines[0])
            self.assertEqual(set(event), {"occurred_at", "contract_version", "result_code"})
            self.assertEqual(event["contract_version"], "v2")
            self.assertEqual(event["result_code"], "resolved")
            self.assertEqual(stat.S_IMODE(evidence_dir.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((evidence_dir / "x-identity-events.jsonl").stat().st_mode), 0o600)

    def test_resolve_x_identity_rejects_an_arbitrary_executable_before_protocol_or_profile_resolution(self) -> None:
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{
                "source_id": "x-source", "source_type": "x", "source_url": "https://x.com/fixture_handle",
                "profile_ref": "/private/profile", "opencli_contract_version": "v2", "parameter_version": "v2-test",
            }],
        })
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"V2_REAL_X_ACK": "authorized"}, clear=False):
            controlled = Path(directory) / "controlled-opencli"
            controlled.write_text("fixture", encoding="utf-8")
            controlled.chmod(0o700)
            evidence_dir = Path(directory) / "evidence"
            with patch("invest_hub_worker.cli.LocalWorkerConfigSet.load", return_value=config), \
                 patch("invest_hub_worker.cli._controlled_x_opencli_executable", return_value=controlled), \
                 patch("invest_hub_worker.cli.WorkerProtocol", side_effect=AssertionError("protocol must not be constructed")), \
                 patch("invest_hub_worker.cli.resolve_configured_x_identity", side_effect=AssertionError("profile must not resolve")), \
                 contextlib.redirect_stdout(output):
                code = main([
                    "resolve-x-identity", "--config", "/private/config.toml", "--credential", "/private/credential.json",
                    "--source-id", "x-source", "--opencli-executable", "/private/arbitrary-opencli", "--evidence-dir", str(evidence_dir),
                ])

            self.assertEqual(code, 1)
            self.assertEqual(json.loads(output.getvalue()), {
                "status": "failed", "resolution_status": None, "idempotent": False,
                "error": "controlled_opencli_required",
            })

    def test_controlled_opencli_requirement_accepts_only_the_canonical_runtime_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory) / ".runtime" / "v2" / "opencli-collection"
            release = runtime / "release"
            executable = release / "bin" / "opencli-v2-collection"
            executable.parent.mkdir(parents=True)
            executable.write_text("fixture", encoding="utf-8")
            executable.chmod(0o700)
            current = runtime / "current"
            current.symlink_to(release, target_is_directory=True)
            canonical = current / "bin" / "opencli-v2-collection"
            with patch("invest_hub_worker.cli._controlled_x_opencli_executable", return_value=canonical):
                self.assertEqual(_require_controlled_x_opencli_executable(str(canonical)), str(canonical.absolute()))
                with self.assertRaisesRegex(IdentityResolutionError, "controlled_opencli_required"):
                    _require_controlled_x_opencli_executable(str(executable))

    def test_identity_evidence_rejects_symlink_and_wrong_owner_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target"
            target.mkdir()
            symlink = root / "evidence-link"
            symlink.symlink_to(target, target_is_directory=True)
            with self.assertRaisesRegex(IdentityResolutionError, "identity_evidence_unavailable"):
                _prepare_identity_evidence_dir(symlink)

            owned = root / "owned"
            owned.mkdir()
            with patch("invest_hub_worker.cli.os.geteuid", return_value=os.geteuid() + 1):
                with self.assertRaisesRegex(IdentityResolutionError, "identity_evidence_unavailable"):
                    _prepare_identity_evidence_dir(owned)

    def test_identity_evidence_rejects_symlinked_event_file_and_enforces_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence_dir = Path(directory) / "evidence"
            evidence_dir.mkdir(mode=0o755)
            _prepare_identity_evidence_dir(evidence_dir)
            self.assertEqual(stat.S_IMODE(evidence_dir.stat().st_mode), 0o700)

            target = Path(directory) / "target-event"
            target.write_text("outside", encoding="utf-8")
            event_path = evidence_dir / "x-identity-events.jsonl"
            event_path.symlink_to(target)
            with self.assertRaisesRegex(IdentityResolutionError, "identity_evidence_unavailable"):
                _append_identity_evidence(evidence_dir, "v2", "resolved")

            event_path.unlink()
            _append_identity_evidence(evidence_dir, "v2", "resolved")
            self.assertEqual(stat.S_IMODE(event_path.stat().st_mode), 0o600)

    def test_resolve_x_identity_requires_ack_before_loading_config_or_constructing_runtime(self) -> None:
        output = io.StringIO()
        with patch.dict(os.environ, {"V2_REAL_X_ACK": "not-authorized"}, clear=False), \
             patch("invest_hub_worker.cli.LocalWorkerConfigSet.load", side_effect=AssertionError("config must not load")), \
             contextlib.redirect_stdout(output):
            code = main([
                "resolve-x-identity", "--config", "/private/config.toml", "--credential", "/private/credential.json",
                "--source-id", "x-source", "--opencli-executable", "/private/opencli", "--evidence-dir", "/private/evidence",
            ])
        self.assertEqual(code, 2)
        result = json.loads(output.getvalue())
        self.assertEqual(set(result), {"status", "resolution_status", "idempotent", "error"})
        self.assertEqual(result["error"], "real_x_requires_explicit_authorization")

    def test_x_v3_verification_replay_uses_only_explicit_replay_protocol(self) -> None:
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{
                "source_id": "x-source", "source_type": "x", "source_url": "https://x.com/fixture_handle",
                "profile_ref": "/private/profile", "opencli_contract_version": "v2", "parameter_version": "x-standard-v2",
            }],
        })
        replay_id = "11111111-1111-4111-8111-111111111111"

        class ReplayProtocol:
            credential = object()
            def __init__(self) -> None:
                self.calls: list[str] = []
            def claim_x_v3_verification_replay(self, value: str) -> dict[str, object]:
                self.calls.append("claim")
                self.assertEqual(value, replay_id)
                return {"replay_id": value, "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z"}
            def get_x_v3_verification_replay_context(self, value: str, attempt: int) -> dict[str, object]:
                self.calls.append("context")
                self.assertEqual((value, attempt), (replay_id, 1))
                return {"replay_id": value, "attempt": attempt, "sources": []}
            def complete_x_v3_verification_replay(self, completion: dict[str, object]) -> dict[str, object]:
                self.calls.append("complete")
                self.assertEqual(completion["replay_id"], replay_id)
                return {"status": "succeeded"}
            def fail_x_v3_verification_replay(self, *_args: object) -> dict[str, object]:
                self.calls.append("failure")
                raise AssertionError("successful replay must not fail")
            def assertEqual(self, left: object, right: object) -> None:
                if left != right:
                    raise AssertionError(f"{left!r} != {right!r}")

        protocol = ReplayProtocol()
        class ReplayRuntime:
            def execute(self, claim: dict[str, object], context: dict[str, object]) -> dict[str, object]:
                self.assertEqual((claim["replay_id"], context["replay_id"]), (replay_id, replay_id))
                return {"replay_id": replay_id, "attempt": 1, "provider": "codex_cli", "model_reported": None, "sources": [], "daily": {}}
            def assertEqual(self, left: object, right: object) -> None:
                if left != right:
                    raise AssertionError(f"{left!r} != {right!r}")

        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"V2_REAL_X_ACK": "authorized"}, clear=False):
            with patch("invest_hub_worker.cli.LocalWorkerConfigSet.load", return_value=config), \
                 patch("invest_hub_worker.cli.WorkerProtocol", return_value=protocol), \
                 patch("invest_hub_worker.cli.build_authorized_x_v3_verification_replay_runtime", return_value=ReplayRuntime()), \
                 patch("invest_hub_worker.cli.Worker", side_effect=AssertionError("generic Worker must not be constructed")), \
                 patch("invest_hub_worker.cli.build_authorized_runtime_set", side_effect=AssertionError("normal runtime must not be constructed")), \
                 patch("invest_hub_worker.cli._run_scheduled", side_effect=AssertionError("scheduler must not run")), \
                 contextlib.redirect_stdout(output):
                code = main([
                    "run-x-v3-verification", "--config", "/private/config.toml", "--credential", "/private/credential.json",
                    "--prompt-path", "/private/prompt.md", "--evidence-dir", str(Path(directory) / "evidence"), "--replay-id", replay_id,
                ])
        self.assertEqual(code, 0)
        self.assertEqual(protocol.calls, ["claim", "context", "complete"])
        self.assertEqual(json.loads(output.getvalue()), {"status": "succeeded", "error": None})
        self.assertNotIn(replay_id, output.getvalue())

    def test_x_v3_verification_schema_error_reports_only_replay_failure(self) -> None:
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{"source_id": "x-source", "source_type": "x", "source_url": "https://x.com/fixture_handle", "profile_ref": "/private/profile", "opencli_contract_version": "v2", "parameter_version": "x-standard-v2"}],
        })
        replay_id = "11111111-1111-4111-8111-111111111111"

        class FailingProtocol:
            credential = object()
            def __init__(self) -> None: self.calls: list[str] = []
            def claim_x_v3_verification_replay(self, _value: str) -> dict[str, object]: self.calls.append("claim"); return {"replay_id": replay_id, "attempt": 1, "lease_expires_at": "future"}
            def get_x_v3_verification_replay_context(self, _value: str, _attempt: int) -> dict[str, object]: self.calls.append("context"); return {"replay_id": replay_id, "attempt": 1, "sources": []}
            def complete_x_v3_verification_replay(self, _completion: dict[str, object]) -> dict[str, object]: self.calls.append("complete"); raise AssertionError("schema error must not complete")
            def fail_x_v3_verification_replay(self, value: str, attempt: int, failure: str) -> dict[str, object]: self.calls.append("failure"); self.assertEqual((value, attempt, failure), (replay_id, 1, "schema_error")); return {"status": "failed"}
            def assertEqual(self, left: object, right: object) -> None:
                if left != right: raise AssertionError(f"{left!r} != {right!r}")

        class SchemaFailingRuntime:
            def execute(self, _claim: dict[str, object], _context: dict[str, object]) -> dict[str, object]:
                from invest_hub_worker.runtime import RuntimeExecutionError
                raise RuntimeExecutionError("schema_error", "fixture schema error")

        protocol = FailingProtocol()
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"V2_REAL_X_ACK": "authorized"}, clear=False):
            with patch("invest_hub_worker.cli.LocalWorkerConfigSet.load", return_value=config), patch("invest_hub_worker.cli.WorkerProtocol", return_value=protocol), patch("invest_hub_worker.cli.build_authorized_x_v3_verification_replay_runtime", return_value=SchemaFailingRuntime()), patch("invest_hub_worker.cli.Worker", side_effect=AssertionError("generic Worker must not be constructed")), contextlib.redirect_stdout(output):
                code = main(["run-x-v3-verification", "--config", "/private/config.toml", "--credential", "/private/credential.json", "--prompt-path", "/private/prompt.md", "--evidence-dir", str(Path(directory) / "evidence"), "--replay-id", replay_id])
        self.assertEqual(code, 1)
        self.assertEqual(protocol.calls, ["claim", "context", "failure"])
        self.assertEqual(json.loads(output.getvalue()), {"status": "failed", "error": "schema_error"})


if __name__ == "__main__":
    unittest.main()
