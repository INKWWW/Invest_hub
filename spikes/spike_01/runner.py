from __future__ import annotations

import argparse
import json
import uuid
from dataclasses import asdict
from pathlib import Path

from .canonical import normalize_page
from .checkpoint import JsonCheckpointStore
from .connectors import (
    Connector,
    ConnectorError,
    OpenCLIConnector,
    SubprocessOpenCLIInvoker,
)
from .evidence import LocalEvidenceStore
from .model import Checkpoint, RunReport, SourceConfig
from .validator import validate_page


def run_incremental(
    connector: Connector,
    config: SourceConfig,
    evidence: LocalEvidenceStore,
    checkpoints: JsonCheckpointStore,
) -> RunReport:
    run_id = uuid.uuid4().hex
    checkpoint_before = checkpoints.load(config.source_container_id)
    checkpoint_after = checkpoint_before
    pages_seen = 0
    raw_messages_seen = 0
    accepted_messages = 0
    duplicate_messages = 0
    invalid_messages = 0
    unresolved_messages = 0
    errors: list[str] = []

    try:
        for page in connector.iter_pages(config, checkpoint_before):
            pages_seen += 1
            raw_messages_seen += len(page.messages)
            evidence.persist_raw(page)
            messages = normalize_page(page, config.source_account_id)
            report = validate_page(
                messages,
                config.source_container_id,
                evidence.message_ids(),
            )
            evidence.persist_canonical(
                tuple(
                    message
                    for message in messages
                    if message.external_item_id
                )
            )
            evidence.persist_validation(report)
            accepted_messages += len(report.accepted_ids)
            duplicate_messages += len(report.duplicate_ids)
            unresolved_messages += len(report.unresolved_ids)
            invalid_messages += max(
                0,
                len(messages)
                - len(report.accepted_ids)
                - len(report.duplicate_ids)
                - len(report.unresolved_ids),
            )
            if not report.checkpoint_safe:
                return RunReport(
                    run_id=run_id,
                    source_container_id=config.source_container_id,
                    pages_seen=pages_seen,
                    raw_messages_seen=raw_messages_seen,
                    accepted_messages=accepted_messages,
                    duplicate_messages=duplicate_messages,
                    invalid_messages=invalid_messages,
                    unresolved_messages=unresolved_messages,
                    checkpoint_before=checkpoint_before,
                    checkpoint_after=checkpoint_after,
                    status="partial",
                    errors=("page validation is not checkpoint safe",),
                )
            last_id = next(
                (
                    message.external_item_id
                    for message in reversed(messages)
                    if message.external_item_id
                ),
                checkpoint_after.last_external_item_id
                if checkpoint_after is not None
                else None,
            )
            checkpoint_after = Checkpoint(
                source_container_id=config.source_container_id,
                cursor=page.cursor_after,
                last_external_item_id=last_id,
            )
            checkpoints.commit(checkpoint_after)
            if raw_messages_seen >= config.max_messages:
                break
    except ConnectorError as exc:
        errors.append(str(exc))
        status = "partial" if pages_seen else "failed"
        return RunReport(
            run_id=run_id,
            source_container_id=config.source_container_id,
            pages_seen=pages_seen,
            raw_messages_seen=raw_messages_seen,
            accepted_messages=accepted_messages,
            duplicate_messages=duplicate_messages,
            invalid_messages=invalid_messages,
            unresolved_messages=unresolved_messages,
            checkpoint_before=checkpoint_before,
            checkpoint_after=checkpoint_after,
            status=status,
            errors=tuple(errors),
        )
    except Exception as exc:
        errors.append(f"{type(exc).__name__}: {exc}")
        return RunReport(
            run_id=run_id,
            source_container_id=config.source_container_id,
            pages_seen=pages_seen,
            raw_messages_seen=raw_messages_seen,
            accepted_messages=accepted_messages,
            duplicate_messages=duplicate_messages,
            invalid_messages=invalid_messages,
            unresolved_messages=unresolved_messages,
            checkpoint_before=checkpoint_before,
            checkpoint_after=checkpoint_after,
            status="failed",
            errors=tuple(errors),
        )

    return RunReport(
        run_id=run_id,
        source_container_id=config.source_container_id,
        pages_seen=pages_seen,
        raw_messages_seen=raw_messages_seen,
        accepted_messages=accepted_messages,
        duplicate_messages=duplicate_messages,
        invalid_messages=invalid_messages,
        unresolved_messages=unresolved_messages,
        checkpoint_before=checkpoint_before,
        checkpoint_after=checkpoint_after,
        status="success",
        errors=tuple(errors),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the local Spike-01 harness")
    subparsers = parser.add_subparsers(dest="mode", required=True)
    real = subparsers.add_parser("real", help="run the read-only OpenCLI track")
    real.add_argument("--channel-url", required=True)
    real.add_argument("--source-container-id", required=True)
    real.add_argument("--profile-path", required=True)
    real.add_argument("--source-account-id", required=True)
    real.add_argument("--opencli-bin", required=True)
    real.add_argument("--contract-path", required=True, type=Path)
    real.add_argument("--evidence-dir", required=True, type=Path)
    real.add_argument("--max-messages", required=True, type=int)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.mode != "real":
        raise RuntimeError(f"unsupported mode: {args.mode}")
    connector = OpenCLIConnector(
        SubprocessOpenCLIInvoker(
            args.contract_path,
            executable_override=args.opencli_bin,
        ),
        source_account_id=args.source_account_id,
    )
    report = run_incremental(
        connector,
        SourceConfig(
            source_container_id=args.source_container_id,
            channel_url=args.channel_url,
            source_account_id=args.source_account_id,
            max_messages=args.max_messages,
            profile_path=args.profile_path,
        ),
        LocalEvidenceStore(args.evidence_dir),
        JsonCheckpointStore(args.evidence_dir / "checkpoints"),
    )
    print(json.dumps(asdict(report), ensure_ascii=False, sort_keys=True))
    return 0 if report.status == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
