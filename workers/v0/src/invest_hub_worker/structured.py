from __future__ import annotations

import json
import re
import unicodedata
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
V3_X_POST_FIELDS = frozenset({"schema_version", "analyses"})
V3_X_POST_ANALYSIS_FIELDS = frozenset({"post_id", "investment_relevance", "investment_categories", "blogger_viewpoint", "action_intent", "action_scope", "conditions", "arguments", "quoted_post_viewpoint", "uncertainties", "evidence_post_ids", "post_link"})
V3_X_INVESTMENT_RELEVANCE = frozenset({"investment_related", "not_investment_related"})
V3_X_INVESTMENT_CATEGORIES = frozenset({"security_industry", "market_structure", "strategy_mindset"})
V3_X_WINDOW_FIELDS = frozenset({"schema_version", "natural_date", "range_task_id", "occurred_from_at", "occurred_through_at", "security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints", "analysis_ids", "evidence_post_ids", "uncertainties"})
V3_X_WINDOW_ITEM_FIELDS = frozenset({"statement", "action_intent", "action_scope", "conditions", "analysis_ids", "evidence_post_ids", "uncertainties"})
V3_X_CROSS_BLOGGER_FIELDS = frozenset({"schema_version", "security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints", "uncertainties"})
V3_X_CROSS_BLOGGER_ITEM_FIELDS = frozenset({"statement", "action_intent", "action_scope", "conditions", "supporting_source_ids", "dissenting_source_ids", "analysis_ids", "evidence_post_ids", "uncertainties"})
V3_X_ACTION_INTENTS = frozenset({"build_position", "buy", "add", "hold", "reduce", "sell", "watch", "avoid", "none"})
V4_X_POST_FIELDS = V3_X_POST_FIELDS
V4_X_POST_ANALYSIS_FIELDS = V3_X_POST_ANALYSIS_FIELDS | frozenset({"action_scope_status"})
V4_X_WINDOW_FIELDS = V3_X_WINDOW_FIELDS
V4_X_WINDOW_ITEM_FIELDS = V3_X_WINDOW_ITEM_FIELDS | frozenset({"action_scope_status"})
V4_X_CROSS_BLOGGER_FIELDS = V3_X_CROSS_BLOGGER_FIELDS
V4_X_CROSS_BLOGGER_ITEM_FIELDS = V3_X_CROSS_BLOGGER_ITEM_FIELDS | frozenset({"action_scope_status"})
V4_X_ACTION_SCOPE_STATUSES = frozenset({"specified", "unspecified", "not_applicable"})
V5_X_CROSS_BLOGGER_FIELDS = frozenset({
    "schema_version", "ai_synthesis", "security_industry_theses",
    "market_structure_theses", "strategy_mindset_theses", "uncertainties",
})
V5_X_AI_SYNTHESIS_FIELDS = frozenset({"cross_blogger_integrations", "ai_assessments"})
V5_X_THESIS_FIELDS = frozenset({
    "thesis_id", "headline", "synthesis", "scenario_branches", "attributed_actions",
    "supporting_source_ids", "dissenting_source_ids", "analysis_ids",
    "evidence_post_ids", "uncertainties",
})
V5_X_SCENARIO_FIELDS = frozenset({
    "condition", "outcome", "source_ids", "analysis_ids", "evidence_post_ids", "uncertainties",
})
V5_X_ACTION_FIELDS = frozenset({
    "source_id", "action_intent", "action_scope_status", "action_scope",
    "conditions", "analysis_ids", "evidence_post_ids", "uncertainties",
})
V5_X_ACTION_INTENTS = frozenset({"build_position", "buy", "add", "hold", "reduce", "sell", "watch", "avoid"})
V5_X_ACTION_SCOPE_STATUSES = frozenset({"specified", "unspecified"})
V5_X_TEXT_LIMITS = {
    "top_uncertainties": 500,
    "thesis_headline": 300,
    "thesis_synthesis": 2000,
    "thesis_uncertainties": 500,
    "scenario_condition": 500,
    "scenario_outcome": 1000,
    "scenario_uncertainties": 500,
    "action_scope": 300,
    "action_conditions": 500,
    "action_uncertainties": 500,
    "integration_headline": 300,
    "integration_synthesis": 2000,
    "integration_uncertainties": 500,
    "common_statement": 1000,
    "conflict_issue": 1000,
    "conflict_position": 1000,
    "assessment_headline": 300,
    "assessment_judgement": 2000,
    "assessment_importance_reason": 1000,
    "assessment_reasoning": 2000,
    "assessment_arrays": 500,
}
V5_X_INTEGRATION_FIELDS = frozenset({
    "integration_id", "headline", "synthesis", "common_points",
    "conflict_points", "related_thesis_ids", "uncertainties",
})
V5_X_COMMON_POINT_FIELDS = frozenset({"statement", "source_ids", "related_thesis_ids"})
V5_X_CONFLICT_FIELDS = frozenset({"issue", "positions"})
V5_X_POSITION_FIELDS = frozenset({"position", "source_ids", "related_thesis_ids"})
V5_X_ASSESSMENT_FIELDS = frozenset({
    "assessment_id", "headline", "judgement", "importance_reason", "reasoning",
    "key_assumptions", "risks", "watch_variables", "related_thesis_ids", "uncertainties",
})
V5_X_ID_PATTERNS = {
    "security_industry_theses": re.compile(r"^security-(\d{2})$"),
    "market_structure_theses": re.compile(r"^market-(\d{2})$"),
    "strategy_mindset_theses": re.compile(r"^strategy-(\d{2})$"),
    "cross_blogger_integrations": re.compile(r"^integration-(\d{2})$"),
    "ai_assessments": re.compile(r"^assessment-(\d{2})$"),
}
_IMPERATIVE_INVESTMENT_RECOMMENDATION = re.compile(r"(?:系统\s*)?(?:建议|应当|应该|必须|请|立即).{0,24}(?:买入|卖出|加仓|减仓|建仓|清仓|抄底|追涨)")
_STRONG_CONSENSUS_WORDING = re.compile(r"(?:共识|一致认为|共同认为|市场(?:已经|已)?确认)")
_UNSPECIFIED_SCOPE_WORDING = re.compile(r"(?:(?:未|不|无法)(?:明确|说明|提供|确认)|未知).{0,24}(?:标的|对象|资产|范围)|(?:标的|对象|资产|范围).{0,24}(?:(?:未|不|无法)(?:明确|说明|提供|确认)|未知)")
_INPUT_MARKET_TOKEN = re.compile(r"(?:\b[A-Z]{2,5}\b|\b\d+(?:\.\d+)?%?\b|(?:USD|HKD|CNY|RMB|JPY|EUR|GBP|AUD|CAD|SGD|TWD|NTD|KRW|CHF|MXN|INR|SEK|NOK|DKK)\s?\d+(?:\.\d+)?|[$¥￥€]-?\d+(?:\.\d+)?(?:%|[KMBT]|万|亿)?|-?\d+(?:\.\d+)?%)")
_V5_PRIVATE_PREFIX = re.compile(r"^(?:local_evidence(_path)?|local_path|raw_x_content|raw_content|cookie|browser[_ -]?profile)[\s:=/\\]", re.IGNORECASE)


