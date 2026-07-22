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

    def __post_init__(self) -> None:
        if not self.chunk_id.strip():
            raise ValueError("chunk_id must be non-empty")
        if not self.prompt_version.strip():
            raise ValueError("prompt_version must be non-empty")
        if self.attempt < 1:
            raise ValueError("attempt must be positive")
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if self.operation not in {"legacy_topics", "v1_1_chunk", "v1_1_daily"}:
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
