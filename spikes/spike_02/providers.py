from __future__ import annotations

import json
import socket
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .model import LLMRequest, ProviderResponse


class ProviderError(RuntimeError):
    """Raised only for invalid Provider configuration, not remote failures."""


class LLMProvider(Protocol):
    def complete(self, request: LLMRequest) -> ProviderResponse:
        raise NotImplementedError


@dataclass(frozen=True)
class MockOutcome:
    status: str
    content: str | None
    error_code: str | None
    finish_reason: str | None

    @classmethod
    def success(cls, content: str) -> "MockOutcome":
        return cls("success", content, None, "stop")

    @classmethod
    def failure(cls, status: str, error_code: str | None = None) -> "MockOutcome":
        return cls(status, None, error_code or status, None)

    @classmethod
    def truncated(cls, content: str) -> "MockOutcome":
        return cls("truncated", content, "output_truncated", "length")


class MockProvider:
    def __init__(self, scripts: Mapping[str, Sequence[MockOutcome]]):
        self._scripts = {chunk_id: tuple(outcomes) for chunk_id, outcomes in scripts.items()}
        self._calls: dict[str, int] = {}

    @property
    def call_count(self) -> int:
        return sum(self._calls.values())

    def calls_for(self, chunk_id: str) -> int:
        return self._calls.get(chunk_id, 0)

    def complete(self, request: LLMRequest) -> ProviderResponse:
        chunk_id = request.chunk.chunk_id
        call_index = self._calls.get(chunk_id, 0)
        self._calls[chunk_id] = call_index + 1
        script = self._scripts.get(chunk_id, ())
        if call_index >= len(script):
            outcome = MockOutcome.failure("provider_script_exhausted")
        else:
            outcome = script[call_index]
        return ProviderResponse(
            status=outcome.status,
            content=outcome.content,
            latency_ms=1,
            input_tokens=None,
            output_tokens=None,
            finish_reason=outcome.finish_reason,
            error_code=outcome.error_code,
        )


class GLMProvider:
    def __init__(
        self,
        *,
        endpoint: str,
        api_key: str,
        model: str,
        opener: Callable[..., Any] = urlopen,
        timeout_seconds: float = 30.0,
    ):
        if not endpoint.strip():
            raise ProviderError("endpoint must be non-empty")
        if not api_key.strip():
            raise ProviderError("api_key must be non-empty")
        if not model.strip():
            raise ProviderError("model must be non-empty")
        self.endpoint = endpoint
        self.api_key = api_key
        self.model = model
        self._opener = opener
        self.timeout_seconds = timeout_seconds

    def complete(self, request: LLMRequest) -> ProviderResponse:
        body = {
            "model": self.model,
            "messages": [{"role": "user", "content": request.chunk.prompt_text}],
            "temperature": 0,
            "response_format": {"type": "json_object"},
        }
        http_request = Request(
            self.endpoint,
            data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
        )
        started = time.monotonic_ns()
        try:
            with self._opener(http_request, timeout=self.timeout_seconds) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            return self._http_error(exc, _elapsed_ms(started))
        except (TimeoutError, socket.timeout):
            return self._response("timeout", _elapsed_ms(started), "timeout")
        except (URLError, OSError):
            return self._response(
                "provider_unavailable",
                _elapsed_ms(started),
                "provider_unavailable",
            )
        except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
            return self._response(
                "invalid_provider_response",
                _elapsed_ms(started),
                "invalid_provider_response",
            )

        try:
            choice = payload["choices"][0]
            message = choice["message"]
            content = message["content"]
            finish_reason = choice.get("finish_reason")
            usage = payload.get("usage") or {}
            input_tokens = _optional_int(usage.get("prompt_tokens"))
            output_tokens = _optional_int(usage.get("completion_tokens"))
        except (KeyError, IndexError, TypeError):
            return self._response(
                "invalid_provider_response",
                _elapsed_ms(started),
                "invalid_provider_response",
            )
        if not isinstance(content, str):
            return self._response(
                "invalid_provider_response",
                _elapsed_ms(started),
                "invalid_provider_response",
            )
        status = "truncated" if finish_reason == "length" else "success"
        return ProviderResponse(
            status=status,
            content=content,
            latency_ms=_elapsed_ms(started),
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            finish_reason=finish_reason,
            error_code="output_truncated" if status == "truncated" else None,
        )

    def _http_error(self, error: HTTPError, latency_ms: int) -> ProviderResponse:
        if error.code == 429:
            return self._response("rate_limited", latency_ms, "rate_limited")
        if error.code == 408:
            return self._response("timeout", latency_ms, "timeout")
        if error.code in {500, 502, 503, 504}:
            return self._response(
                "provider_unavailable",
                latency_ms,
                "provider_unavailable",
            )
        return self._response("provider_rejected", latency_ms, "provider_rejected")

    @staticmethod
    def _response(status: str, latency_ms: int, error_code: str) -> ProviderResponse:
        return ProviderResponse(
            status=status,
            content=None,
            latency_ms=latency_ms,
            input_tokens=None,
            output_tokens=None,
            finish_reason=None,
            error_code=error_code,
        )


def _elapsed_ms(started_ns: int) -> int:
    return max(0, (time.monotonic_ns() - started_ns) // 1_000_000)


def _optional_int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None
