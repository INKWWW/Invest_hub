from __future__ import annotations

import json
from collections.abc import Iterable
from pathlib import Path

from .fixtures import load_fixture
from .model import FixtureCase, QualityReport, RunReport, StructuredOutput


INITIAL_THRESHOLDS = {
    "first_success_rate": 0.90,
    "final_success_rate": 0.99,
    "json_parse_rate": 0.98,
    "grounded_rate": 0.95,
    "severe_attribution_errors": 0,
    "media_hallucinations": 0,
}


def evaluate_output(case: FixtureCase, output: StructuredOutput) -> QualityReport:
    topics = tuple(_topic_text(topic) for topic in output.topics)
    topic_sources = tuple(set(topic.source_message_ids) for topic in output.topics)
    unparsed_ids = {
        message.message_id
        for message in case.messages
        if message.kind == "unparsed_media"
    }
    covered = 0
    grounded = 0
    attributed = 0
    severe_attribution_errors = 0
    media_hallucinations = 0

    for claim in case.claims:
        matching_indexes = [
            index
            for index, text in enumerate(topics)
            if all(term in text for term in claim.required_terms)
        ]
        if matching_indexes:
            covered += 1
        grounded_indexes = [
            index
            for index in matching_indexes
            if set(claim.source_message_ids).issubset(topic_sources[index])
        ]
        if grounded_indexes:
            grounded += 1
        correct_indexes = [
            index
            for index in grounded_indexes
            if _author_matches(case, output, index, claim.target_author_id)
        ]
        if correct_indexes:
            attributed += 1
        if claim.target_author_id is not None and grounded_indexes and not correct_indexes:
            severe_attribution_errors += 1
        for index, text in enumerate(topics):
            if topic_sources[index].intersection(unparsed_ids) and any(
                term in text for term in claim.forbidden_terms
            ):
                media_hallucinations += 1
                break

    return QualityReport(
        covered_claims=covered,
        grounded_claims=grounded,
        attributed_claims=attributed,
        required_claims=len(case.claims),
        severe_attribution_errors=severe_attribution_errors,
        media_hallucinations=media_hallucinations,
    )


def evaluate_review_sheet(path: Path) -> QualityReport:
    covered = 0
    grounded = 0
    attributed = 0
    media_hallucinations = 0
    required = 0
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ValueError(f"review sheet read failed: {exc}") from exc
    for line_number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid review JSON at line {line_number}") from exc
        if not isinstance(payload, dict):
            raise ValueError(f"review line {line_number} must be an object")
        required += 1
        booleans = (
            "covered",
            "grounded",
            "correct_attribution",
            "media_hallucination",
        )
        if not all(isinstance(payload.get(field), bool) for field in booleans):
            raise ValueError(f"review line {line_number} boolean fields are required")
        covered += int(payload["covered"])
        grounded += int(payload["grounded"])
        attributed += int(payload["correct_attribution"])
        media_hallucinations += int(payload["media_hallucination"])
    return QualityReport(
        covered_claims=covered,
        grounded_claims=grounded,
        attributed_claims=attributed,
        required_claims=required,
        severe_attribution_errors=required - attributed,
        media_hallucinations=media_hallucinations,
    )


def classify_run(
    reports: Iterable[RunReport],
    quality: QualityReport,
    *,
    has_real_glm_evidence: bool,
    constrained: bool,
) -> str:
    reports_tuple = tuple(reports)
    if not has_real_glm_evidence:
        return "unverified"
    if {report.scale for report in reports_tuple} != {"small", "medium", "large"}:
        return "unverified"
    if not reports_tuple:
        return "unverified"
    if min(report.first_success_rate for report in reports_tuple) < INITIAL_THRESHOLDS["first_success_rate"]:
        return "fail"
    if min(report.final_success_rate for report in reports_tuple) < INITIAL_THRESHOLDS["final_success_rate"]:
        return "fail"
    if min(report.json_parse_rate for report in reports_tuple) < INITIAL_THRESHOLDS["json_parse_rate"]:
        return "fail"
    grounded_rate = (
        quality.grounded_claims / quality.required_claims
        if quality.required_claims
        else 0.0
    )
    if grounded_rate < INITIAL_THRESHOLDS["grounded_rate"]:
        return "fail"
    if quality.severe_attribution_errors or quality.media_hallucinations:
        return "fail"
    return "conditional_pass" if constrained else "pass"


def _topic_text(topic) -> str:
    fields = [topic.title, topic.summary, *(topic.tickers or ())]
    if topic.operation_tendency:
        fields.append(topic.operation_tendency)
    if topic.uncertainty:
        fields.append(topic.uncertainty)
    return " ".join(fields)


def _author_matches(
    case: FixtureCase,
    output: StructuredOutput,
    topic_index: int,
    target_author_id: str | None,
) -> bool:
    if target_author_id is None:
        return True
    topic = output.topics[topic_index]
    return topic.author_scope == "target" and topic.author_id == target_author_id
