from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any

from .model import StructuredOutput, StructuredTopic


class SchemaError(ValueError):
    def __init__(self, code: str, detail: str):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


def parse_structured_output(text: str) -> StructuredOutput:
    normalized = _remove_json_fence(text)
    try:
        payload = json.loads(normalized)
    except json.JSONDecodeError as exc:
        raise SchemaError("invalid_json", str(exc)) from exc
    if not isinstance(payload, Mapping):
        raise SchemaError("invalid_shape", "top-level JSON must be an object")

    required_fields = {"topics", "media_unparsed", "media_source_message_ids", "warnings"}
    missing_fields = sorted(required_fields - set(payload))
    if missing_fields:
        raise SchemaError("missing_field", ", ".join(missing_fields))

    topics_payload = payload.get("topics", [])
    if not isinstance(topics_payload, list):
        raise SchemaError("invalid_topics", "topics must be an array")
    topics: list[StructuredTopic] = []
    for index, raw_topic in enumerate(topics_payload):
        if not isinstance(raw_topic, Mapping):
            raise SchemaError("invalid_topic", f"topic {index} must be an object")
        topics.append(
            StructuredTopic(
                title=_required_string(raw_topic, "title", index),
                summary=_required_string(raw_topic, "summary", index),
                source_message_ids=_string_tuple(raw_topic, "source_message_ids", index),
                author_scope=_required_string(raw_topic, "author_scope", index),
                author_id=_optional_string(raw_topic, "author_id", index),
                tickers=_string_tuple(raw_topic, "tickers", index),
                operation_tendency=_optional_string(raw_topic, "operation_tendency", index),
                uncertainty=_optional_string(raw_topic, "uncertainty", index),
            )
        )

    media_unparsed = payload.get("media_unparsed", False)
    if not isinstance(media_unparsed, bool):
        raise SchemaError("invalid_media_flag", "media_unparsed must be boolean")
    media_source_message_ids = payload.get("media_source_message_ids", [])
    if not isinstance(media_source_message_ids, list) or not all(
        isinstance(item, str) and item for item in media_source_message_ids
    ):
        raise SchemaError(
            "invalid_media_sources",
            "media_source_message_ids must be an array of non-empty strings",
        )
    warnings = payload.get("warnings", [])
    if not isinstance(warnings, list) or not all(isinstance(item, str) for item in warnings):
        raise SchemaError("invalid_warnings", "warnings must be an array of strings")
    return StructuredOutput(
        topics=tuple(topics),
        media_unparsed=media_unparsed,
        media_source_message_ids=tuple(media_source_message_ids),
        warnings=tuple(warnings),
    )


def validate_structured_output(
    output: StructuredOutput,
    input_message_ids: set[str],
    target_author_ids: set[str],
    unparsed_media_message_ids: set[str],
) -> StructuredOutput:
    for topic in output.topics:
        if topic.author_scope not in {"target", "channel"}:
            raise SchemaError("invalid_author_scope", topic.author_scope)
        if not topic.source_message_ids:
            raise SchemaError("source_message_ids", "topic must cite a message")
        unknown_ids = set(topic.source_message_ids) - input_message_ids
        if unknown_ids:
            unknown = sorted(unknown_ids)[0]
            raise SchemaError("source_message_ids", f"unknown message ID: {unknown}")
        if topic.author_scope == "target":
            if not topic.author_id or topic.author_id not in target_author_ids:
                raise SchemaError("author_id", "target topic must cite a known target author")
    media_source_ids = set(output.media_source_message_ids)
    if len(media_source_ids) != len(output.media_source_message_ids):
        raise SchemaError("media_source_message_ids", "duplicate message ID")
    unknown_media_ids = media_source_ids - input_message_ids
    if unknown_media_ids:
        unknown = sorted(unknown_media_ids)[0]
        raise SchemaError("media_source_message_ids", f"unknown message ID: {unknown}")
    non_media_ids = media_source_ids - unparsed_media_message_ids
    if non_media_ids:
        non_media = sorted(non_media_ids)[0]
        raise SchemaError(
            "media_source_message_ids",
            f"message is not unparsed media: {non_media}",
        )
    if output.media_unparsed != bool(unparsed_media_message_ids):
        raise SchemaError(
            "media_unparsed",
            "media_unparsed must match the current chunk's unparsed media messages",
        )
    if media_source_ids != unparsed_media_message_ids:
        raise SchemaError(
            "media_source_message_ids",
            "must cite every unparsed media message in the current chunk",
        )
    return output


def _remove_json_fence(text: str) -> str:
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


def _required_string(payload: Mapping[str, Any], field: str, index: int) -> str:
    value = payload.get(field)
    if not isinstance(value, str) or not value.strip():
        raise SchemaError("invalid_topic", f"topic {index} field {field} must be string")
    return value


def _optional_string(payload: Mapping[str, Any], field: str, index: int) -> str | None:
    value = payload.get(field)
    if value is None:
        return None
    if not isinstance(value, str):
        raise SchemaError("invalid_topic", f"topic {index} field {field} must be string or null")
    return value


def _string_tuple(payload: Mapping[str, Any], field: str, index: int) -> tuple[str, ...]:
    value = payload.get(field, [])
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise SchemaError("invalid_topic", f"topic {index} field {field} must be string array")
    return tuple(value)