def _is_safe_v5_text(value: object, max_length: int) -> bool:
    if not isinstance(value, str) or not 1 <= len(value) <= max_length:
        return False
    if any(unicodedata.category(character) == "Cc" for character in value):
        return False
    stripped = value.lstrip()
    return not (
        stripped.startswith("/")
        or bool(re.match(r"^[A-Za-z]:[\\/]", stripped))
        or stripped.lower().startswith("file:")
        or bool(_V5_PRIVATE_PREFIX.match(stripped))
    )


def _validate_analysis_evidence_catalog(
    allowed_analysis_ids: set[str],
    analysis_evidence_post_ids: Mapping[str, set[str]],
) -> None:
    if (
        not isinstance(analysis_evidence_post_ids, Mapping)
        or set(analysis_evidence_post_ids) != allowed_analysis_ids
        or any(
            not isinstance(evidence_ids, set)
            or not evidence_ids
            or any(not _non_empty_string(post_id) for post_id in evidence_ids)
            for evidence_ids in analysis_evidence_post_ids.values()
        )
    ):
        raise SchemaError("analysis", "analysis evidence catalog is incomplete")


def _validate_v4_action_scope(value: Mapping[str, Any]) -> str:
    action_intent = value.get("action_intent")
    action_scope_status = value.get("action_scope_status")
    action_scope = value.get("action_scope")
    if action_intent not in V3_X_ACTION_INTENTS or action_scope_status not in V4_X_ACTION_SCOPE_STATUSES or not isinstance(action_scope, str):
        raise SchemaError("action scope", "action intent, scope status, or scope is invalid")
    if action_intent == "none":
        if action_scope_status != "not_applicable" or action_scope:
            raise SchemaError("action scope", "none action must use not_applicable with an empty scope")
    elif action_scope_status == "specified":
        if not action_scope.strip() or _UNSPECIFIED_SCOPE_WORDING.search(action_scope):
            raise SchemaError("action scope", "specified action scope must be an explicit object, not a missing-object explanation")
    elif action_scope_status == "unspecified":
        if action_scope:
            raise SchemaError("action scope", "unspecified action scope must be empty")
    else:
        raise SchemaError("action scope", "non-none action must have specified or unspecified scope status")
    return str(action_scope_status)


def _validate_v5_action_scope(value: Mapping[str, Any]) -> str:
    action_intent = value.get("action_intent")
    action_scope_status = value.get("action_scope_status")
    action_scope = value.get("action_scope")
    if action_intent not in V5_X_ACTION_INTENTS or action_scope_status not in V5_X_ACTION_SCOPE_STATUSES or not isinstance(action_scope, str):
        raise SchemaError("action", "V5 action intent or scope status is invalid")
    if action_scope_status == "specified":
        if not _is_safe_v5_text(action_scope, V5_X_TEXT_LIMITS["action_scope"]) or _UNSPECIFIED_SCOPE_WORDING.search(action_scope):
            raise SchemaError("action", "specified action scope must be an explicit safe object")
    elif action_scope != "":
        raise SchemaError("action", "unspecified action scope must be empty")
    return str(action_scope_status)


def _v4_payload_for_v3_validation(
    text: str,
    *,
    root_fields: frozenset[str],
    item_fields: frozenset[str],
    v4_schema_version: str,
    v3_schema_version: str,
    item_groups: tuple[str, ...],
    error_code: str,
) -> tuple[str, list[str]]:
    """Validate v4's action-scope state before reusing v3 evidence checks.

    v3 has the same evidence, ownership and safety rules, but requires a
    non-empty scope for every non-none action.  The private sentinel exists
    only in this in-memory handoff and is restored to an empty scope before
    the v4 result leaves this module.
    """

    payload = _json_object(text)
    _require_exact_fields(payload, root_fields, error_code)
    if payload.get("schema_version") != v4_schema_version:
        raise SchemaError(error_code, "schema version is invalid")
    normalized = dict(payload)
    statuses: list[str] = []
    for group in item_groups:
        values = payload.get(group)
        if not isinstance(values, list):
            raise SchemaError(error_code, "viewpoints must be arrays")
        normalized_items: list[dict[str, Any]] = []
        for value in values:
            if not isinstance(value, Mapping):
                raise SchemaError(error_code, "analysis or viewpoint item must be an object")
            _require_exact_fields(value, item_fields, error_code)
            status = _validate_v4_action_scope(value)
            statuses.append(status)
            normalized_value = dict(value)
            normalized_value.pop("action_scope_status")
            if status == "unspecified":
                normalized_value["action_scope"] = "scope unspecified in source"
            normalized_items.append(normalized_value)
        normalized[group] = normalized_items
    normalized["schema_version"] = v3_schema_version
    return json.dumps(normalized, ensure_ascii=False), statuses


def _restore_v4_action_scope_status(output: dict[str, Any], *, schema_version: str, item_groups: tuple[str, ...], statuses: list[str]) -> dict[str, Any]:
    status_iter = iter(statuses)
    for group in item_groups:
        for item in output[group]:
            status = next(status_iter)
            item["action_scope_status"] = status
            if status == "unspecified":
                item["action_scope"] = ""
    output["schema_version"] = schema_version
    return output


def parse_v4_x_post_analysis_output(
    text: str,
    allowed_post_ids: set[str],
    allowed_context_post_ids: Mapping[str, set[str]] | set[str],
) -> dict[str, Any]:
    normalized, statuses = _v4_payload_for_v3_validation(
        text, root_fields=V4_X_POST_FIELDS, item_fields=V4_X_POST_ANALYSIS_FIELDS,
        v4_schema_version="v4-x-post-analysis", v3_schema_version="v3-x-post-analysis",
        item_groups=("analyses",), error_code="invalid_v4_x_post",
    )
    return _restore_v4_action_scope_status(
        parse_v3_x_post_analysis_output(normalized, allowed_post_ids, allowed_context_post_ids),
        schema_version="v4-x-post-analysis", item_groups=("analyses",), statuses=statuses,
    )


def parse_v4_x_window_output(
    text: str,
    allowed_analysis_ids: set[str],
    analysis_evidence_post_ids: Mapping[str, set[str]],
) -> dict[str, Any]:
    groups = ("security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints")
    _validate_analysis_evidence_catalog(allowed_analysis_ids, analysis_evidence_post_ids)
    normalized, statuses = _v4_payload_for_v3_validation(
        text, root_fields=V4_X_WINDOW_FIELDS, item_fields=V4_X_WINDOW_ITEM_FIELDS,
        v4_schema_version="v4-x-window", v3_schema_version="v3-x-window", item_groups=groups,
        error_code="invalid_v4_x_window",
    )
    projected = _json_object(normalized)
    for group in groups:
        for item in projected[group]:
            analysis_ids = item.get("analysis_ids")
            if isinstance(analysis_ids, list) and set(analysis_ids) <= allowed_analysis_ids:
                item["evidence_post_ids"] = sorted(
                    set().union(*(analysis_evidence_post_ids[analysis_id] for analysis_id in analysis_ids))
                )
    normalized = json.dumps(projected, ensure_ascii=False)
    return _restore_v4_action_scope_status(
        parse_v3_x_window_output(normalized, allowed_analysis_ids, analysis_evidence_post_ids),
        schema_version="v4-x-window", item_groups=groups, statuses=statuses,
    )


