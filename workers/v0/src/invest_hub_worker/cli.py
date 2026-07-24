from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import stat
import time
from pathlib import Path

from .config import LocalWorkerConfig, LocalWorkerConfigSet
from .errors import ConfigError, ProtocolError, RemoteConflict
from .protocol import WorkerProtocol
from .runtime import build_authorized_runtime_set
from .worker import Worker
from .x_identity import IdentityResolutionError, resolve_configured_x_identity


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Invest Hub V0 authorized local Worker")
    subparsers = parser.add_subparsers(dest="command", required=True)
    run_once = subparsers.add_parser("run-once", help="claim and process at most one authorized task")
    run_once.add_argument("--config", required=True)
    run_once.add_argument("--credential", required=True)
    run_once.add_argument("--opencli-contract", required=True)
    run_once.add_argument("--prompt-path", required=True)
    run_once.add_argument("--evidence-dir", required=True)
    run_once.add_argument("--enrolment-code-file")
    run_once.add_argument("--opencli-executable")
    run_once.add_argument("--worker-name", default="v0-authorized-worker")
    run_scheduled = subparsers.add_parser("run-scheduled", help="schedule due windows and process authorized tasks")
    run_scheduled.add_argument("--config", required=True)
    run_scheduled.add_argument("--credential", required=True)
    run_scheduled.add_argument("--opencli-contract", required=True)
    run_scheduled.add_argument("--prompt-path", required=True)
    run_scheduled.add_argument("--evidence-dir", required=True)
    run_scheduled.add_argument("--opencli-executable")
    run_scheduled.add_argument("--worker-name", default="v1-authorized-worker")
    run_scheduled.add_argument("--once", action="store_true", help="perform one scheduling and task-processing iteration")
    run_scheduled.add_argument("--poll-seconds", type=int, default=60)
    resolve_identity = subparsers.add_parser("resolve-x-identity", help="verify one configured X source identity without collecting posts")
    resolve_identity.add_argument("--config", required=True)
    resolve_identity.add_argument("--credential", required=True)
    resolve_identity.add_argument("--source-id", required=True)
    resolve_identity.add_argument("--opencli-executable", required=True)
    resolve_identity.add_argument("--evidence-dir", required=True)
    resolve_identity.add_argument("--worker-name", default="v2-x-identity-worker")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "resolve-x-identity":
        return _resolve_x_identity(args)
    acknowledgement_variable = "V1_REAL_DISCORD_ACK" if args.command == "run-scheduled" else "V0_REAL_DISCORD_ACK"
    if args.command == "run-scheduled" and args.poll_seconds < 1:
        print(json.dumps({"status": "refused", "reason": "poll_seconds_must_be_positive"}))
        return 2

    config = LocalWorkerConfigSet.load(Path(args.config))
    has_discord = any(source.source_type == "discord" for source in config.sources)
    has_x = any(source.source_type == "x" for source in config.sources)
    if has_discord and os.environ.get(acknowledgement_variable) != "authorized":
        print(json.dumps({"status": "refused", "reason": "real_discord_requires_explicit_authorization"}))
        return 2
    if has_x and os.environ.get("V2_REAL_X_ACK") != "authorized":
        print(json.dumps({"status": "refused", "reason": "real_x_requires_explicit_authorization"}))
        return 2
    credential_path = Path(args.credential)
    protocol = WorkerProtocol(config.control_plane_url, credential_path, worker_name=args.worker_name)
    if protocol.credential is None:
        if not args.enrolment_code_file:
            print(json.dumps({"status": "refused", "reason": "worker_enrolment_required"}))
            return 2
        protocol.enrol(_read_private_text(Path(args.enrolment_code_file)))

    evidence_dir = Path(args.evidence_dir)
    evidence_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(evidence_dir, 0o700)
    runtime = build_authorized_runtime_set(
        config=config,
        evidence_dir=evidence_dir,
        prompt_path=Path(args.prompt_path),
        opencli_contract_path=Path(args.opencli_contract),
        opencli_executable=args.opencli_executable,
    )
    worker = Worker(protocol, execute=runtime.execute, execute_windowed=runtime.execute_windowed)
    if args.command == "run-once":
        outcome = worker.run_once()
        print(json.dumps({"status": outcome.status, "task_id": outcome.task_id, "error": outcome.error}, sort_keys=True))
        return 0 if outcome.status in {"succeeded", "no_task"} else 1
    return _run_scheduled(worker, once=args.once, poll_seconds=args.poll_seconds)


