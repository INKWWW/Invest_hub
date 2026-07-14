from __future__ import annotations

from datetime import datetime

from .model import (
    CanonicalMessage,
    ValidationIssue,
    ValidationReport,
)


def validate_page(
    messages: tuple[CanonicalMessage, ...],
    expected_container_id: str,
    known_external_ids: frozenset[str],
) -> ValidationReport:
    issues: list[ValidationIssue] = []
    accepted_ids: list[str] = []
    duplicate_ids: list[str] = []
    unresolved_ids: list[str] = []
    current_ids = {
        message.external_item_id for message in messages if message.external_item_id
    }
    seen_ids: set[str] = set()
    invalid = False

    def issue(
        code: str,
        message: CanonicalMessage,
        field: str | None,
        detail: str,
    ) -> None:
        nonlocal invalid
        invalid = True
        issues.append(
            ValidationIssue(
                code=code,
                item_id=message.external_item_id or None,
                field=field,
                detail=detail,
            )
        )

    for message in messages:
        if not message.external_item_id:
            issue("missing_required_field", message, "external_item_id", "empty")
        elif message.external_item_id in seen_ids:
            issue("duplicate_in_page", message, "external_item_id", "repeated")
        else:
            seen_ids.add(message.external_item_id)

        if not message.author_id:
            issue("missing_required_field", message, "author_id", "empty")
        if not message.source_container_id:
            issue("missing_required_field", message, "source_container_id", "empty")
        elif message.source_container_id != expected_container_id:
            issue(
                "container_conflict",
                message,
                "source_container_id",
                f"expected {expected_container_id}",
            )
        if not message.published_at:
            issue("missing_required_field", message, "published_at", "empty")
        else:
            try:
                datetime.fromisoformat(message.published_at.replace("Z", "+00:00"))
            except ValueError:
                issue("invalid_timestamp", message, "published_at", "not ISO-8601")

        for attachment in message.attachments:
            if not attachment.name or not attachment.content_type or not attachment.url:
                issue(
                    "missing_attachment_metadata",
                    message,
                    "attachments",
                    "name, content_type and url are required",
                )

        if message.external_item_id in known_external_ids:
            duplicate_ids.append(message.external_item_id)
            continue

        unresolved = False
        relation_ids = []
        if message.parent_item_id:
            relation_ids.append(message.parent_item_id)
        if message.quoted_item and message.quoted_item.external_item_id:
            relation_ids.append(message.quoted_item.external_item_id)
        for relation_id in relation_ids:
            if relation_id not in known_external_ids and relation_id not in current_ids:
                unresolved = True
        if unresolved and message.external_item_id:
            unresolved_ids.append(message.external_item_id)
        elif message.external_item_id and not invalid:
            accepted_ids.append(message.external_item_id)

    if invalid:
        state = "invalid"
        checkpoint_safe = False
    elif unresolved_ids:
        state = "unresolved_relation"
        checkpoint_safe = True
    elif duplicate_ids and not accepted_ids:
        state = "duplicate"
        checkpoint_safe = True
    else:
        state = "accepted"
        checkpoint_safe = True
    return ValidationReport(
        state=state,
        issues=tuple(issues),
        accepted_ids=tuple(accepted_ids),
        duplicate_ids=tuple(duplicate_ids),
        unresolved_ids=tuple(unresolved_ids),
        checkpoint_safe=checkpoint_safe,
    )
