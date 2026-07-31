from __future__ import annotations

import json
import re
from collections.abc import Mapping, Sequence
from datetime import date, datetime
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

V1_1_CHUNK_FIELDS = frozenset({"schema_version", "facts", "media_source_message_ids", "warnings"})
V1_1_FACT_FIELDS = frozenset(
    {
        "author_id",
        "topic",
        "viewpoint",
        "reasoning",
        "operation_tendency",
        "methodology",
        "uncertainty",
        "source_message_ids",
    }
)
V1_1_DAILY_FIELDS = frozenset(
    {"schema_version", "natural_date", "as_of", "author_cards", "topic_discussions", "warnings"}
)
V1_1_AUTHOR_CARD_FIELDS = frozenset(
    {"author_id", "author_display", "core_logic", "operation_tendency", "methodology", "uncertainty", "source_message_ids"}
)
V1_1_CORE_LOGIC_FIELDS = frozenset({"market_trend", "stock_judgments"})
V1_1_STOCK_JUDGMENT_FIELDS = frozenset({"subject", "judgment", "reasoning", "source_message_ids"})
V1_1_OPERATION_FIELDS = frozenset({"market", "stocks"})
V1_1_TOPIC_FIELDS = frozenset({"title", "summary", "viewpoints", "uncertainty", "source_message_ids"})
V1_1_VIEWPOINT_FIELDS = frozenset(
    {"author_id", "author_display", "viewpoint", "reasoning", "operation_tendency", "source_message_ids"}
)
V2_X_CHUNK_FIELDS = frozenset({"schema_version", "analyses"})
V2_X_ANALYSIS_FIELDS = frozenset({"post_id", "blogger_viewpoint", "arguments", "quoted_post_viewpoint", "uncertainties", "evidence_post_ids", "post_link"})
V2_X_WINDOW_FIELDS = frozenset({"schema_version", "natural_date", "range_task_id", "occurred_from_at", "occurred_through_at", "window_viewpoints", "analysis_ids", "evidence_post_ids", "uncertainties"})
V2_X_CROSS_BLOGGER_FIELDS = frozenset({"schema_version", "stock_viewpoints", "market_industry_viewpoints", "uncertainties"})
V2_X_CROSS_BLOGGER_ITEM_FIELDS = frozenset({"statement", "supporting_source_ids", "dissenting_source_ids", "analysis_ids", "evidence_post_ids", "uncertainties"})
_IMPERATIVE_INVESTMENT_RECOMMENDATION = re.compile(r"(?:系统\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)")


