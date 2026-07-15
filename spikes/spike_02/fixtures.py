from __future__ import annotations

import json
from collections.abc import Mapping
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .model import ExpectedClaim, FixtureCase, FixtureMessage, Scale


class FixtureError(ValueError):
    """Raised when a fixture violates the public fixture contract."""


_SCALES = {"small", "medium", "large"}
_CATEGORIES = {
    "fact",
    "target_viewpoint",
    "ticker",
    "operation_tendency",
    "context",
}


def load_fixture(path: Path) -> FixtureCase:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise FixtureError(f"fixture read failed: {exc}") from exc
    if not isinstance(payload, Mapping):
        raise FixtureError("fixture root must be an object")

    case_id = _required_string(payload, "case_id")
    scale = _required_string(payload, "scale")
    if scale not in _SCALES:
        raise FixtureError(f"unsupported scale: {scale}")

    raw_messages = payload.get("messages")
    if not isinstance(raw_messages, list) or not raw_messages:
        raise FixtureError("messages must be a non-empty array")

    messages: list[FixtureMessage] = []
    message_ids: set[str] = set()
    for raw_message in raw_messages:
        if not isinstance(raw_message, Mapping):
            raise FixtureError("message must be an object")
        message_id = _required_string(raw_message, "message_id")
        if message_id in message_ids:
            raise FixtureError(f"duplicate message_id: {message_id}")
        message_ids.add(message_id)
        content = _required_string(raw_message, "content")
        kind = _required_string(raw_message, "kind")
        if kind not in {"text", "unparsed_media"}:
            raise FixtureError(f"unsupported message kind: {kind}")
        if not content.strip():
            raise FixtureError(f"empty content: {message_id}")
        author_scope = _required_string(raw_message, "author_scope")
        if author_scope not in {"target", "other"}:
            raise FixtureError(f"unsupported author_scope: {author_scope}")
        parent_id = raw_message.get("parent_id")
        if parent_id is not None and not isinstance(parent_id, str):
            raise FixtureError(f"parent_id must be string or null: {message_id}")
        messages.append(
            FixtureMessage(
                message_id=message_id,
                author_id=_required_string(raw_message, "author_id"),
                author_scope=author_scope,
                published_at=_required_string(raw_message, "published_at"),
                content=content,
                kind=kind,
                parent_id=parent_id,
            )
        )

    for message in messages:
        if message.parent_id is not None and message.parent_id not in message_ids:
            raise FixtureError(
                f"unknown parent_id: {message.message_id} -> {message.parent_id}"
            )

    raw_claims = payload.get("claims", [])
    if not isinstance(raw_claims, list):
        raise FixtureError("claims must be an array")
    claims: list[ExpectedClaim] = []
    claim_ids: set[str] = set()
    for raw_claim in raw_claims:
        if not isinstance(raw_claim, Mapping):
            raise FixtureError("claim must be an object")
        claim_id = _required_string(raw_claim, "claim_id")
        if claim_id in claim_ids:
            raise FixtureError(f"duplicate claim_id: {claim_id}")
        claim_ids.add(claim_id)
        category = _required_string(raw_claim, "category")
        if category not in _CATEGORIES:
            raise FixtureError(f"unsupported claim category: {category}")
        required_terms = _string_tuple(raw_claim, "required_terms")
        source_message_ids = _string_tuple(raw_claim, "source_message_ids")
        missing_sources = set(source_message_ids) - message_ids
        if missing_sources:
            missing = sorted(missing_sources)[0]
            raise FixtureError(f"unknown source_message_id: {missing}")
        target_author_id = raw_claim.get("target_author_id")
        if target_author_id is not None and not isinstance(target_author_id, str):
            raise FixtureError(f"target_author_id must be string or null: {claim_id}")
        claims.append(
            ExpectedClaim(
                claim_id=claim_id,
                category=category,
                required_terms=required_terms,
                source_message_ids=source_message_ids,
                target_author_id=target_author_id,
                forbidden_terms=_string_tuple(raw_claim, "forbidden_terms"),
            )
        )

    return FixtureCase(
        case_id=case_id,
        scale=scale,
        messages=tuple(messages),
        claims=tuple(claims),
    )


def build_synthetic_scale_case(case_id: str, count: int) -> FixtureCase:
    if count < 500:
        raise ValueError("synthetic scale fixture requires at least 500 messages")
    scale: Scale = "medium" if count == 500 else "large"
    start = datetime(2026, 1, 2, 8, 0, tzinfo=timezone.utc)
    messages: list[FixtureMessage] = []
    for index in range(count):
        message_id = f"{case_id}-message-{index + 1:04d}"
        parent_id = None
        if index > 0 and index % 10 == 0:
            parent_id = messages[index - 1].message_id
        is_media = index > 0 and index % 25 == 0
        language = "English" if index % 3 == 0 else "中文"
        ticker = ("ABC", "XYZ", "LMN")[index % 3]
        content = (
            f"[synthetic {index + 1}] {language} topic-{index % 11} "
            f"ticker {ticker}, message {index + 1}."
        )
        if is_media:
            content = f"[synthetic {index + 1}] [image attachment not parsed]"
        messages.append(
            FixtureMessage(
                message_id=message_id,
                author_id="target-analyst" if index % 17 == 0 else f"author-{index % 19:02d}",
                author_scope="target" if index % 17 == 0 else "other",
                published_at=(start + timedelta(minutes=index)).isoformat().replace("+00:00", "Z"),
                content=content,
                kind="unparsed_media" if is_media else "text",
                parent_id=parent_id,
            )
        )
    return FixtureCase(case_id=case_id, scale=scale, messages=tuple(messages), claims=())


def write_fixture(case: FixtureCase, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "case_id": case.case_id,
        "scale": case.scale,
        "messages": [
            {
                "message_id": message.message_id,
                "author_id": message.author_id,
                "author_scope": message.author_scope,
                "published_at": message.published_at,
                "content": message.content,
                "kind": message.kind,
                "parent_id": message.parent_id,
            }
            for message in case.messages
        ],
        "claims": [],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _required_string(payload: Mapping[str, Any], field: str) -> str:
    value = payload.get(field)
    if not isinstance(value, str) or not value.strip():
        raise FixtureError(f"{field} must be a non-empty string")
    return value


def _string_tuple(payload: Mapping[str, Any], field: str) -> tuple[str, ...]:
    value = payload.get(field, [])
    if not isinstance(value, list) or not all(
        isinstance(item, str) and item.strip() for item in value
    ):
        raise FixtureError(f"{field} must be an array of non-empty strings")
    return tuple(value)
