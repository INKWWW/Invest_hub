from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import stat
import time
from pathlib import Path

from .config import LocalWorkerConfig, LocalWorkerConfigSet
from .activation import activate_one_x_source
from .errors import ConfigError, ProtocolError, RemoteConflict
from .protocol import WorkerProtocol
from .runtime import build_authorized_runtime_set, build_authorized_x_daily_judgement_runtime
from .worker import Worker
from .x_identity import IdentityResolutionError, OpenCLIProfileInvoker, resolve_configured_x_identity


_SCHEDULED_FAILURE_BACKOFF_SECONDS = 300


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
    judgement_runtime = build_authorized_x_daily_judgement_runtime(
        evidence_dir=evidence_dir,
        prompt_path=Path(args.prompt_path),
    ) if has_x else None
    capabilities = (["discord_sync"] if has_discord else []) + (["x_sync"] if has_x else [])
    worker = Worker(protocol, execute=runtime.execute, execute_windowed=runtime.execute_windowed, capabilities=capabilities)
    if args.command == "run-once":
        outcome = worker.run_once()
        print(json.dumps({"status": outcome.status, "task_id": outcome.task_id, "error": outcome.error}, sort_keys=True))
        return 0 if outcome.status in {"succeeded", "no_task"} else 1
    activation_invoker = OpenCLIProfileInvoker(_require_controlled_x_opencli_executable(args.opencli_executable)) if has_x else None
    return _run_scheduled(worker, once=args.once, poll_seconds=args.poll_seconds, activation_invoker=activation_invoker, judgement_runtime=judgement_runtime)


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
        executable = _require_controlled_x_opencli_executable(args.opencli_executable)
        protocol = WorkerProtocol(config_set.control_plane_url, Path(args.credential), worker_name=args.worker_name)
        resolved = resolve_configured_x_identity(source, protocol, executable)
    except (ConfigError, IdentityResolutionError) as exc:
        result_code = _identity_error_code(exc)
        if not _append_identity_evidence_if_possible(evidence_dir, source, result_code):
            result_code = "identity_evidence_unavailable"
        _print_identity_result("failed", None, False, result_code)
        return 1
    except RemoteConflict:
        result_code = "identity_conflict"
        if not _append_identity_evidence_if_possible(evidence_dir, source, result_code):
            result_code = "identity_evidence_unavailable"
        _print_identity_result("failed", None, False, result_code)
        return 1
    except ProtocolError:
        result_code = "protocol_failure"
        if not _append_identity_evidence_if_possible(evidence_dir, source, result_code):
            result_code = "identity_evidence_unavailable"
        _print_identity_result("failed", None, False, result_code)
        return 1
    except Exception:
        result_code = "identity_resolution_failed"
        if not _append_identity_evidence_if_possible(evidence_dir, source, result_code):
            result_code = "identity_evidence_unavailable"
        _print_identity_result("failed", None, False, result_code)
        return 1

    resolution_status = resolved.get("resolution_status")
    idempotent = resolved.get("idempotent")
    if resolution_status != "resolved" or not isinstance(idempotent, bool):
        result_code = "invalid_identity_resolution_response"
        if not _append_identity_evidence_if_possible(evidence_dir, source, result_code):
            result_code = "identity_evidence_unavailable"
        _print_identity_result("failed", None, False, result_code)
        return 1
    if not _append_identity_evidence_if_possible(evidence_dir, source, "resolved"):
        _print_identity_result("failed", None, False, "identity_evidence_unavailable")
        return 1
    _print_identity_result("resolved", "resolved", idempotent, None)
    return 0


def _identity_error_code(error: Exception) -> str:
    code = str(error)
    allowed = {
        "invalid_x_identity", "invalid_profile_response", "profile_timeout", "profile_invocation_failed",
        "identity_mismatch", "source_not_x", "invalid_x_identity_source", "invalid_identity_resolution_response",
        "controlled_opencli_required", "identity_evidence_unavailable",
    }
    return code if code in allowed else "identity_resolution_failed"


def _controlled_x_opencli_executable() -> Path:
    repository_root = Path(__file__).resolve().parents[4]
    return repository_root / ".runtime" / "v2" / "opencli-collection" / "current" / "bin" / "opencli-v2-collection"


def _require_controlled_x_opencli_executable(value: str) -> str:
    expected = _controlled_x_opencli_executable()
    candidate = Path(value).expanduser()
    candidate_absolute = candidate if candidate.is_absolute() else Path.cwd() / candidate
    expected_absolute = expected.absolute()
    if candidate_absolute != expected_absolute:
        raise IdentityResolutionError("controlled_opencli_required")
    try:
        expected_resolved = expected_absolute.resolve(strict=True)
        candidate_resolved = candidate_absolute.resolve(strict=True)
        runtime_root = expected_absolute.parents[2].resolve(strict=True)
        details = expected_resolved.stat()
    except OSError as exc:
        raise IdentityResolutionError("controlled_opencli_required") from exc
    if (
        candidate_resolved != expected_resolved
        or not expected_resolved.is_relative_to(runtime_root)
        or not stat.S_ISREG(details.st_mode)
        or not details.st_mode & stat.S_IXUSR
    ):
        raise IdentityResolutionError("controlled_opencli_required")
    return str(expected_absolute)