def parse_v2_x_chunk_output(
    text: str,
    allowed_post_ids: set[str],
    allowed_context_post_ids: Mapping[str, set[str]] | set[str],
) -> dict[str, Any]:
    """Validate one immutable analysis per authored post.

    Production callers pass a mapping from an authored post ID to the context
    post IDs visible with that exact post.  The set form is retained only for
    the single-post fixture boundary, where it has the same meaning.  This is
    intentionally not a global context allow-list: a quote attached to post A
    must never become evidence for post B merely because both were collected
    in the same window.
    """
    payload = _json_object(text)
    _require_exact_fields(payload, V2_X_CHUNK_FIELDS, "invalid_v2_x_chunk")
    if payload.get("schema_version") != "v2-x-chunk" or not isinstance(payload.get("analyses"), list):
        raise SchemaError("invalid_v2_x_chunk", "schema version or analyses is invalid")
    analyses: list[dict[str, Any]] = []
    seen: set[str] = set()
    for value in payload["analyses"]:
        if not isinstance(value, Mapping):
            raise SchemaError("invalid_v2_x_analysis", "analysis must be an object")
        _require_exact_fields(value, V2_X_ANALYSIS_FIELDS, "invalid_v2_x_analysis")
        post_id = value["post_id"]
        if not _non_empty_string(post_id) or post_id not in allowed_post_ids or post_id in seen:
            raise SchemaError("invalid_v2_x_analysis", "analysis must name one unique allowed post")
        seen.add(post_id)
        if isinstance(allowed_context_post_ids, Mapping):
            context_ids = allowed_context_post_ids.get(post_id)
            if not isinstance(context_ids, set) or not all(_non_empty_string(value) for value in context_ids):
                raise SchemaError("invalid_v2_x_chunk", "post bundle context is invalid")
        else:
            context_ids = allowed_context_post_ids
        if any(value[field] is not None and not _non_empty_string(value[field]) for field in ("blogger_viewpoint", "quoted_post_viewpoint")):
            raise SchemaError("invalid_v2_x_analysis", "viewpoints must be a string or null")
        if not _string_list(value["arguments"]) or not _string_list(value["uncertainties"]):
            raise SchemaError("invalid_v2_x_analysis", "arguments and uncertainties must be string arrays")
        evidence = value["evidence_post_ids"]
        if not _non_empty_string_list(evidence) or len(set(evidence)) != len(evidence) or not set(evidence) <= ({post_id} | context_ids):
            raise SchemaError("evidence", "analysis evidence is outside its post bundle")
        link = value["post_link"]
        if not _non_empty_string(link) or not link.startswith("https://") or "/status/" not in link:
            raise SchemaError("invalid_v2_x_analysis", "post_link must be an HTTPS post link")
        analyses.append(dict(value))
    if seen != allowed_post_ids:
        raise SchemaError("invalid_v2_x_chunk", "exactly one analysis is required for every input post")
    return {"schema_version": "v2-x-chunk", "analyses": analyses}


def parse_v2_x_window_output(text: str, allowed_analysis_ids: set[str]) -> dict[str, Any]:
    payload = _json_object(text)
    _require_exact_fields(payload, V2_X_WINDOW_FIELDS, "invalid_v2_x_window")
    if payload.get("schema_version") != "v2-x-window" or not _valid_date(payload.get("natural_date")):
        raise SchemaError("invalid_v2_x_window", "schema version or natural date is invalid")
    if not _non_empty_string(payload["range_task_id"]):
        raise SchemaError("invalid_v2_x_window", "range task identity is invalid")
    if not _valid_instant(payload["occurred_from_at"]) or not _valid_instant(payload["occurred_through_at"]) or payload["occurred_from_at"] > payload["occurred_through_at"]:
        raise SchemaError("invalid_v2_x_window", "window instants are invalid")
    if not _string_list(payload["window_viewpoints"]) or not _string_list(payload["uncertainties"]):
        raise SchemaError("invalid_v2_x_window", "window text fields must be string arrays")
    for field in ("analysis_ids", "evidence_post_ids"):
        if not _non_empty_string_list(payload[field]) or len(set(payload[field])) != len(payload[field]):
            raise SchemaError("invalid_v2_x_window", f"{field} must be unique and non-empty")
    if not set(payload["analysis_ids"]) <= allowed_analysis_ids:
        raise SchemaError("analysis", "window cites an unpersisted post analysis")
    return dict(payload)


