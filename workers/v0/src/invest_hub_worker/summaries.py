from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Mapping, Sequence, TypedDict
from zoneinfo import ZoneInfo

from .canonical import CanonicalMessage


class SummaryError(ValueError):
    pass


class BatchSummaryPayload(TypedDict):
    natural_date: str
    input_message_ids: list[str]
    structured_run_keys: list[str]
    output: dict[str, Any]
    coverage: dict[str, Any]


def build_batch_summaries(
    messages: Sequence[CanonicalMessage],
    runs: Sequence[Mapping[str, Any]],
) -> list[BatchSummaryPayload]:
    if not messages:
        raise SummaryError("cannot summarize an empty message set")

    by_id: dict[str, CanonicalMessage] = {}
    by_day: dict[str, list[CanonicalMessage]] = defaultdict(list)
    for message in messages:
        if message.external_message_id in by_id:
            raise SummaryError("duplicate canonical message ID")
        natural_date = _natural_date(message.occurred_at)
        by_id[message.external_message_id] = message
        by_day[natural_date].append(message)

    run_by_id: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    normalized_runs: list[tuple[str, list[str], Mapping[str, Any]]] = []
    for run in runs:
        chunk_key = run.get("chunk_key")
        input_message_ids = run.get("input_message_ids")
        output = run.get("output")
        if not isinstance(chunk_key, str) or not chunk_key or not _string_list(input_message_ids) or not isinstance(output, Mapping):
            raise SummaryError("invalid structured run for batch summary")
        if len(set(input_message_ids)) != len(input_message_ids):
            raise SummaryError("structured run has duplicate message IDs")
        normalized_runs.append((chunk_key, list(input_message_ids), output))
        for message_id in input_message_ids:
            run_by_id[message_id].append(run)

    if not normalized_runs:
        raise SummaryError("cannot summarize without structured runs")
    uncovered = [message_id for message_id in by_id if message_id not in run_by_id]
    if uncovered:
        raise SummaryError("canonical message is not covered by a structured run")

    summaries: list[BatchSummaryPayload] = []
    for natural_date in sorted(by_day):
        day_messages = by_day[natural_date]
        input_ids = [message.external_message_id for message in day_messages]
        day_id_set = set(input_ids)
        selected = [run for run in normalized_runs if day_id_set.intersection(run[1])]
        run_keys = [run[0] for run in selected]
        topics: list[Any] = []
        warnings: list[str] = []
        for _chunk_key, _run_ids, output in selected:
            output_topics = output.get("topics", [])
            output_warnings = output.get("warnings", [])
            if not isinstance(output_topics, list) or not isinstance(output_warnings, list) or not all(isinstance(item, str) for item in output_warnings):
                raise SummaryError("structured output cannot form a safe summary")
            topics.extend(output_topics)
            warnings.extend(output_warnings)
        media_ids = [message.external_message_id for message in day_messages if message.attachments]
        if media_ids and "附件未解析" not in warnings:
            warnings.append("附件未解析")
        summaries.append({
            "natural_date": natural_date,
            "input_message_ids": input_ids,
            "structured_run_keys": run_keys,
            "output": {"topics": topics, "warnings": list(dict.fromkeys(warnings))},
            "coverage": {
                "unparsed_media": bool(media_ids),
                "unparsed_media_message_ids": media_ids,
            },
        })
    return summaries


