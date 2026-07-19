from __future__ import annotations

import argparse
import json
import os
import stat
from pathlib import Path

from .config import LocalWorkerConfigSet
from .protocol import WorkerProtocol
from .runtime import build_authorized_discord_runtime_set
from .worker import Worker


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
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if os.environ.get("V0_REAL_DISCORD_ACK") != "authorized":
        print(json.dumps({"status": "refused", "reason": "real_discord_requires_explicit_authorization"}))
        return 2

    config = LocalWorkerConfigSet.load(Path(args.config))
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
    runtime = build_authorized_discord_runtime_set(
        config=config,
        evidence_dir=evidence_dir,
        prompt_path=Path(args.prompt_path),
        opencli_contract_path=Path(args.opencli_contract),
        opencli_executable=args.opencli_executable,
    )
    outcome = Worker(protocol, execute=runtime.execute).run_once()
    print(json.dumps({"status": outcome.status, "task_id": outcome.task_id, "error": outcome.error}, sort_keys=True))
    return 0 if outcome.status in {"succeeded", "no_task"} else 1


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