def parse_v2_x_cross_blogger_output(
    text: str,
    *,
    allowed_source_ids: set[str],
    allowed_analysis_ids: set[str],
    allowed_post_ids: set[str],
) -> dict[str, object]:
    """Validate the safe, cross-blogger completion sent to the control plane."""

    payload = _json_object(text)
    _require_exact_fields(payload, V2_X_CROSS_BLOGGER_FIELDS, "invalid_v2_x_cross_blogger")
    if payload.get("schema_version") != "v2-x-cross-blogger":
        raise SchemaError("invalid_v2_x_cross_blogger", "schema_version must be v2-x-cross-blogger")
    if not isinstance(payload.get("stock_viewpoints"), list) or not isinstance(payload.get("market_industry_viewpoints"), list):
        raise SchemaError("invalid_v2_x_cross_blogger", "viewpoints must be arrays")
    if not _string_list(payload.get("uncertainties")):
        raise SchemaError("invalid_v2_x_cross_blogger", "uncertainties must be a string array")

    def normalized_items(values: list[object], category: str) -> list[dict[str, object]]:
        result: list[dict[str, object]] = []
        for index, value in enumerate(values):
            if not isinstance(value, Mapping):
                raise SchemaError("invalid_v2_x_cross_blogger_item", f"{category} item {index} must be an object")
            _require_exact_fields(value, V2_X_CROSS_BLOGGER_ITEM_FIELDS, "invalid_v2_x_cross_blogger_item")
            statement = value["statement"]
            if not _non_empty_string(statement):
                raise SchemaError("invalid_v2_x_cross_blogger_item", "statement must be a non-empty string")
            if _IMPERATIVE_INVESTMENT_RECOMMENDATION.search(statement):
                raise SchemaError("invalid_v2_x_cross_blogger_item", "imperative system investment recommendation is not allowed")
            supporting = value["supporting_source_ids"]
            dissenting = value["dissenting_source_ids"]
            if not _string_list(supporting) or not _string_list(dissenting) or len(set(supporting)) != len(supporting) or len(set(dissenting)) != len(dissenting):
                raise SchemaError("invalid_v2_x_cross_blogger_item", "source IDs must be unique string arrays")
            if not set(supporting) <= allowed_source_ids or not set(dissenting) <= allowed_source_ids:
                raise SchemaError("source", "unknown source")
            if set(supporting) & set(dissenting):
                raise SchemaError("source", "source cannot be both supporting and dissenting")
            analyses = value["analysis_ids"]
            if not _non_empty_string_list(analyses) or len(set(analyses)) != len(analyses):
                raise SchemaError("analysis", "analysis IDs must be unique and non-empty")
            if not set(analyses) <= allowed_analysis_ids:
                raise SchemaError("analysis", "unknown analysis")
            evidence = value["evidence_post_ids"]
            if not _non_empty_string_list(evidence):
                raise SchemaError("evidence", "evidence must be non-empty")
            if len(set(evidence)) != len(evidence):
                raise SchemaError("evidence", "duplicate evidence ID")
            if not set(evidence) <= allowed_post_ids:
                raise SchemaError("evidence", "unknown evidence post")
            if not _string_list(value["uncertainties"]):
                raise SchemaError("invalid_v2_x_cross_blogger_item", "uncertainties must be a string array")
            result.append(dict(value))
        return result

    return {
        "schema_version": "v2-x-cross-blogger",
        "stock_viewpoints": normalized_items(payload["stock_viewpoints"], "stock"),
        "market_industry_viewpoints": normalized_items(payload["market_industry_viewpoints"], "market_industry"),
        "uncertainties": list(payload["uncertainties"]),
    }


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


