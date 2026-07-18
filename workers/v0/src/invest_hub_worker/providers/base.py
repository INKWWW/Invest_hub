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

    def __post_init__(self) -> None:
        if not self.chunk_id.strip():
            raise ValueError("chunk_id must be non-empty")
        if not self.prompt_version.strip():
            raise ValueError("prompt_version must be non-empty")
        if self.attempt < 1:
            raise ValueError("attempt must be positive")
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")


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

