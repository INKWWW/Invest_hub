from __future__ import annotations

import uuid

from .canonical import normalize_page
from .checkpoint import JsonCheckpointStore
from .connectors import Connector, ConnectorError
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