def parse_v1_1_chunk_output(text: str) -> dict[str, Any]:
    """Parse the first V1.1 layer: attributed, message-backed fact units."""

    payload = _json_object(text)
    _require_exact_fields(payload, V1_1_CHUNK_FIELDS, "invalid_v1_1_chunk")
    if payload.get("schema_version") != "v1.1-chunk":
        raise SchemaError("invalid_v1_1_chunk", "schema_version must be v1.1-chunk")
    facts = payload["facts"]
    if not isinstance(facts, list):
        raise SchemaError("invalid_v1_1_chunk", "facts must be an array")
    normalized_facts: list[dict[str, Any]] = []
    for index, fact in enumerate(facts):
        if not isinstance(fact, Mapping):
            raise SchemaError("invalid_v1_1_fact", f"fact {index} must be an object")
        _require_exact_fields(fact, V1_1_FACT_FIELDS, "invalid_v1_1_fact")
        for field in ("author_id", "topic", "viewpoint"):
            if not _non_empty_string(fact[field]):
                raise SchemaError("invalid_v1_1_fact", f"fact {index} {field} must be a non-empty string")
        for field in ("reasoning", "operation_tendency"):
            if fact[field] is not None and not _non_empty_string(fact[field]):
                raise SchemaError("invalid_v1_1_fact", f"fact {index} {field} must be a string or null")
        for field in ("methodology", "uncertainty"):
            if not _string_list(fact[field]):
                raise SchemaError("invalid_v1_1_fact", f"fact {index} {field} must be a string array")
        if not _non_empty_string_list(fact["source_message_ids"]):
            raise SchemaError("invalid_v1_1_fact", f"fact {index} source_message_ids must be a non-empty string array")
        if len(set(fact["source_message_ids"])) != len(fact["source_message_ids"]):
            raise SchemaError("invalid_v1_1_fact", f"fact {index} has duplicate source message IDs")
        normalized_facts.append(dict(fact))

    media_ids = payload["media_source_message_ids"]
    if not _string_list(media_ids) or len(set(media_ids)) != len(media_ids):
        raise SchemaError("invalid_media_sources", "media_source_message_ids must be a unique string array")
    warnings = payload["warnings"]
    if not _string_list(warnings):
        raise SchemaError("invalid_warnings", "warnings must be an array of strings")
    return {
        "schema_version": "v1.1-chunk",
        "facts": normalized_facts,
        "media_source_message_ids": list(media_ids),
        "warnings": list(warnings),
    }


def validate_v1_1_chunk_output(
    output: Mapping[str, Any],
    message_catalog: Mapping[str, tuple[str, str]],
    unparsed_media_ids: set[str],
) -> dict[str, Any]:
    """Ensure every first-layer assertion names observed authors and evidence."""

    normalized = parse_v1_1_chunk_output(json.dumps(dict(output), ensure_ascii=False))
    catalog = _validated_message_catalog(message_catalog)
    if not unparsed_media_ids <= set(catalog):
        unknown = sorted(unparsed_media_ids - set(catalog))[0]
        raise SchemaError("media_source_message_ids", f"unparsed media ID is not in input: {unknown}")
    media_ids = set(normalized["media_source_message_ids"])
    if media_ids != unparsed_media_ids:
        raise SchemaError("media_source_message_ids", "must cite every unparsed media message in current chunk")
    for fact in normalized["facts"]:
        source_ids = set(fact["source_message_ids"])
        unknown = source_ids - set(catalog)
        if unknown:
            raise SchemaError("source_message_ids", f"unknown message ID: {sorted(unknown)[0]}")
        author_id = fact["author_id"]
        if not any(catalog[message_id][0] == author_id for message_id in source_ids):
            raise SchemaError("author_id", "fact must cite a message from its stated author")
    return normalized


def parse_v1_1_daily_output(text: str) -> dict[str, Any]:
    """Parse the second V1.1 layer: configured author cards and viewpoints."""

    payload = _json_object(text)
    _require_exact_fields(payload, V1_1_DAILY_FIELDS, "invalid_v1_1_daily")
    if payload.get("schema_version") != "v1.1":
        raise SchemaError("invalid_v1_1_daily", "schema_version must be v1.1")
    if not _valid_date(payload["natural_date"]):
        raise SchemaError("invalid_v1_1_daily", "natural_date must be YYYY-MM-DD")
    if not _valid_instant(payload["as_of"]):
        raise SchemaError("invalid_v1_1_daily", "as_of must be an ISO-8601 instant")
    if not isinstance(payload["author_cards"], list) or not isinstance(payload["topic_discussions"], list):
        raise SchemaError("invalid_v1_1_daily", "author_cards and topic_discussions must be arrays")
    author_cards = [_parse_v1_1_author_card(card, index) for index, card in enumerate(payload["author_cards"])]
    topics = [_parse_v1_1_topic(topic, index) for index, topic in enumerate(payload["topic_discussions"])]
    if not _string_list(payload["warnings"]):
        raise SchemaError("invalid_warnings", "warnings must be an array of strings")
    return {
        "schema_version": "v1.1",
        "natural_date": payload["natural_date"],
        "as_of": payload["as_of"],
        "author_cards": author_cards,
        "topic_discussions": topics,
        "warnings": list(payload["warnings"]),
    }