def _resolve_x_identity(args: argparse.Namespace) -> int:
    if os.environ.get("V2_REAL_X_ACK") != "authorized":
        _print_identity_result("refused", None, False, "real_x_requires_explicit_authorization")
        return 2
    evidence_dir: Path | None = None
    source: LocalWorkerConfig | None = None
    try:
        config_set = LocalWorkerConfigSet.load(Path(args.config))
        source = config_set.source_for(args.source_id)
        x_sources = [candidate for candidate in config_set.sources if candidate.source_type == "x"]
        if source.source_type != "x" or len(x_sources) != 1:
            raise IdentityResolutionError("invalid_x_identity_source")
        evidence_dir = Path(args.evidence_dir)
        _prepare_identity_evidence_dir(evidence_dir)
        protocol = WorkerProtocol(config_set.control_plane_url, Path(args.credential), worker_name=args.worker_name)
        resolved = resolve_configured_x_identity(source, protocol, args.opencli_executable)
    except (ConfigError, IdentityResolutionError) as exc:
        result_code = _identity_error_code(exc)
        _append_identity_evidence_if_possible(evidence_dir, source, result_code)
        _print_identity_result("failed", None, False, result_code)
        return 1
    except RemoteConflict:
        _append_identity_evidence_if_possible(evidence_dir, source, "identity_conflict")
        _print_identity_result("failed", None, False, "identity_conflict")
        return 1
    except ProtocolError:
        _append_identity_evidence_if_possible(evidence_dir, source, "protocol_failure")
        _print_identity_result("failed", None, False, "protocol_failure")
        return 1
    except Exception:
        _append_identity_evidence_if_possible(evidence_dir, source, "identity_resolution_failed")
        _print_identity_result("failed", None, False, "identity_resolution_failed")
        return 1

    resolution_status = resolved.get("resolution_status")
    idempotent = resolved.get("idempotent")
    if resolution_status != "resolved" or not isinstance(idempotent, bool):
        _append_identity_evidence_if_possible(evidence_dir, source, "invalid_identity_resolution_response")
        _print_identity_result("failed", None, False, "invalid_identity_resolution_response")
        return 1
    _append_identity_evidence(evidence_dir, source.opencli_contract_version, "resolved")
    _print_identity_result("resolved", "resolved", idempotent, None)
    return 0


def _identity_error_code(error: Exception) -> str:
    code = str(error)
    allowed = {
        "invalid_x_identity", "invalid_profile_response", "profile_timeout", "profile_invocation_failed",
        "identity_mismatch", "source_not_x", "invalid_x_identity_source", "invalid_identity_resolution_response",
    }
    return code if code in allowed else "identity_resolution_failed"


def _prepare_identity_evidence_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, 0o700)
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise IdentityResolutionError("identity_resolution_failed")


def _append_identity_evidence_if_possible(evidence_dir: Path | None, source: LocalWorkerConfig | None, result_code: str) -> None:
    if evidence_dir is not None and source is not None:
        _append_identity_evidence(evidence_dir, source.opencli_contract_version, result_code)


def _append_identity_evidence(evidence_dir: Path, contract_version: str, result_code: str) -> None:
    event_path = evidence_dir / "x-identity-events.jsonl"
    event = {
        "occurred_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "contract_version": contract_version,
        "result_code": result_code,
    }
    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
    fd = os.open(event_path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(event, sort_keys=True))
            stream.write("\n")
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        raise


def _print_identity_result(status: str, resolution_status: str | None, idempotent: bool, error: str | None) -> None:
    print(json.dumps({
        "status": status,
        "resolution_status": resolution_status,
        "idempotent": idempotent,
        "error": error,
    }, sort_keys=True))


def _run_scheduled(worker: Worker, *, once: bool, poll_seconds: int) -> int:
    while True:
        try:
            tick = worker.schedule_tick()
        except Exception as exc:
            print(json.dumps({"status": "schedule_failed", "error": type(exc).__name__}, sort_keys=True))
            return 1

        outcome = worker.run_once()
        scheduled_at = tick.get("scheduled_at") if isinstance(tick.get("scheduled_at"), str) else None
        tasks = tick.get("tasks")
        deferred_sources = tick.get("deferred_source_ids")
        print(json.dumps({
            "status": outcome.status,
            "task_id": outcome.task_id,
            "error": outcome.error,
            "scheduled_at": scheduled_at,
            "scheduled_task_count": len(tasks) if isinstance(tasks, list) else None,
            "deferred_source_count": len(deferred_sources) if isinstance(deferred_sources, list) else None,
        }, sort_keys=True))
        if once:
            return 0 if outcome.status in {"succeeded", "no_task"} else 1
        time.sleep(poll_seconds)


def _read_private_text(path: Path) -> str:
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
    except OSError as exc:
        raise RuntimeError("cannot read enrolment code file") from exc
    if mode & 0o077:
        raise RuntimeError("enrolment code file must be owner-only")
    value = path.read_text(encoding="utf-8").strip()
    if not value:
        raise RuntimeError("enrolment code file is empty")
    return value


if __name__ == "__main__":
    raise SystemExit(main())