def _prepare_identity_evidence_dir(path: Path) -> None:
    try:
        path.mkdir(parents=True, mode=0o700, exist_ok=True)
        details = os.lstat(path)
        if stat.S_ISLNK(details.st_mode) or not stat.S_ISDIR(details.st_mode) or details.st_uid != os.geteuid():
            raise IdentityResolutionError("identity_evidence_unavailable")
        os.chmod(path, 0o700)
        final_details = os.lstat(path)
    except OSError as exc:
        raise IdentityResolutionError("identity_evidence_unavailable") from exc
    if (
        stat.S_ISLNK(final_details.st_mode)
        or not stat.S_ISDIR(final_details.st_mode)
        or final_details.st_uid != os.geteuid()
        or stat.S_IMODE(final_details.st_mode) != 0o700
    ):
        raise IdentityResolutionError("identity_evidence_unavailable")


def _append_identity_evidence_if_possible(evidence_dir: Path | None, source: LocalWorkerConfig | None, result_code: str) -> bool:
    if evidence_dir is not None and source is not None:
        try:
            _append_identity_evidence(evidence_dir, source.opencli_contract_version, result_code)
        except IdentityResolutionError:
            return False
    return True


def _append_identity_evidence(evidence_dir: Path, contract_version: str, result_code: str) -> None:
    _prepare_identity_evidence_dir(evidence_dir)
    event_path = evidence_dir / "x-identity-events.jsonl"
    event = {
        "occurred_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "contract_version": contract_version,
        "result_code": result_code,
    }
    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        try:
            existing = os.lstat(event_path)
        except FileNotFoundError:
            existing = None
        if existing is not None and (
            stat.S_ISLNK(existing.st_mode)
            or not stat.S_ISREG(existing.st_mode)
            or existing.st_uid != os.geteuid()
        ):
            raise IdentityResolutionError("identity_evidence_unavailable")
        fd = os.open(event_path, flags, 0o600)
    except OSError as exc:
        raise IdentityResolutionError("identity_evidence_unavailable") from exc
    try:
        details = os.fstat(fd)
        if not stat.S_ISREG(details.st_mode) or details.st_uid != os.geteuid():
            raise IdentityResolutionError("identity_evidence_unavailable")
        os.fchmod(fd, 0o600)
        if stat.S_IMODE(os.fstat(fd).st_mode) != 0o600:
            raise IdentityResolutionError("identity_evidence_unavailable")
        with os.fdopen(fd, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(event, sort_keys=True))
            stream.write("\n")
    except (OSError, IdentityResolutionError) as exc:
        try:
            os.close(fd)
        except OSError:
            pass
        if isinstance(exc, IdentityResolutionError):
            raise
        raise IdentityResolutionError("identity_evidence_unavailable") from exc


def _print_identity_result(status: str, resolution_status: str | None, idempotent: bool, error: str | None) -> None:
    print(json.dumps({
        "status": status,
        "resolution_status": resolution_status,
        "idempotent": idempotent,
        "error": error,
    }, sort_keys=True))


def _run_scheduled(
    worker: Worker,
    *,
    once: bool,
    poll_seconds: int,
    activation_invoker: OpenCLIProfileInvoker | None = None,
    judgement_runtime: object | None = None,
) -> int:
    while True:
        tick: dict[str, object] = {}
        activation_error: str | None = None
        if activation_invoker is not None:
            try:
                worker.protocol.heartbeat("idle", worker.capabilities, datetime.now(timezone.utc).isoformat())
                activate_one_x_source(worker.protocol, activation_invoker)
            except Exception as exc:
                activation_error = type(exc).__name__
                print(json.dumps({"status": "activation_failed", "error": activation_error}, sort_keys=True), flush=True)
        try:
            tick = worker.schedule_tick()
        except Exception as exc:
            print(json.dumps({"status": "schedule_failed", "error": type(exc).__name__}, sort_keys=True), flush=True)

        outcome = worker.run_once()
        if outcome.status == "no_task" and judgement_runtime is not None:
            outcome = worker.run_x_daily_judgement_once(judgement_runtime.execute if hasattr(judgement_runtime, "execute") else judgement_runtime)
        scheduled_at = tick.get("scheduled_at") if isinstance(tick.get("scheduled_at"), str) else None
        tasks = tick.get("tasks")
        deferred_sources = tick.get("deferred_source_ids")
        judgement_dispatch_failed = tick.get("judgement_dispatch_failed") is True
        print(json.dumps({
            "status": outcome.status,
            "task_id": outcome.task_id,
            "error": outcome.error,
            "activation_error": activation_error,
            "scheduled_at": scheduled_at,
            "scheduled_task_count": len(tasks) if isinstance(tasks, list) else None,
            "deferred_source_count": len(deferred_sources) if isinstance(deferred_sources, list) else None,
            "judgement_dispatch_failed": judgement_dispatch_failed,
        }, sort_keys=True), flush=True)
        if once:
            return 0 if outcome.status in {"succeeded", "no_task"} else 1
        time.sleep(_scheduled_sleep_seconds(outcome, poll_seconds))


def _scheduled_sleep_seconds(outcome: object, poll_seconds: int) -> int:
    if getattr(outcome, "status", None) == "recovering" and getattr(outcome, "task_id", None):
        return max(poll_seconds, _SCHEDULED_FAILURE_BACKOFF_SECONDS)
    return poll_seconds


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