def validate_v1_1_daily_output(
    output: Mapping[str, Any],
    message_catalog: Mapping[str, tuple[str, str]],
    configured_author_profiles: Mapping[str, str],
    *,
    fact_units: Sequence[Mapping[str, Any]],
    expected_natural_date: str,
    expected_as_of: str,
    unparsed_media_ids: set[str],
) -> dict[str, Any]:
    """Fail closed unless V1.1 daily conclusions stay within their evidence."""

    normalized = parse_v1_1_daily_output(json.dumps(dict(output), ensure_ascii=False))
    if normalized["natural_date"] != expected_natural_date or normalized["as_of"] != expected_as_of:
        raise SchemaError("daily_time_mismatch", "daily output must use the requested date and as_of instant")
    catalog = _validated_message_catalog(message_catalog)
    configured = _validated_configured_profiles(configured_author_profiles)
    fact_evidence_ids = _validated_fact_evidence_ids(fact_units)
    if not unparsed_media_ids <= set(catalog):
        unknown = sorted(unparsed_media_ids - set(catalog))[0]
        raise SchemaError("media_source_message_ids", f"unparsed media ID is not in daily evidence: {unknown}")
    if unparsed_media_ids and "存在未解析媒体" not in normalized["warnings"]:
        raise SchemaError("media_uncertainty", "daily output must surface unparsed media")
    conclusion_evidence_ids = fact_evidence_ids - unparsed_media_ids

    seen_cards: set[str] = set()
    for card in normalized["author_cards"]:
        author_id = card["author_id"]
        if author_id in seen_cards or configured.get(author_id) != card["author_display"]:
            raise SchemaError("author_card", "author card must belong to one configured author with its observed display")
        seen_cards.add(author_id)
        _validate_author_evidence(card["source_message_ids"], author_id, catalog, "author_card")
        _validate_fact_evidence(card["source_message_ids"], conclusion_evidence_ids, "author_card")
        for judgment in card["core_logic"]["stock_judgments"]:
            _validate_author_evidence(judgment["source_message_ids"], author_id, catalog, "stock_judgment")
            _validate_fact_evidence(judgment["source_message_ids"], conclusion_evidence_ids, "stock_judgment")

    for topic in normalized["topic_discussions"]:
        topic_ids = set(topic["source_message_ids"])
        _validate_known_evidence(topic_ids, catalog, "topic")
        _validate_fact_evidence(topic["source_message_ids"], conclusion_evidence_ids, "topic")
        for viewpoint in topic["viewpoints"]:
            author_id = viewpoint["author_id"]
            if any(catalog[message_id][0] != author_id or catalog[message_id][1] != viewpoint["author_display"]
                   for message_id in viewpoint["source_message_ids"]):
                raise SchemaError("viewpoint", "viewpoint evidence must belong to its named author")
            _validate_known_evidence(set(viewpoint["source_message_ids"]), catalog, "viewpoint")
            _validate_fact_evidence(viewpoint["source_message_ids"], conclusion_evidence_ids, "viewpoint")
            if not set(viewpoint["source_message_ids"]) <= topic_ids:
                raise SchemaError("topic", "topic evidence must include every viewpoint evidence ID")
    return normalized