def parse_v4_x_cross_blogger_output(
    text: str,
    **kwargs: Any,
) -> dict[str, object]:
    groups = ("security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints")
    normalized, statuses = _v4_payload_for_v3_validation(
        text, root_fields=V4_X_CROSS_BLOGGER_FIELDS, item_fields=V4_X_CROSS_BLOGGER_ITEM_FIELDS,
        v4_schema_version="v4-x-cross-blogger", v3_schema_version="v3-x-cross-blogger", item_groups=groups,
        error_code="invalid_v4_x_cross_blogger",
    )
    return _restore_v4_action_scope_status(
        parse_v3_x_cross_blogger_output(normalized, **kwargs),
        schema_version="v4-x-cross-blogger", item_groups=groups, statuses=statuses,
    )

def parse_v5_x_cross_blogger_output(
    text: str,
    *,
    allowed_source_ids: set[str],
    allowed_analysis_ids: set[str],
    allowed_post_ids: set[str],
    analysis_source_ids: Mapping[str, str],
    analysis_evidence_post_ids: Mapping[str, set[str]],
    frozen_source_ids: set[str] | None = None,
    opaque_context_ids: Mapping[str, set[str]] | None = None,
    input_sources: Sequence[Mapping[str, Any]],
) -> dict[str, object]:
    payload = _json_object(text)
    _require_exact_fields(payload, V5_X_CROSS_BLOGGER_FIELDS, "invalid_v5_x_cross_blogger")
    if payload.get("schema_version") != "v5-x-cross-blogger":
        raise SchemaError("invalid_v5_x_cross_blogger", "schema_version must be v5-x-cross-blogger")
    categories = ("security_industry_theses", "market_structure_theses", "strategy_mindset_theses")
    if not all(isinstance(payload.get(category), list) for category in categories):
        raise SchemaError("invalid_v5_x_cross_blogger", "theses must be arrays")
    if not _string_list(payload.get("uncertainties")):
        raise SchemaError("invalid_v5_x_cross_blogger", "uncertainties must be a string array")
    if not isinstance(payload.get("ai_synthesis"), Mapping):
        raise SchemaError("invalid_v5_x_cross_blogger", "ai_synthesis must be an object")
    opaque_source_ids = frozen_source_ids if frozen_source_ids is not None else allowed_source_ids
    if not allowed_source_ids <= opaque_source_ids or not all(_non_empty_string(source_id) for source_id in opaque_source_ids):
        raise SchemaError("source", "frozen source catalog is invalid")
    _validate_analysis_evidence_catalog(allowed_analysis_ids, analysis_evidence_post_ids)
    for analysis_id in allowed_analysis_ids:
        source_id = analysis_source_ids.get(analysis_id)
        evidence_ids = analysis_evidence_post_ids.get(analysis_id)
        if source_id not in allowed_source_ids or not isinstance(evidence_ids, set) or not evidence_ids or not evidence_ids <= allowed_post_ids:
            raise SchemaError("analysis", "analysis ownership catalog is invalid")
    context_catalog = opaque_context_ids or {}
    if not set(context_catalog) <= {"batch", "run", "segment"} or any(
        not isinstance(opaque_ids, set) or not all(_non_empty_string(opaque_id) for opaque_id in opaque_ids)
        for opaque_ids in context_catalog.values()
    ):
        raise SchemaError("context", "opaque context catalog is invalid")
    opaque_catalogs = (
        ("batch", context_catalog.get("batch", set())),
        ("run", context_catalog.get("run", set())),
        ("segment", context_catalog.get("segment", set())),
        ("analysis", allowed_analysis_ids),
        ("source", opaque_source_ids),
        ("evidence", allowed_post_ids),
    )
    for opaque_kind, opaque_ids in opaque_catalogs:
        _reject_opaque_ids(payload["uncertainties"], opaque_ids, opaque_kind)
    input_market_tokens = _extract_market_tokens(input_sources)

    seen_ids: set[str] = set()
    thesis_by_id: dict[str, dict[str, Any]] = {}
    thesis_sources: dict[str, set[str]] = {}

    def reject_free_text(
        values: Sequence[object],
        *,
        code: str,
        allow_consensus: bool,
        max_length: int,
        check_market_tokens: bool = False,
    ) -> None:
        for value in values:
            if not _is_safe_v5_text(value, max_length):
                raise SchemaError(code, "natural text is invalid")
            assert isinstance(value, str)
            if _IMPERATIVE_INVESTMENT_RECOMMENDATION.search(value):
                raise SchemaError("recommendation", "imperative system investment recommendation is not allowed")
            if _STRONG_CONSENSUS_WORDING.search(value) and not allow_consensus:
                raise SchemaError("consensus", "strong consensus wording is not supported by the cited sources")
            for opaque_kind, opaque_ids in opaque_catalogs:
                _reject_opaque_ids([value], opaque_ids, opaque_kind)
            if check_market_tokens:
                candidate_tokens = _extract_market_tokens(value)
                if not candidate_tokens <= input_market_tokens:
                    raise SchemaError("assessment", "assessment introduces an out-of-context market token")

    reject_free_text(
        payload["uncertainties"],
        code="uncertainty",
        allow_consensus=True,
        max_length=V5_X_TEXT_LIMITS["top_uncertainties"],
    )

    def validate_string_array(values: object, *, code: str) -> list[str]:
        if not _string_list(values) or len(set(values)) != len(values):
            raise SchemaError(code, "text arrays must contain unique strings")
        return list(values)

    def validate_source_ids(values: object, *, code: str, allow_empty: bool) -> list[str]:
        if not _string_list(values) or len(set(values)) != len(values):
            raise SchemaError(code, "source IDs must be unique string arrays")
        source_ids = list(values)
        if (not allow_empty and not source_ids) or not set(source_ids) <= allowed_source_ids:
            raise SchemaError("source", "unknown source")
        return source_ids

    def validate_analysis_ids(values: object, *, code: str, parent_analysis_ids: set[str] | None = None) -> list[str]:
        if not _non_empty_string_list(values) or len(set(values)) != len(values):
            raise SchemaError("analysis", "analysis IDs must be unique and non-empty")
        analysis_ids = list(values)
        if not set(analysis_ids) <= allowed_analysis_ids:
            raise SchemaError("analysis", "unknown analysis")
        if parent_analysis_ids is not None and not set(analysis_ids) <= parent_analysis_ids:
            raise SchemaError(code, "nested analyses must stay within the parent thesis")
        return analysis_ids

    def validate_evidence_ids(values: object, *, expected: set[str], code: str, allow_empty: bool = False) -> list[str]:
        if (allow_empty and values == []):
            return []
        if not _non_empty_string_list(values) or len(set(values)) != len(values):
            raise SchemaError("evidence", "evidence must be a unique non-empty string array")
        evidence_ids = list(values)
        if not set(evidence_ids) <= allowed_post_ids:
            raise SchemaError("evidence", "unknown evidence post")
        if set(evidence_ids) != expected:
            raise SchemaError(code, "evidence does not match analyses")
        return evidence_ids

    def validate_related_thesis_ids(values: object, *, code: str) -> list[str]:
        if not _non_empty_string_list(values) or len(set(values)) != len(values):
            raise SchemaError(code, "related thesis IDs must be unique and non-empty")
        thesis_ids = list(values)
        if not set(thesis_ids) <= set(thesis_by_id):
            raise SchemaError("thesis", "unknown related thesis")
        return thesis_ids

    def validate_thesis_group(group_name: str) -> list[dict[str, Any]]:
        values = payload[group_name]
        assert isinstance(values, list)
        pattern = V5_X_ID_PATTERNS[group_name]
        normalized: list[dict[str, Any]] = []
        for index, value in enumerate(values, start=1):
            if not isinstance(value, Mapping):
                raise SchemaError("thesis", f"{group_name} thesis must be an object")
            _require_exact_fields(value, V5_X_THESIS_FIELDS, "thesis")
            match = pattern.fullmatch(str(value.get("thesis_id")))
            if not match or int(match.group(1)) != index:
                raise SchemaError("thesis", "thesis IDs must be consecutive and category-scoped")
            thesis_id = str(value["thesis_id"])
            if thesis_id in seen_ids:
                raise SchemaError("thesis", "thesis IDs must be globally unique")
            seen_ids.add(thesis_id)
            headline = value["headline"]
            synthesis = value["synthesis"]
            supporting = validate_source_ids(value["supporting_source_ids"], code="thesis", allow_empty=False)
            dissenting = validate_source_ids(value["dissenting_source_ids"], code="thesis", allow_empty=True)
            if set(supporting) & set(dissenting):
                raise SchemaError("source", "source cannot be both supporting and dissenting")
            analysis_ids = validate_analysis_ids(value["analysis_ids"], code="thesis")
            analysis_sources = {analysis_source_ids[analysis_id] for analysis_id in analysis_ids}
            thesis_source_union = set(supporting) | set(dissenting)
            if analysis_sources != thesis_source_union:
                raise SchemaError("source", "analysis/source ownership mismatch")
            evidence_expected = set().union(*(analysis_evidence_post_ids[analysis_id] for analysis_id in analysis_ids))
            evidence_ids = validate_evidence_ids(value["evidence_post_ids"], expected=evidence_expected, code="evidence")
            uncertainties = validate_string_array(value["uncertainties"], code="thesis")
            for opaque_kind, opaque_ids in opaque_catalogs:
                _reject_opaque_ids(uncertainties, opaque_ids, opaque_kind)
            allow_consensus = len(supporting) >= 2 and not dissenting
            reject_free_text([headline], code="thesis", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["thesis_headline"], check_market_tokens=True)
            reject_free_text([synthesis], code="thesis", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["thesis_synthesis"], check_market_tokens=True)
            reject_free_text(uncertainties, code="thesis", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["thesis_uncertainties"], check_market_tokens=True)

            scenarios = value["scenario_branches"]
            if not isinstance(scenarios, list):
                raise SchemaError("scenario", "scenario branches must be an array")
            normalized_scenarios: list[dict[str, Any]] = []
            for scenario in scenarios:
                if not isinstance(scenario, Mapping):
                    raise SchemaError("scenario", "scenario branch must be an object")
                _require_exact_fields(scenario, V5_X_SCENARIO_FIELDS, "scenario")
                source_ids = validate_source_ids(scenario["source_ids"], code="scenario", allow_empty=False)
                if not set(source_ids) <= thesis_source_union:
                    raise SchemaError("scenario", "scenario source_ids must stay within the parent thesis")
                nested_analysis_ids = validate_analysis_ids(scenario["analysis_ids"], code="scenario", parent_analysis_ids=set(analysis_ids))
                nested_analysis_sources = {analysis_source_ids[analysis_id] for analysis_id in nested_analysis_ids}
                if nested_analysis_sources != set(source_ids):
                    raise SchemaError("scenario", "scenario analysis/source ownership mismatch")
                nested_expected = set().union(*(analysis_evidence_post_ids[analysis_id] for analysis_id in nested_analysis_ids))
                nested_evidence_ids = validate_evidence_ids(scenario["evidence_post_ids"], expected=nested_expected, code="scenario")
                nested_uncertainties = validate_string_array(scenario["uncertainties"], code="scenario")
                for opaque_kind, opaque_ids in opaque_catalogs:
                    _reject_opaque_ids(nested_uncertainties, opaque_ids, opaque_kind)
                reject_free_text([scenario["condition"]], code="scenario", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["scenario_condition"], check_market_tokens=True)
                reject_free_text([scenario["outcome"]], code="scenario", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["scenario_outcome"], check_market_tokens=True)
                reject_free_text(nested_uncertainties, code="scenario", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["scenario_uncertainties"], check_market_tokens=True)
                normalized_scenarios.append({
                    "condition": scenario["condition"],
                    "outcome": scenario["outcome"],
                    "source_ids": source_ids,
                    "analysis_ids": nested_analysis_ids,
                    "evidence_post_ids": nested_evidence_ids,
                    "uncertainties": nested_uncertainties,
                })

            actions = value["attributed_actions"]
            if not isinstance(actions, list):
                raise SchemaError("action", "attributed actions must be an array")
            normalized_actions: list[dict[str, Any]] = []
            for action in actions:
                if not isinstance(action, Mapping):
                    raise SchemaError("action", "attributed action must be an object")
                _require_exact_fields(action, V5_X_ACTION_FIELDS, "action")
                action_source_id = action.get("source_id")
                if action_source_id not in thesis_source_union:
                    raise SchemaError("action", "action source must belong to the parent thesis")
                _validate_v5_action_scope(action)
                action_analysis_ids = validate_analysis_ids(action["analysis_ids"], code="action", parent_analysis_ids=set(analysis_ids))
                if {analysis_source_ids[analysis_id] for analysis_id in action_analysis_ids} != {action_source_id}:
                    raise SchemaError("action", "attributed action must cite one blogger")
                action_expected = set().union(*(analysis_evidence_post_ids[analysis_id] for analysis_id in action_analysis_ids))
                action_evidence_ids = validate_evidence_ids(action["evidence_post_ids"], expected=action_expected, code="action")
                action_uncertainties = validate_string_array(action["uncertainties"], code="action")
                if not _string_list(action["conditions"]):
                    raise SchemaError("action", "conditions must be a string array")
                action_conditions = list(action["conditions"])
                for opaque_kind, opaque_ids in opaque_catalogs:
                    _reject_opaque_ids(action_conditions, opaque_ids, opaque_kind)
                    _reject_opaque_ids(action_uncertainties, opaque_ids, opaque_kind)
                if action["action_scope_status"] == "specified":
                    reject_free_text([action["action_scope"]], code="action", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["action_scope"], check_market_tokens=True)
                reject_free_text(action_conditions, code="action", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["action_conditions"], check_market_tokens=True)
                reject_free_text(action_uncertainties, code="action", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["action_uncertainties"], check_market_tokens=True)
                normalized_actions.append({
                    "source_id": action_source_id,
                    "action_intent": action["action_intent"],
                    "action_scope_status": action["action_scope_status"],
                    "action_scope": action["action_scope"],
                    "conditions": action_conditions,
                    "analysis_ids": action_analysis_ids,
                    "evidence_post_ids": action_evidence_ids,
                    "uncertainties": action_uncertainties,
                })

            normalized_item = {
                "thesis_id": thesis_id,
                "headline": headline,
                "synthesis": synthesis,
                "scenario_branches": normalized_scenarios,
                "attributed_actions": normalized_actions,
                "supporting_source_ids": supporting,
                "dissenting_source_ids": dissenting,
                "analysis_ids": analysis_ids,
                "evidence_post_ids": evidence_ids,
                "uncertainties": uncertainties,
            }
            thesis_by_id[thesis_id] = normalized_item
            thesis_sources[thesis_id] = analysis_sources
            normalized.append(normalized_item)
        return normalized

    normalized_categories = {
        "security_industry_theses": validate_thesis_group("security_industry_theses"),
        "market_structure_theses": validate_thesis_group("market_structure_theses"),
        "strategy_mindset_theses": validate_thesis_group("strategy_mindset_theses"),
    }

    ai_synthesis = payload["ai_synthesis"]
    assert isinstance(ai_synthesis, Mapping)
    _require_exact_fields(ai_synthesis, V5_X_AI_SYNTHESIS_FIELDS, "integration")
    integrations = ai_synthesis.get("cross_blogger_integrations")
    assessments = ai_synthesis.get("ai_assessments")
    if not isinstance(integrations, list) or not isinstance(assessments, list):
        raise SchemaError("integration", "AI synthesis arrays are invalid")

    normalized_integrations: list[dict[str, Any]] = []
    integration_pattern = V5_X_ID_PATTERNS["cross_blogger_integrations"]
    for index, value in enumerate(integrations, start=1):
        if not isinstance(value, Mapping):
            raise SchemaError("integration", "integration must be an object")
        _require_exact_fields(value, V5_X_INTEGRATION_FIELDS, "integration")
        match = integration_pattern.fullmatch(str(value.get("integration_id")))
        if not match or int(match.group(1)) != index:
            raise SchemaError("integration", "integration IDs must be consecutive")
        integration_id = str(value["integration_id"])
        if integration_id in seen_ids:
            raise SchemaError("integration", "integration IDs must be globally unique")
        seen_ids.add(integration_id)
        related_thesis_ids = validate_related_thesis_ids(value["related_thesis_ids"], code="integration")
        integration_supporting = set().union(*(set(thesis_by_id[thesis_id]["supporting_source_ids"]) for thesis_id in related_thesis_ids))
        integration_dissenting = set().union(*(set(thesis_by_id[thesis_id]["dissenting_source_ids"]) for thesis_id in related_thesis_ids))
        allow_consensus = len(integration_supporting) >= 2 and not integration_dissenting
        reject_free_text([value["headline"]], code="integration", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["integration_headline"], check_market_tokens=True)
        reject_free_text([value["synthesis"]], code="integration", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["integration_synthesis"], check_market_tokens=True)
        integration_uncertainties = validate_string_array(value["uncertainties"], code="integration")
        for opaque_kind, opaque_ids in opaque_catalogs:
            _reject_opaque_ids(integration_uncertainties, opaque_ids, opaque_kind)
        reject_free_text(integration_uncertainties, code="integration", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["integration_uncertainties"], check_market_tokens=True)

        common_points = value["common_points"]
        conflict_points = value["conflict_points"]
        if not isinstance(common_points, list) or not isinstance(conflict_points, list) or (not common_points and not conflict_points):
            raise SchemaError("integration", "integration must contain common points or conflict points")
        normalized_common_points: list[dict[str, Any]] = []
        normalized_conflict_points: list[dict[str, Any]] = []
        child_related_union: list[str] = []

        for common_point in common_points:
            if not isinstance(common_point, Mapping):
                raise SchemaError("integration", "common point must be an object")
            _require_exact_fields(common_point, V5_X_COMMON_POINT_FIELDS, "integration")
            source_ids = validate_source_ids(common_point["source_ids"], code="integration", allow_empty=False)
            if len(source_ids) < 2:
                raise SchemaError("integration", "common point requires at least two sources")
            thesis_ids = validate_related_thesis_ids(common_point["related_thesis_ids"], code="integration")
            allowed_child_sources = set().union(*(thesis_sources[thesis_id] for thesis_id in thesis_ids))
            if not set(source_ids) <= allowed_child_sources:
                raise SchemaError("integration", "child source must belong to child related theses")
            child_related_union.extend(thesis_ids)
            reject_free_text([common_point["statement"]], code="integration", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["common_statement"], check_market_tokens=True)
            normalized_common_points.append({
                "statement": common_point["statement"],
                "source_ids": source_ids,
                "related_thesis_ids": thesis_ids,
            })

        for conflict_point in conflict_points:
            if not isinstance(conflict_point, Mapping):
                raise SchemaError("conflict", "conflict point must be an object")
            _require_exact_fields(conflict_point, V5_X_CONFLICT_FIELDS, "conflict")
            positions = conflict_point["positions"]
            if not isinstance(positions, list) or len(positions) < 2:
                raise SchemaError("conflict", "conflict must contain at least two positions")
            position_union_sources: set[str] = set()
            normalized_positions: list[dict[str, Any]] = []
            for position in positions:
                if not isinstance(position, Mapping):
                    raise SchemaError("conflict", "position must be an object")
                _require_exact_fields(position, V5_X_POSITION_FIELDS, "conflict")
                source_ids = validate_source_ids(position["source_ids"], code="conflict", allow_empty=False)
                thesis_ids = validate_related_thesis_ids(position["related_thesis_ids"], code="conflict")
                allowed_child_sources = set().union(*(thesis_sources[thesis_id] for thesis_id in thesis_ids))
                if not set(source_ids) <= allowed_child_sources:
                    raise SchemaError("integration", "child source must belong to child related theses")
                child_related_union.extend(thesis_ids)
                position_union_sources.update(source_ids)
                reject_free_text([position["position"]], code="conflict", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["conflict_position"], check_market_tokens=True)
                normalized_positions.append({
                    "position": position["position"],
                    "source_ids": source_ids,
                    "related_thesis_ids": thesis_ids,
                })
            if len(position_union_sources) < 2:
                raise SchemaError("conflict", "conflict must span at least two bloggers")
            reject_free_text([conflict_point["issue"]], code="conflict", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["conflict_issue"], check_market_tokens=True)
            normalized_conflict_points.append({
                "issue": conflict_point["issue"],
                "positions": normalized_positions,
            })

        if list(dict.fromkeys(child_related_union)) != related_thesis_ids:
            raise SchemaError("integration", "integration top-level related_thesis_ids must match child union")
        normalized_integrations.append({
            "integration_id": integration_id,
            "headline": value["headline"],
            "synthesis": value["synthesis"],
            "common_points": normalized_common_points,
            "conflict_points": normalized_conflict_points,
            "related_thesis_ids": related_thesis_ids,
            "uncertainties": integration_uncertainties,
        })

    normalized_assessments: list[dict[str, Any]] = []
    assessment_pattern = V5_X_ID_PATTERNS["ai_assessments"]
    for index, value in enumerate(assessments, start=1):
        if not isinstance(value, Mapping):
            raise SchemaError("assessment", "assessment must be an object")
        _require_exact_fields(value, V5_X_ASSESSMENT_FIELDS, "assessment")
        match = assessment_pattern.fullmatch(str(value.get("assessment_id")))
        if not match or int(match.group(1)) != index:
            raise SchemaError("assessment", "assessment IDs must be consecutive")
        assessment_id = str(value["assessment_id"])
        if assessment_id in seen_ids:
            raise SchemaError("assessment", "assessment IDs must be globally unique")
        seen_ids.add(assessment_id)
        related_thesis_ids = validate_related_thesis_ids(value["related_thesis_ids"], code="assessment")
        supporting_union = set().union(*(set(thesis_by_id[thesis_id]["supporting_source_ids"]) for thesis_id in related_thesis_ids))
        dissenting_union = set().union(*(set(thesis_by_id[thesis_id]["dissenting_source_ids"]) for thesis_id in related_thesis_ids))
        allow_consensus = len(supporting_union) >= 2 and not dissenting_union
        reject_free_text([value["headline"]], code="assessment", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["assessment_headline"], check_market_tokens=True)
        reject_free_text([value["judgement"]], code="assessment", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["assessment_judgement"], check_market_tokens=True)
        reject_free_text([value["importance_reason"]], code="assessment", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["assessment_importance_reason"], check_market_tokens=True)
        reject_free_text([value["reasoning"]], code="assessment", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["assessment_reasoning"], check_market_tokens=True)
        key_assumptions = validate_string_array(value["key_assumptions"], code="assessment")
        risks = validate_string_array(value["risks"], code="assessment")
        watch_variables = validate_string_array(value["watch_variables"], code="assessment")
        uncertainties = validate_string_array(value["uncertainties"], code="assessment")
        for text_values in (key_assumptions, risks, watch_variables, uncertainties):
            for opaque_kind, opaque_ids in opaque_catalogs:
                _reject_opaque_ids(text_values, opaque_ids, opaque_kind)
            reject_free_text(text_values, code="assessment", allow_consensus=allow_consensus, max_length=V5_X_TEXT_LIMITS["assessment_arrays"], check_market_tokens=True)
        normalized_assessments.append({
            "assessment_id": assessment_id,
            "headline": value["headline"],
            "judgement": value["judgement"],
            "importance_reason": value["importance_reason"],
            "reasoning": value["reasoning"],
            "key_assumptions": key_assumptions,
            "risks": risks,
            "watch_variables": watch_variables,
            "related_thesis_ids": related_thesis_ids,
            "uncertainties": uncertainties,
        })

    return {
        "schema_version": "v5-x-cross-blogger",
        "ai_synthesis": {
            "cross_blogger_integrations": normalized_integrations,
            "ai_assessments": normalized_assessments,
        },
        **normalized_categories,
        "uncertainties": list(payload["uncertainties"]),
    }

