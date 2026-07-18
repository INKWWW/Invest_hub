from __future__ import annotations

import threading
import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from .base import ProviderContext, ProviderResponse


@dataclass(frozen=True)
class MockOutcome:
    """A deterministic provider outcome for tests; it never performs I/O."""

    status: str
    parsed_output: dict[str, Any] | None = None
    error_code: str | None = None

    @classmethod
    def success(cls, parsed_output: Mapping[str, Any]) -> "MockOutcome":
        return cls("success", dict(parsed_output))

    @classmethod
    def schema_error(cls) -> "MockOutcome":
        return cls("schema_error", error_code="schema_error")

    @classmethod
    def invalid_json(cls) -> "MockOutcome":
        return cls("invalid_json", error_code="invalid_json")

    @classmethod
    def timeout(cls) -> "MockOutcome":
        return cls("timeout", error_code="timeout")

    @classmethod
    def provider_failure(cls) -> "MockOutcome":
        return cls("provider_failure", error_code="provider_failure")

    @classmethod
    def empty_response(cls) -> "MockOutcome":
        return cls("empty_response", error_code="empty_response")


class MockProvider:
    """Scripted Provider used by deterministic tests and local dry runs."""

    def __init__(self, scripts: Mapping[str, Sequence[MockOutcome]]) -> None:
        self._scripts = {chunk_id: tuple(outcomes) for chunk_id, outcomes in scripts.items()}
        self._calls: dict[str, int] = {}
        self._lock = threading.Lock()

    @property
    def call_count(self) -> int:
        with self._lock:
            return sum(self._calls.values())

    def calls_for(self, chunk_id: str) -> int:
        with self._lock:
            return self._calls.get(chunk_id, 0)

    def complete(
        self,
        input_chunk: tuple[Any, ...],
        context: ProviderContext,
    ) -> ProviderResponse:
        del input_chunk
        started = time.monotonic_ns()
        with self._lock:
            index = self._calls.get(context.chunk_id, 0)
            self._calls[context.chunk_id] = index + 1
        script = self._scripts.get(context.chunk_id, ())
        outcome = (
            script[index]
            if index < len(script)
            else MockOutcome.provider_failure()
        )
        status = outcome.status
        failure_class = None if status == "success" else status
        parsed_output = dict(outcome.parsed_output) if outcome.parsed_output is not None else None
        return ProviderResponse(
            status=status,
            provider="mock",
            model_reported="mock-deterministic",
            prompt_version=context.prompt_version,
            elapsed_ms=max(0, (time.monotonic_ns() - started) // 1_000_000),
            attempt=context.attempt,
            raw_ref=None,
            parsed_output_ref=None,
            parsed_output=parsed_output,
            failure_class=failure_class,
            error_code=outcome.error_code,
        )