def _parse_v1_1_author_card(value: object, index: int) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise SchemaError("invalid_author_card", f"author card {index} must be an object")
    _require_exact_fields(value, V1_1_AUTHOR_CARD_FIELDS, "invalid_author_card")
    if not _non_empty_string(value["author_id"]) or not _non_empty_string(value["author_display"]):
        raise SchemaError("invalid_author_card", f"author card {index} identity is invalid")
    core_logic = value["core_logic"]
    operation = value["operation_tendency"]
    if not isinstance(core_logic, Mapping) or not isinstance(operation, Mapping):
        raise SchemaError("invalid_author_card", f"author card {index} nested fields are invalid")
    _require_exact_fields(core_logic, V1_1_CORE_LOGIC_FIELDS, "invalid_author_card")
    _require_exact_fields(operation, V1_1_OPERATION_FIELDS, "invalid_author_card")
    if core_logic["market_trend"] is not None and not _non_empty_string(core_logic["market_trend"]):
        raise SchemaError("invalid_author_card", f"author card {index} market_trend is invalid")
    if not isinstance(core_logic["stock_judgments"], list):
        raise SchemaError("invalid_author_card", f"author card {index} stock_judgments must be an array")
    judgments = [_parse_v1_1_stock_judgment(item, index, item_index) for item_index, item in enumerate(core_logic["stock_judgments"])]
    for field in ("market", "stocks"):
        if operation[field] is not None and not _non_empty_string(operation[field]):
            raise SchemaError("invalid_author_card", f"author card {index} operation tendency is invalid")
    for field in ("methodology", "uncertainty"):
        if not _string_list(value[field]):
            raise SchemaError("invalid_author_card", f"author card {index} {field} must be a string array")
    if not _non_empty_string_list(value["source_message_ids"]):
        raise SchemaError("invalid_author_card", f"author card {index} requires evidence")
    return {
        **dict(value),
        "core_logic": {"market_trend": core_logic["market_trend"], "stock_judgments": judgments},
        "operation_tendency": dict(operation),
    }


def _parse_v1_1_stock_judgment(value: object, card_index: int, index: int) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise SchemaError("invalid_stock_judgment", f"author card {card_index} stock judgment {index} must be an object")
    _require_exact_fields(value, V1_1_STOCK_JUDGMENT_FIELDS, "invalid_stock_judgment")
    if value["subject"] is not None and not _non_empty_string(value["subject"]):
        raise SchemaError("invalid_stock_judgment", "subject must be a string or null")
    if not _non_empty_string(value["judgment"]):
        raise SchemaError("invalid_stock_judgment", "judgment must be a non-empty string")
    if value["reasoning"] is not None and not _non_empty_string(value["reasoning"]):
        raise SchemaError("invalid_stock_judgment", "reasoning must be a string or null")
    if not _non_empty_string_list(value["source_message_ids"]):
        raise SchemaError("invalid_stock_judgment", "stock judgment requires evidence")
    return dict(value)


def _parse_v1_1_topic(value: object, index: int) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise SchemaError("invalid_topic_discussion", f"topic {index} must be an object")
    _require_exact_fields(value, V1_1_TOPIC_FIELDS, "invalid_topic_discussion")
    if not _non_empty_string(value["title"]) or not _non_empty_string(value["summary"]):
        raise SchemaError("invalid_topic_discussion", f"topic {index} title and summary are required")
    if not isinstance(value["viewpoints"], list) or not _string_list(value["uncertainty"]):
        raise SchemaError("invalid_topic_discussion", f"topic {index} viewpoints and uncertainty are invalid")
    if not _non_empty_string_list(value["source_message_ids"]):
        raise SchemaError("invalid_topic_discussion", f"topic {index} requires evidence")
    viewpoints = [_parse_v1_1_viewpoint(item, index, item_index) for item_index, item in enumerate(value["viewpoints"])]
    return {**dict(value), "viewpoints": viewpoints}


def _parse_v1_1_viewpoint(value: object, topic_index: int, index: int) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise SchemaError("invalid_viewpoint", f"topic {topic_index} viewpoint {index} must be an object")
    _require_exact_fields(value, V1_1_VIEWPOINT_FIELDS, "invalid_viewpoint")
    for field in ("author_id", "author_display", "viewpoint"):
        if not _non_empty_string(value[field]):
            raise SchemaError("invalid_viewpoint", f"viewpoint {field} must be a non-empty string")
    for field in ("reasoning", "operation_tendency"):
        if value[field] is not None and not _non_empty_string(value[field]):
            raise SchemaError("invalid_viewpoint", f"viewpoint {field} must be a string or null")
    if not _non_empty_string_list(value["source_message_ids"]):
        raise SchemaError("invalid_viewpoint", "viewpoint requires evidence")
    return dict(value)