def parse_v3_x_post_analysis_output(
    text: str,
    allowed_post_ids: set[str],
    allowed_context_post_ids: Mapping[str, set[str]] | set[str],
) -> dict[str, Any]:
    payload = _json_object(text)
    _require_exact_fields(payload, V3_X_POST_FIELDS, "invalid_v3_x_post")
    if payload.get("schema_version") != "v3-x-post-analysis" or not isinstance(payload.get("analyses"), list):
        raise SchemaError("invalid_v3_x_post", "schema version or analyses is invalid")
    analyses: list[dict[str, Any]] = []
    seen: set[str] = set()
    for value in payload["analyses"]:
        if not isinstance(value, Mapping):
            raise SchemaError("invalid_v3_x_post_analysis", "analysis must be an object")
        _require_exact_fields(value, V3_X_POST_ANALYSIS_FIELDS, "invalid_v3_x_post_analysis")
        post_id = value["post_id"]
        if not _non_empty_string(post_id) or post_id not in allowed_post_ids or post_id in seen:
            raise SchemaError("invalid_v3_x_post_analysis", "analysis must name one unique allowed post")
        seen.add(post_id)
        context_ids = allowed_context_post_ids.get(post_id) if isinstance(allowed_context_post_ids, Mapping) else allowed_context_post_ids
        if not isinstance(context_ids, set) or not all(_non_empty_string(context_id) for context_id in context_ids):
            raise SchemaError("invalid_v3_x_post", "post bundle context is invalid")
        relevance = value["investment_relevance"]
        categories = value["investment_categories"]
        if relevance not in V3_X_INVESTMENT_RELEVANCE or not _string_list(categories) or len(set(categories)) != len(categories) or not set(categories) <= V3_X_INVESTMENT_CATEGORIES:
            raise SchemaError("invalid_v3_x_post_analysis", "investment relevance or categories is invalid")
        if any(value[field] is not None and not _non_empty_string(value[field]) for field in ("blogger_viewpoint", "quoted_post_viewpoint")):
            raise SchemaError("invalid_v3_x_post_analysis", "viewpoints must be a string or null")
        action_intent = value["action_intent"]
        action_scope = value["action_scope"]
        if action_intent not in V3_X_ACTION_INTENTS or not isinstance(action_scope, str) or (action_intent == "none" and action_scope) or (action_intent != "none" and not action_scope.strip()):
            raise SchemaError("action scope", "action scope is inconsistent with action intent")
        if not all(_string_list(value[field]) for field in ("conditions", "arguments", "uncertainties")):
            raise SchemaError("invalid_v3_x_post_analysis", "text fields must be string arrays")
        evidence = value["evidence_post_ids"]
        if not _non_empty_string_list(evidence) or len(set(evidence)) != len(evidence) or post_id not in evidence or not set(evidence) <= ({post_id} | context_ids):
            raise SchemaError("evidence", "analysis evidence is outside its post bundle")
        link = value["post_link"]
        if not _non_empty_string(link) or not link.startswith("https://") or "/status/" not in link:
            raise SchemaError("invalid_v3_x_post_analysis", "post_link must be an HTTPS post link")
        if relevance == "not_investment_related" and (categories or value["blogger_viewpoint"] is not None or value["quoted_post_viewpoint"] is not None or action_intent != "none" or action_scope or value["conditions"] or value["arguments"] or value["uncertainties"]):
            raise SchemaError("invalid_v3_x_post_analysis", "non-investment analysis must be empty")
        opaque_ids = {post_id} | context_ids
        for natural_value in (value["blogger_viewpoint"], value["quoted_post_viewpoint"], action_scope):
            if natural_value is not None:
                _reject_opaque_ids([natural_value], opaque_ids, "evidence")
        for field in ("conditions", "arguments", "uncertainties"):
            _reject_opaque_ids(value[field], opaque_ids, "evidence")
        analyses.append(dict(value))
    if seen != allowed_post_ids:
        raise SchemaError("invalid_v3_x_post", "exactly one analysis is required for every input post")
    return {"schema_version": "v3-x-post-analysis", "analyses": analyses}