def build_v1_1_batch_summaries(
    messages: Sequence[CanonicalMessage],
    runs: Sequence[Mapping[str, Any]],
    daily_outputs: Mapping[str, Mapping[str, Any]],
) -> list[BatchSummaryPayload]:
    """Persist V1.1 fact units beside one validated daily result per local day.

    V1.1 chunking is deliberately Shanghai-day local.  A cross-day fact would
    make its daily evidence ambiguous, so it is rejected before the database
    can create a reader-visible summary.
    """

    if not messages:
        raise SummaryError("cannot summarize an empty message set")
    by_id: dict[str, CanonicalMessage] = {}
    by_day: dict[str, list[CanonicalMessage]] = defaultdict(list)
    for item in messages:
        if item.external_message_id in by_id:
            raise SummaryError("duplicate canonical message ID")
        day = _shanghai_natural_date(item.occurred_at)
        by_id[item.external_message_id] = item
        by_day[day].append(item)

    normalized_runs: list[tuple[str, list[str], Mapping[str, Any]]] = []
    covered_ids: set[str] = set()
    for run in runs:
        chunk_key = run.get("chunk_key")
        input_ids = run.get("input_message_ids")
        output = run.get("output")
        if not isinstance(chunk_key, str) or not chunk_key or not _string_list(input_ids) or not isinstance(output, Mapping):
            raise SummaryError("invalid V1.1 structured run")
        if len(set(input_ids)) != len(input_ids) or any(message_id not in by_id for message_id in input_ids):
            raise SummaryError("V1.1 structured run has invalid message evidence")
        run_days = {_shanghai_natural_date(by_id[message_id].occurred_at) for message_id in input_ids}
        if len(run_days) != 1:
            raise SummaryError("V1.1 structured run crosses Shanghai days")
        if output.get("schema_version") != "v1.1-chunk" or not isinstance(output.get("facts"), list) or not _string_array(output.get("warnings")):
            raise SummaryError("invalid V1.1 structured output")
        normalized_runs.append((chunk_key, list(input_ids), output))
        covered_ids.update(input_ids)
    if set(by_id) != covered_ids:
        raise SummaryError("canonical message is not covered by a V1.1 structured run")
    if set(daily_outputs) != set(by_day):
        raise SummaryError("V1.1 daily output must cover exactly the summarized Shanghai days")

    summaries: list[BatchSummaryPayload] = []
    for day in sorted(by_day):
        day_messages = by_day[day]
        day_ids = {item.external_message_id for item in day_messages}
        selected = [run for run in normalized_runs if set(run[1]) <= day_ids]
        if not selected:
            raise SummaryError("V1.1 day has no structured runs")
        facts: list[Any] = []
        warnings: list[str] = []
        for _chunk_key, _input_ids, output in selected:
            facts.extend(output["facts"])
            warnings.extend(output["warnings"])
        media_ids = [item.external_message_id for item in day_messages if item.attachments]
        if media_ids and "存在未解析媒体" not in warnings:
            warnings.append("存在未解析媒体")
        summaries.append({
            "natural_date": day,
            "input_message_ids": [item.external_message_id for item in day_messages],
            "structured_run_keys": [run[0] for run in selected],
            "output": {
                "schema_version": "v1.1-batch",
                "facts": facts,
                "warnings": list(dict.fromkeys(warnings)),
                "daily_summary": dict(daily_outputs[day]),
            },
            "coverage": {
                "unparsed_media": bool(media_ids),
                "unparsed_media_message_ids": media_ids,
            },
        })
    return summaries


def _natural_date(value: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SummaryError("canonical message must have an occurred_at timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SummaryError("canonical message occurred_at is invalid") from exc
    if parsed.tzinfo is None:
        raise SummaryError("canonical message occurred_at must be timezone-aware")
    return parsed.astimezone(timezone.utc).date().isoformat()


def _shanghai_natural_date(value: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SummaryError("canonical message must have an occurred_at timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SummaryError("canonical message occurred_at is invalid") from exc
    if parsed.tzinfo is None:
        raise SummaryError("canonical message occurred_at must be timezone-aware")
    return parsed.astimezone(ZoneInfo("Asia/Shanghai")).date().isoformat()


def _string_list(value: object) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(item, str) and item for item in value)


def _string_array(value: object) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) and item for item in value)


def build_v2_x_daily_viewpoint_timeline(
    prior_segments: list[dict[str, object]], new_segment: dict[str, object] | None,
) -> list[dict[str, object]]:
    """Return a deterministic reader projection without mutating older prose."""

    segments = [dict(segment) for segment in prior_segments]
    if new_segment is not None:
        segment_id = new_segment.get("id")
        if not isinstance(segment_id, str) or not segment_id or any(segment.get("id") == segment_id for segment in segments):
            raise SummaryError("X viewpoint segment identity is invalid or duplicated")
        segments.append(dict(new_segment))
    if any(not isinstance(segment.get("id"), str) or not isinstance(segment.get("occurred_from_at"), str) for segment in segments):
        raise SummaryError("X viewpoint segment is missing its immutable identity or time")
    return sorted(segments, key=lambda segment: (str(segment["occurred_from_at"]), str(segment["id"])))
