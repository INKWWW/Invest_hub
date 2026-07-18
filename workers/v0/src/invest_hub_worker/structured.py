from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any


class SchemaError(ValueError):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


REQUIRED_FIELDS = frozenset({"topics", "media_unparsed", "media_source_message_ids", "warnings"})
ALLOWED_FIELDS = REQUIRED_FIELDS
TOPIC_FIELDS = frozenset(
    {
        "title",
        "summary",
        "source_message_ids",
        "author_scope",
        "author_id",
        "tickers",
        "operation_tendency",
        "uncertainty",
    }
)


def parse_structured_output(text: str) -> dict[str, Any]:
    normalized = _remove_json_fence(text)
    try:
        payload = json.loads(normalized)
    except (json.JSONDecodeError, TypeError) as exc:
        raise SchemaError("invalid_json", str(exc)) from exc
    if not isinstance(payload, Mapping):
        raise SchemaError("invalid_shape", "top-level JSON must be an object")

    missing = sorted(REQUIRED_FIELDS - set(payload))
    if missing:
        raise SchemaError("missing_field", ", ".join(missing))
    unknown = sorted(set(payload) - ALLOWED_FIELDS)
    if unknown:
        raise SchemaError("unknown_field", ", ".join(unknown))

    topics = payload["topics"]
    if not isinstance(topics, list):
        raise SchemaError("invalid_topics", "topics must be an array")
    normalized_topics: list[dict[str, Any]] = []
    for index, topic in enumerate(topics):
        if not isinstance(topic, Mapping):
            raise SchemaError("invalid_topic", f"topic {index} must be an object")
        missing_topic = sorted({"title", "summary", "source_message_ids", "author_scope"} - set(topic))
        if missing_topic:
            raise SchemaError("invalid_topic", f"topic {index} missing {', '.join(missing_topic)}")
        unknown_topic = sorted(set(topic) - TOPIC_FIELDS)
        if unknown_topic:
            raise SchemaError("invalid_topic", f"topic {index} unknown {', '.join(unknown_topic)}")
        title = topic["title"]
        summary = topic["summary"]
        scope = topic["author_scope"]
        if not isinstance(title, str) or not title.strip():
            raise SchemaError("invalid_topic", f"topic {index} title must be a non-empty string")
        if not isinstance(summary, str) or not summary.strip():
            raise SchemaError("invalid_topic", f"topic {index} summary must be a non-empty string")
        if scope not in {"target", "channel"}:
            raise SchemaError("invalid_author_scope", f"topic {index} author_scope must be target or channel")
        source_ids = topic["source_message_ids"]
        if not _string_list(source_ids):
            raise SchemaError("invalid_topic", f"topic {index} source_message_ids must be a string array")
        author_id = topic.get("author_id")
        if author_id is not None and (not isinstance(author_id, str) or not author_id.strip()):
            raise SchemaError("invalid_topic", f"topic {index} author_id must be a string or null")
        tickers = topic.get("tickers", [])
        if not _string_list(tickers):
            raise SchemaError("invalid_topic", f"topic {index} tickers must be a string array")
        for optional in ("operation_tendency", "uncertainty"):
            value = topic.get(optional)
            if value is not None and not isinstance(value, str):
                raise SchemaError("invalid_topic", f"topic {index} {optional} must be a string or null")
        normalized_topics.append(dict(topic))

    media_unparsed = payload["media_unparsed"]
    if not isinstance(media_unparsed, bool):
        raise SchemaError("invalid_media_flag", "media_unparsed must be boolean")
    media_ids = payload["media_source_message_ids"]
    if not _string_list(media_ids):
        raise SchemaError("invalid_media_sources", "media_source_message_ids must be a string array")
    if len(set(media_ids)) != len(media_ids):
        raise SchemaError("media_source_message_ids", "duplicate message ID")
    warnings = payload["warnings"]
    if not isinstance(warnings, list) or not all(isinstance(item, str) for item in warnings):
        raise SchemaError("invalid_warnings", "warnings must be an array of strings")

    return {
        "topics": normalized_topics,
        "media_unparsed": media_unparsed,
        "media_source_message_ids": list(media_ids),
        "warnings": list(warnings),
    }


def validate_structured_output(
    output: Mapping[str, Any],
    input_message_ids: set[str],
    unparsed_media_ids: set[str],
    target_author_ids: set[str] | None = None,
) -> dict[str, Any]:
    """Validate source attribution and exact unparsed-media coverage."""

    # Re-run shape validation when callers construct a mapping directly.
    normalized = parse_structured_output(json.dumps(dict(output), ensure_ascii=False))
    if not unparsed_media_ids <= input_message_ids:
        unknown = sorted(unparsed_media_ids - input_message_ids)[0]
        raise SchemaError("media_source_message_ids", f"unparsed media ID is not in input: {unknown}")

    media_ids = set(normalized["media_source_message_ids"])
    unknown_media_ids = media_ids - input_message_ids
    if unknown_media_ids:
        unknown = sorted(unknown_media_ids)[0]
        raise SchemaError("media_source_message_ids", f"unknown message ID: {unknown}")
    non_media_ids = media_ids - unparsed_media_ids
    if non_media_ids:
        non_media = sorted(non_media_ids)[0]
        raise SchemaError("media_source_message_ids", f"message is not unparsed media: {non_media}")
    if normalized["media_unparsed"] != bool(unparsed_media_ids):
        raise SchemaError("media_unparsed", "media_unparsed must match current chunk media")
    if media_ids != unparsed_media_ids:
        raise SchemaError("media_source_message_ids", "must cite every unparsed media message in current chunk")

    known_target_authors = target_author_ids or set()
    for topic in normalized["topics"]:
        topic_ids = set(topic["source_message_ids"])
        unknown_ids = topic_ids - input_message_ids
        if unknown_ids:
            unknown = sorted(unknown_ids)[0]
            raise SchemaError("source_message_ids", f"unknown message ID: {unknown}")
        if topic["author_scope"] == "target":
            author_id = topic.get("author_id")
            if known_target_authors and author_id not in known_target_authors:
                raise SchemaError("author_id", "target topic must cite a known target author")
            if not author_id:
                raise SchemaError("author_id", "target topic must cite an author")
    return normalized


def _string_list(value: object) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) and bool(item.strip()) for item in value)


def _remove_json_fence(text: str) -> str:
    if not isinstance(text, str):
        raise SchemaError("invalid_json", "structured output must be text")
    normalized = text.strip()
    if not normalized.startswith("```"):
        return normalized
    lines = normalized.splitlines()
    if len(lines) < 3 or not lines[-1].strip().startswith("```"):
        return normalized
    language = lines[0].strip()[3:].strip().lower()
    if language not in {"", "json"}:
        return normalized
    return "\n".join(lines[1:-1]).strip()