def parse_v3_x_window_output(
    text: str,
    allowed_analysis_ids: set[str],
    analysis_evidence_post_ids: Mapping[str, set[str]],
) -> dict[str, Any]:
    payload = _json_object(text)
    _require_exact_fields(payload, V3_X_WINDOW_FIELDS, "invalid_v3_x_window")
    if payload.get("schema_version") != "v3-x-window" or not _valid_date(payload.get("natural_date")):
        raise SchemaError("invalid_v3_x_window", "schema version or natural date is invalid")
    if not _non_empty_string(payload["range_task_id"]) or not _valid_instant(payload["occurred_from_at"]) or not _valid_instant(payload["occurred_through_at"]) or payload["occurred_from_at"] > payload["occurred_through_at"]:
        raise SchemaError("invalid_v3_x_window", "window identity or instants are invalid")
    if set(analysis_evidence_post_ids) != allowed_analysis_ids or any(not evidence_ids for evidence_ids in analysis_evidence_post_ids.values()):
        raise SchemaError("analysis", "analysis evidence catalog is incomplete")
    expected_evidence = set().union(*analysis_evidence_post_ids.values()) if analysis_evidence_post_ids else set()
    for field, expected in (("analysis_ids", allowed_analysis_ids), ("evidence_post_ids", expected_evidence)):
        values = payload[field]
        if not _non_empty_string_list(values) or len(set(values)) != len(values) or set(values) != expected:
            raise SchemaError("coverage", f"{field} must exactly cover the window input")
    if not _string_list(payload["uncertainties"]):
        raise SchemaError("invalid_v3_x_window", "uncertainties must be a string array")
    opaque_ids = allowed_analysis_ids | expected_evidence
    _reject_opaque_ids(payload["uncertainties"], opaque_ids, "analysis")
    categories = ("security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints")
    normalized: dict[str, list[dict[str, Any]]] = {}
    for category in categories:
        values = payload[category]
        if not isinstance(values, list):
            raise SchemaError("invalid_v3_x_window", "viewpoints must be arrays")
        items: list[dict[str, Any]] = []
        for value in values:
            if not isinstance(value, Mapping):
                raise SchemaError("invalid_v3_x_window_item", "window item must be an object")
            _require_exact_fields(value, V3_X_WINDOW_ITEM_FIELDS, "invalid_v3_x_window_item")
            if not _non_empty_string(value["statement"]) or _STRONG_CONSENSUS_WORDING.search(value["statement"]):
                raise SchemaError("invalid_v3_x_window_item", "statement is invalid for one blogger")
            action_intent = value["action_intent"]
            action_scope = value["action_scope"]
            if action_intent not in V3_X_ACTION_INTENTS or not isinstance(action_scope, str) or (action_intent == "none" and action_scope) or (action_intent != "none" and not action_scope.strip()):
                raise SchemaError("action scope", "action scope is inconsistent with action intent")
            if not _string_list(value["conditions"]) or not _string_list(value["uncertainties"]):
                raise SchemaError("invalid_v3_x_window_item", "text fields must be string arrays")
            analysis_ids = value["analysis_ids"]
            if not _non_empty_string_list(analysis_ids) or len(set(analysis_ids)) != len(analysis_ids) or not set(analysis_ids) <= allowed_analysis_ids:
                raise SchemaError("analysis", "window item cites an unknown analysis")
            evidence = value["evidence_post_ids"]
            expected_item_evidence = set().union(*(analysis_evidence_post_ids[analysis_id] for analysis_id in analysis_ids))
            if not _non_empty_string_list(evidence) or len(set(evidence)) != len(evidence) or set(evidence) != expected_item_evidence:
                raise SchemaError("evidence", "window item evidence does not match analyses")
            _reject_opaque_ids([value["statement"], action_scope], opaque_ids, "analysis")
            _reject_opaque_ids(value["conditions"], opaque_ids, "analysis")
            _reject_opaque_ids(value["uncertainties"], opaque_ids, "analysis")
            items.append(dict(value))
        normalized[category] = items
    return {"schema_version": "v3-x-window", "natural_date": payload["natural_date"], "range_task_id": payload["range_task_id"], "occurred_from_at": payload["occurred_from_at"], "occurred_through_at": payload["occurred_through_at"], **normalized, "analysis_ids": list(payload["analysis_ids"]), "evidence_post_ids": list(payload["evidence_post_ids"]), "uncertainties": list(payload["uncertainties"])}


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
    analysis_source_ids: Mapping[str, str],
    analysis_evidence_post_ids: Mapping[str, set[str]],
    frozen_source_ids: set[str] | None = None,
    opaque_context_ids: Mapping[str, set[str]] | None = None,
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
    opaque_source_ids = frozen_source_ids if frozen_source_ids is not None else allowed_source_ids
    if not allowed_source_ids <= opaque_source_ids or not all(_non_empty_string(source_id) for source_id in opaque_source_ids):
        raise SchemaError("source", "frozen source catalog is invalid")
    if set(analysis_source_ids) != allowed_analysis_ids or set(analysis_evidence_post_ids) != allowed_analysis_ids:
        raise SchemaError("analysis", "analysis ownership catalog is incomplete")
    for analysis_id in allowed_analysis_ids:
        source_id = analysis_source_ids.get(analysis_id)
        evidence_ids = analysis_evidence_post_ids.get(analysis_id)
        if source_id not in allowed_source_ids or not isinstance(evidence_ids, set) or not evidence_ids or not evidence_ids <= allowed_post_ids:
            raise SchemaError("analysis", "analysis ownership catalog is invalid")
    context_catalog = opaque_context_ids or {}
    if not set(context_catalog) <= {"batch", "run", "segment"} or any(
        not isinstance(opaque_ids, set) or not all(_non_empty_string(opaque_id) for opaque_id in opaque_ids)
        for opaque_ids in context_catalog.values()
    ):
        raise SchemaError("context", "opaque context catalog is invalid")
    opaque_catalogs = (
        ("batch", context_catalog.get("batch", set())),
        ("run", context_catalog.get("run", set())),
        ("segment", context_catalog.get("segment", set())),
        ("analysis", allowed_analysis_ids),
        ("source", opaque_source_ids),
        ("evidence", allowed_post_ids),
    )
    for opaque_kind, opaque_ids in opaque_catalogs:
        _reject_opaque_ids(payload["uncertainties"], opaque_ids, opaque_kind)

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
            for opaque_kind, opaque_ids in opaque_catalogs:
                _reject_opaque_ids([statement], opaque_ids, opaque_kind)
            supporting = value["supporting_source_ids"]
            dissenting = value["dissenting_source_ids"]
            if not _string_list(supporting) or not _string_list(dissenting) or len(set(supporting)) != len(supporting) or len(set(dissenting)) != len(dissenting):
                raise SchemaError("invalid_v2_x_cross_blogger_item", "source IDs must be unique string arrays")
            if not set(supporting) <= allowed_source_ids or not set(dissenting) <= allowed_source_ids:
                raise SchemaError("source", "unknown source")
            if set(supporting) & set(dissenting):
                raise SchemaError("source", "source cannot be both supporting and dissenting")
            if _STRONG_CONSENSUS_WORDING.search(statement) and (len(supporting) < 2 or dissenting):
                raise SchemaError(
                    "consensus",
                    "strong consensus wording requires two independent supporting sources and no dissenting source",
                )
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
            for opaque_kind, opaque_ids in opaque_catalogs:
                _reject_opaque_ids(value["uncertainties"], opaque_ids, opaque_kind)
            item_source_ids = set(supporting) | set(dissenting)
            analysis_sources = {analysis_source_ids[analysis_id] for analysis_id in analyses}
            if not analysis_sources <= item_source_ids or not item_source_ids <= analysis_sources:
                raise SchemaError("source", "analysis source ownership does not match item sources")
            analysis_evidence = set().union(*(analysis_evidence_post_ids[analysis_id] for analysis_id in analyses))
            if set(evidence) != analysis_evidence:
                raise SchemaError("evidence", "evidence posts must exactly match the referenced analyses")
            result.append(dict(value))
        return result

    return {
        "schema_version": "v2-x-cross-blogger",
        "stock_viewpoints": normalized_items(payload["stock_viewpoints"], "stock"),
        "market_industry_viewpoints": normalized_items(payload["market_industry_viewpoints"], "market_industry"),
        "uncertainties": list(payload["uncertainties"]),
    }