def _json_object(text: str) -> Mapping[str, Any]:
    normalized = _remove_json_fence(text)
    try:
        payload = json.loads(normalized)
    except (json.JSONDecodeError, TypeError) as exc:
        raise SchemaError("invalid_json", str(exc)) from exc
    if not isinstance(payload, Mapping):
        raise SchemaError("invalid_shape", "top-level JSON must be an object")
    return payload


def _require_exact_fields(value: Mapping[str, Any], expected: frozenset[str], code: str) -> None:
    missing = sorted(expected - set(value))
    unknown = sorted(set(value) - expected)
    if missing or unknown:
        detail = ", ".join(([f"missing {item}" for item in missing] + [f"unknown {item}" for item in unknown]))
        raise SchemaError(code, detail)


def _validated_message_catalog(message_catalog: Mapping[str, tuple[str, str]]) -> dict[str, tuple[str, str]]:
    catalog: dict[str, tuple[str, str]] = {}
    for message_id, identity in message_catalog.items():
        if not _non_empty_string(message_id) or not isinstance(identity, tuple) or len(identity) != 2:
            raise SchemaError("invalid_message_catalog", "message identity catalog is invalid")
        author_id, author_display = identity
        if not _non_empty_string(author_id) or not _non_empty_string(author_display):
            raise SchemaError("invalid_message_catalog", "message author identity is invalid")
        catalog[message_id] = (author_id, author_display)
    return catalog


def _validated_configured_profiles(profiles: Mapping[str, str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for author_id, display in profiles.items():
        if not _non_empty_string(author_id) or not _non_empty_string(display):
            raise SchemaError("invalid_author_profiles", "configured author profiles are invalid")
        result[author_id] = display
    return result


def _validate_known_evidence(source_ids: set[str], catalog: Mapping[str, tuple[str, str]], kind: str) -> None:
    unknown = source_ids - set(catalog)
    if unknown:
        raise SchemaError("source_message_ids", f"{kind} has unknown message ID: {sorted(unknown)[0]}")


def _validate_author_evidence(source_ids: list[str], author_id: str, catalog: Mapping[str, tuple[str, str]], kind: str) -> None:
    _validate_known_evidence(set(source_ids), catalog, kind)
    if any(catalog[message_id][0] != author_id for message_id in source_ids):
        raise SchemaError(kind, "author evidence must belong to the named author")


def _validated_fact_evidence_ids(fact_units: Sequence[Mapping[str, Any]]) -> set[str]:
    evidence_ids: set[str] = set()
    for index, fact in enumerate(fact_units):
        if not isinstance(fact, Mapping) or not _non_empty_string_list(fact.get("source_message_ids")):
            raise SchemaError("invalid_fact_units", f"fact unit {index} requires source message IDs")
        evidence_ids.update(fact["source_message_ids"])
    return evidence_ids


def _validate_fact_evidence(source_ids: list[str], fact_evidence_ids: set[str], kind: str) -> None:
    unsupported = set(source_ids) - fact_evidence_ids
    if unsupported:
        raise SchemaError("source_message_ids", f"{kind} must cite validated fact evidence: {sorted(unsupported)[0]}")


def _non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _non_empty_string_list(value: object) -> bool:
    return _string_list(value) and bool(value)


def _valid_date(value: object) -> bool:
    if not _non_empty_string(value):
        return False
    try:
        date.fromisoformat(value)
    except ValueError:
        return False
    return True


def _valid_instant(value: object) -> bool:
    if not _non_empty_string(value):
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


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
