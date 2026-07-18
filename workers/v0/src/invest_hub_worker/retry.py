from __future__ import annotations

import time
from dataclasses import dataclass, replace
from typing import Any

from .providers.base import Provider, ProviderContext, ProviderResponse


RETRYABLE_STATUSES = frozenset(
    {"schema_error", "timeout", "provider_failure", "empty_response", "invalid_json"}
)


@dataclass(frozen=True)
class RetryPolicy:
    max_attempts: int = 3
    timeout_seconds: float = 240.0
    backoff_seconds: float = 0.0

    def __post_init__(self) -> None:
        if self.max_attempts < 1:
            raise ValueError("max_attempts must be positive")
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if self.backoff_seconds < 0:
            raise ValueError("backoff_seconds cannot be negative")

    def execute(
        self,
        provider: Provider,
        input_chunk: tuple[Any, ...],
        context: ProviderContext,
    ) -> ProviderResponse:
        """Run only this chunk, retrying bounded transient outcomes."""

        response: ProviderResponse | None = None
        for attempt in range(1, self.max_attempts + 1):
            attempt_context = replace(
                context,
                attempt=attempt,
                timeout_seconds=self.timeout_seconds,
            )
            try:
                response = provider.complete(input_chunk, attempt_context)
            except Exception:
                response = ProviderResponse(
                    status="provider_failure",
                    provider=provider.__class__.__name__.lower(),
                    model_reported=None,
                    prompt_version=context.prompt_version,
                    elapsed_ms=0,
                    attempt=attempt,
                    raw_ref=None,
                    parsed_output_ref=None,
                    failure_class="provider_failure",
                    error_code="provider_failure",
                )

            if response.status == "success" or response.status not in RETRYABLE_STATUSES:
                return response
            if attempt < self.max_attempts and self.backoff_seconds:
                time.sleep(self.backoff_seconds)

        assert response is not None
        return response