def parse_v3_x_cross_blogger_output(
    text: str,
    *,
    allowed_source_ids: set[str],
    allowed_analysis_ids: set[str],
    allowed_post_ids: set[str],
    analysis_source_ids: Mapping[str, str],
    analysis_evidence_post_ids: Mapping[str, set[str]],
    frozen_source_ids: set[str] | None = None,
    opaque_context_ids: Mapping[str, set[str]] | None = None,
) -> dict[str, object]:
    """Validate v3 cross-blogger investment judgements before persistence."""

    payload = _json_object(text)
    _require_exact_fields(payload, V3_X_CROSS_BLOGGER_FIELDS, "invalid_v3_x_cross_blogger")
    if payload.get("schema_version") != "v3-x-cross-blogger":
        raise SchemaError("invalid_v3_x_cross_blogger", "schema_version must be v3-x-cross-blogger")
    categories = ("security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints")
    if not all(isinstance(payload.get(category), list) for category in categories):
        raise SchemaError("invalid_v3_x_cross_blogger", "viewpoints must be arrays")
    if not _string_list(payload.get("uncertainties")):
        raise SchemaError("invalid_v3_x_cross_blogger", "uncertainties must be a string array")
    opaque_source_ids = frozen_source_ids if frozen_source_ids is not None else allowed_source_ids
    if not allowed_source_ids <= opaque_source_ids or not all(_non_empty_string(source_id) for source_id in opaque_source_ids):
        raise SchemaError("source", "frozen source catalog is invalid")
    if set(analysis_source_ids) != allowed_analysis_ids or set(analysis_evidence_post_ids) != allowed_analysis_ids:
        raise SchemaError("analysis", "analysis ownership catalog is incomplete")
    for analysis_id in allowed_analysis_ids:
        source_id = analysis_source_ids.get(analysis_id)
        evidence_ids = analysis_evidence_post_ids.get(analysis_id)
        if source_id not in allowed_source_ids or not isinstance(evidence_ids, set) or not evidence_ids or not evidence_ids <= allowed_post_ids:
            raise SchemaError("analysis", "analysis ownership catalog is invalid")
    context_catalog = opaque_context_ids or {}
    if not set(context_catalog) <= {"batch", "run", "segment"} or any(
        not isinstance(opaque_ids, set) or not all(_non_empty_string(opaque_id) for opaque_id in opaque_ids)
        for opaque_ids in context_catalog.values()
    ):
        raise SchemaError("context", "opaque context catalog is invalid")
    opaque_catalogs = (
        ("batch", context_catalog.get("batch", set())),
        ("run", context_catalog.get("run", set())),
        ("segment", context_catalog.get("segment", set())),
        ("analysis", allowed_analysis_ids),
        ("source", opaque_source_ids),
        ("evidence", allowed_post_ids),
    )
    for opaque_kind, opaque_ids in opaque_catalogs:
        _reject_opaque_ids(payload["uncertainties"], opaque_ids, opaque_kind)

    def normalized_items(values: list[object], category: str) -> list[dict[str, object]]:
        result: list[dict[str, object]] = []
        for index, value in enumerate(values):
            if not isinstance(value, Mapping):
                raise SchemaError("invalid_v3_x_cross_blogger_item", f"{category} item {index} must be an object")
            _require_exact_fields(value, V3_X_CROSS_BLOGGER_ITEM_FIELDS, "invalid_v3_x_cross_blogger_item")
            statement = value["statement"]
            if not _non_empty_string(statement):
                raise SchemaError("invalid_v3_x_cross_blogger_item", "statement must be a non-empty string")
            if _IMPERATIVE_INVESTMENT_RECOMMENDATION.search(statement):
                raise SchemaError("invalid_v3_x_cross_blogger_item", "imperative system investment recommendation is not allowed")
            action_intent = value["action_intent"]
            action_scope = value["action_scope"]
            if action_intent not in V3_X_ACTION_INTENTS:
                raise SchemaError("action intent", "action intent is invalid")
            if not isinstance(action_scope, str) or (action_intent == "none" and action_scope) or (action_intent != "none" and not action_scope.strip()):
                raise SchemaError("action scope", "action scope is inconsistent with action intent")
            if not _string_list(value["conditions"]):
                raise SchemaError("conditions", "conditions must be a string array")
            for opaque_kind, opaque_ids in opaque_catalogs:
                _reject_opaque_ids([statement, action_scope], opaque_ids, opaque_kind)
                _reject_opaque_ids(value["conditions"], opaque_ids, opaque_kind)
            supporting = value["supporting_source_ids"]
            dissenting = value["dissenting_source_ids"]
            if not _string_list(supporting) or not _string_list(dissenting) or len(set(supporting)) != len(supporting) or len(set(dissenting)) != len(dissenting):
                raise SchemaError("invalid_v3_x_cross_blogger_item", "source IDs must be unique string arrays")
            if not set(supporting) <= allowed_source_ids or not set(dissenting) <= allowed_source_ids:
                raise SchemaError("source", "unknown source")
            if set(supporting) & set(dissenting):
                raise SchemaError("source", "source cannot be both supporting and dissenting")
            if _STRONG_CONSENSUS_WORDING.search(statement) and (len(supporting) < 2 or dissenting):
                raise SchemaError("consensus", "strong consensus wording requires two independent supporting sources and no dissenting source")
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
                raise SchemaError("invalid_v3_x_cross_blogger_item", "uncertainties must be a string array")
            for opaque_kind, opaque_ids in opaque_catalogs:
                _reject_opaque_ids(value["uncertainties"], opaque_ids, opaque_kind)
            item_source_ids = set(supporting) | set(dissenting)
            analysis_sources = {analysis_source_ids[analysis_id] for analysis_id in analyses}
            if not analysis_sources <= item_source_ids or not item_source_ids <= analysis_sources:
                raise SchemaError("source", "analysis source ownership does not match item sources")
            analysis_evidence = set().union(*(analysis_evidence_post_ids[analysis_id] for analysis_id in analyses))
            if set(evidence) != analysis_evidence:
                raise SchemaError("evidence", "evidence posts must exactly match the referenced analyses")
            result.append(dict(value))
        return result

    return {
        "schema_version": "v3-x-cross-blogger",
        "security_industry_viewpoints": normalized_items(payload["security_industry_viewpoints"], "security_industry"),
        "market_structure_viewpoints": normalized_items(payload["market_structure_viewpoints"], "market_structure"),
        "strategy_mindset_viewpoints": normalized_items(payload["strategy_mindset_viewpoints"], "strategy_mindset"),
        "uncertainties": list(payload["uncertainties"]),
    }


def _reject_opaque_ids(values: object, opaque_ids: set[str], opaque_kind: str) -> None:
    if not isinstance(values, list):
        raise SchemaError("invalid_v2_x_cross_blogger", "natural language fields must be string arrays")
    canonical_opaque_ids = tuple(opaque_id.casefold() for opaque_id in opaque_ids)
    for value in values:
        if not isinstance(value, str):
            raise SchemaError("invalid_v2_x_cross_blogger", "natural language fields must be strings")
        canonical_value = value.casefold()
        if any(opaque_id in canonical_value for opaque_id in canonical_opaque_ids):
            raise SchemaError(opaque_kind, f"opaque {opaque_kind} ID is not allowed in natural language")


def _extract_market_tokens(value: object) -> set[str]:
    return {match.group(0).upper() for text in _iter_strings(value) for match in _INPUT_MARKET_TOKEN.finditer(text)}


def _iter_strings(value: object) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, Mapping):
        strings: list[str] = []
        for nested in value.values():
            strings.extend(_iter_strings(nested))
        return strings
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
        strings: list[str] = []
        for nested in value:
            strings.extend(_iter_strings(nested))
        return strings
    return []



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
