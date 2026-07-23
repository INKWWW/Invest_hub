from __future__ import annotations

import time
import uuid
from collections.abc import Mapping
from datetime import datetime
from typing import Callable
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from ..config import LocalWorkerConfig
from .base import ConnectorError, RawPage


def _normalized_request_url(url: str) -> str:
    parts = urlsplit(url)
    query = [(key, value) for key, value in parse_qsl(parts.query, keep_blank_values=True) if key not in {"_v2", "cache_buster"}]
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(sorted(query)), ""))


class XActiveAdapter:
    """Bounded OpenCLI transport adapter; it never owns login state or persistence."""

    def __init__(self, invoker: object, *, page_timeout_seconds: float = 90.0, clock: Callable[[], float] = time.monotonic) -> None:
        self.invoker = invoker
        self.page_timeout_seconds = page_timeout_seconds
        self.clock = clock

    def fetch_page(self, source: LocalWorkerConfig, cursor: str | None, *, end_at: datetime | None = None) -> RawPage:
        if source.source_type != "x":
            raise ConnectorError("X adapter requires an X source", code="preflight")
        started = self.clock()
        response = self._fetch(source, cursor, None)
        entry, state = self._match(response)
        attempts = 1
        if entry is None:
            self._deadline(started)
            response = self._fetch(source, cursor, f"v2-{uuid.uuid4().hex}")
            entry, state = self._match(response)
            attempts = 2
        self._deadline(started)
        if entry is None:
            raise ConnectorError("X network response is not fresh", code="opencli_missing" if state == "missing" else "opencli_stale")
        posts = entry.get("posts") or []
        if not isinstance(posts, list) or not all(isinstance(post, dict) for post in posts):
            raise ConnectorError("X network posts must be a list", code="opencli_contract")
        page_id = str(entry.get("page_id") or response.get("page_id") or f"page-{uuid.uuid4().hex}")
        cursor_after = entry.get("cursor_after", response.get("cursor_after"))
        telemetry: dict[str, object] = {"network_attempts": attempts, "match_state": "matched_new", "post_count": len(posts)}
        if end_at is not None:
            telemetry["collection_end_at"] = end_at.isoformat().replace("+00:00", "Z")
        return RawPage(page_id=page_id, source_id=source.source_id, cursor_before=cursor, cursor_after=str(cursor_after) if cursor_after is not None else None, messages=tuple(posts), raw_payload_ref=f"local://x/{page_id}", telemetry=telemetry, source_type="x")

    def _fetch(self, source: LocalWorkerConfig, cursor: str | None, cache_buster: str | None) -> Mapping[str, object]:
        try:
            response = self.invoker.fetch_page(source_url=source.source_url, profile_ref=source.profile_ref, cursor=cursor, cache_buster=cache_buster)
        except ConnectorError:
            raise
        except Exception as exc:
            raise ConnectorError("X Active Adapter invocation failed", code="opencli_contract") from exc
        if not isinstance(response, Mapping):
            raise ConnectorError("X Active Adapter response must be an object", code="opencli_contract")
        return response

    @staticmethod
    def _match(response: Mapping[str, object]) -> tuple[Mapping[str, object] | None, str]:
        network = response.get("network")
        expected_key, expected_url = response.get("expected_request_key"), response.get("expected_request_url")
        if not isinstance(network, list) or not network or not isinstance(expected_key, str) or not isinstance(expected_url, str):
            return None, "missing"
        normalized_expected = _normalized_request_url(expected_url)
        for candidate in network:
            if isinstance(candidate, Mapping) and candidate.get("request_key") == expected_key and isinstance(candidate.get("request_url"), str) and _normalized_request_url(str(candidate["request_url"])) == normalized_expected:
                return candidate, "matched_new"
        return None, "stale"

    def _deadline(self, started: float) -> None:
        if self.clock() - started >= self.page_timeout_seconds:
            raise ConnectorError("X page hard deadline exceeded", code="timeout")
