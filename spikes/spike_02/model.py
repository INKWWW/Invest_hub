from __future__ import annotations

from dataclasses import dataclass
from typing import Literal


Scale = Literal["small", "medium", "large"]
ProviderName = Literal["mock", "codex"]
MessageKind = Literal["text", "unparsed_media"]


@dataclass(frozen=True)
class FixtureMessage:
    message_id: str
    author_id: str
    author_scope: Literal["target", "other"]
    published_at: str
    content: str
    kind: MessageKind
    parent_id: str | None


@dataclass(frozen=True)
class ExpectedClaim:
    claim_id: str
    category: Literal[
        "fact",
        "target_viewpoint",
        "ticker",
        "operation_tendency",
        "context",
    ]
    required_terms: tuple[str, ...]
    source_message_ids: tuple[str, ...]
    target_author_id: str | None
    forbidden_terms: tuple[str, ...]


@dataclass(frozen=True)
class FixtureCase:
    case_id: str
    scale: Scale
    messages: tuple[FixtureMessage, ...]
    claims: tuple[ExpectedClaim, ...]


@dataclass(frozen=True)
class Chunk:
    chunk_id: str
    case_id: str
    index: int
    primary_message_ids: tuple[str, ...]
    context_message_ids: tuple[str, ...]
    prompt_text: str
    input_chars: int
    prompt_lines: tuple[str, ...]


@dataclass(frozen=True)
class LLMRequest:
    run_id: str
    chunk: Chunk
    attempt: int
    prompt_version: str


@dataclass(frozen=True)
class ProviderResponse:
    status: str
    content: str | None
    latency_ms: int
    input_tokens: int | None
    output_tokens: int | None
    finish_reason: str | None
    error_code: str | None
    process_exit_code: int | None = None
    diagnostic: str | None = None


@dataclass(frozen=True)
class StructuredTopic:
    title: str
    summary: str
    source_message_ids: tuple[str, ...]
    author_scope: str
    author_id: str | None
    tickers: tuple[str, ...]
    operation_tendency: str | None
    uncertainty: str | None


@dataclass(frozen=True)
class StructuredOutput:
    topics: tuple[StructuredTopic, ...]
    media_unparsed: bool
    media_source_message_ids: tuple[str, ...]
    warnings: tuple[str, ...]


@dataclass(frozen=True)
class ChunkResult:
    chunk_id: str
    status: str
    attempts: int
    output: StructuredOutput | None
    error_code: str | None


@dataclass(frozen=True)
class QualityReport:
    covered_claims: int
    grounded_claims: int
    attributed_claims: int
    required_claims: int
    severe_attribution_errors: int
    media_hallucinations: int


@dataclass(frozen=True)
class RunReport:
    run_id: str
    provider: ProviderName
    case_id: str
    scale: Scale
    chunk_size: int
    request_count: int
    retry_count: int
    first_success_rate: float
    final_success_rate: float
    json_parse_rate: float
    p50_latency_ms: int
    p95_latency_ms: int
    primary_message_ids: tuple[str, ...]
    results: tuple[ChunkResult, ...]
    batch_elapsed_ms: int
    max_concurrency: int
    max_active_requests: int
