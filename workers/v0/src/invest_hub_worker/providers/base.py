from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol


@dataclass(frozen=True)
class ProviderContext:
    """Per-chunk execution context.

    The prompt is deliberately kept on the request context only.  It is sent to
    a local provider process but is never copied into :class:`ProviderResponse`
    or a cloud task result.
    """

    chunk_id: str
    prompt_version: str
    prompt_text: str
    attempt: int = 1
    timeout_seconds: float = 240.0
    input_message_ids: frozenset[str] = frozenset()
    unparsed_media_message_ids: frozenset[str] = frozenset()
    target_author_ids: frozenset[str] = frozenset()
    operation: str = "legacy_topics"
    input_message_authors: tuple[tuple[str, str, str], ...] = ()
    configured_author_profiles: tuple[tuple[str, str], ...] = ()
    expected_natural_date: str | None = None
    expected_as_of: str | None = None
    visible_context_post_ids: frozenset[str] = frozenset()
    allowed_source_ids: frozenset[str] = frozenset()
    allowed_analysis_ids: frozenset[str] = frozenset()
    allowed_post_ids: frozenset[str] = frozenset()
    allowed_analysis_source_ids: tuple[tuple[str, str], ...] = ()
    allowed_analysis_evidence_post_ids: tuple[tuple[str, tuple[str, ...]], ...] = ()
    frozen_source_ids: frozenset[str] = frozenset()
    opaque_context_ids: tuple[tuple[str, tuple[str, ...]], ...] = ()

    def __post_init__(self) -> None:
        if not self.chunk_id.strip():
            raise ValueError("chunk_id must be non-empty")
        if not self.prompt_version.strip():
            raise ValueError("prompt_version must be non-empty")
        if self.attempt < 1:
            raise ValueError("attempt must be positive")
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if self.operation not in {"legacy_topics", "v1_1_chunk", "v1_1_daily", "v2_x_chunk", "v2_x_window", "v2_x_cross_blogger", "v3_x_post_analysis", "v3_x_window", "v3_x_cross_blogger", "v4_x_post_analysis", "v4_x_window", "v4_x_cross_blogger", "v5_x_cross_blogger"}:
            raise ValueError("operation must be an approved structuring operation")
        message_ids: set[str] = set()
        for identity in self.input_message_authors:
            if not isinstance(identity, tuple) or len(identity) != 3 or any(not isinstance(value, str) or not value.strip() for value in identity):
                raise ValueError("input_message_authors must contain message and author identities")
            if identity[0] in message_ids:
                raise ValueError("input_message_authors must not repeat a message ID")
            message_ids.add(identity[0])
        author_ids: set[str] = set()
        for profile in self.configured_author_profiles:
            if not isinstance(profile, tuple) or len(profile) != 2 or any(not isinstance(value, str) or not value.strip() for value in profile):
                raise ValueError("configured_author_profiles must contain stable author identities")
            if profile[0] in author_ids:
                raise ValueError("configured_author_profiles must not repeat an author ID")
            author_ids.add(profile[0])
        if any(not isinstance(source_id, str) or not source_id.strip() for source_id in self.frozen_source_ids):
            raise ValueError("frozen_source_ids must contain non-empty source IDs")
        seen_context_kinds: set[str] = set()
        for value in self.opaque_context_ids:
            if not isinstance(value, tuple) or len(value) != 2:
                raise ValueError("opaque_context_ids must contain context kind and IDs")
            kind, ids = value
            if kind not in {"batch", "run", "segment"} or kind in seen_context_kinds:
                raise ValueError("opaque_context_ids must use unique approved context kinds")
            seen_context_kinds.add(kind)
            if not isinstance(ids, tuple) or not ids or any(not isinstance(opaque_id, str) or not opaque_id.strip() for opaque_id in ids) or len(set(ids)) != len(ids):
                raise ValueError("opaque_context_ids must contain unique non-empty IDs")
        if self.operation == "v1_1_daily" and (not self.expected_natural_date or not self.expected_as_of):
            raise ValueError("v1_1_daily requires expected natural date and as_of")


@dataclass(frozen=True)
class ProviderResponse:
    """Safe provider telemetry and references.

    Neither the prompt nor the full model response is represented here.  A
    provider may return the validated structured object for the local execution
    boundary, while durable raw/structured evidence is addressed only by refs.
    """

    status: str
    provider: str
    model_reported: str | None
    prompt_version: str
    elapsed_ms: int
    attempt: int
    raw_ref: str | None
    parsed_output_ref: str | None
    parsed_output: dict[str, Any] | None = None
    failure_class: str | None = None
    error_code: str | None = None


class Provider(Protocol):
    def complete(
        self,
        input_chunk: tuple[Any, ...],
        context: ProviderContext,
    ) -> ProviderResponse:
        raise NotImplementedError
