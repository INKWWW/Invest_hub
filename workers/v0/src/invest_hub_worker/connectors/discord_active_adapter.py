from __future__ import annotations

import time
import uuid
from collections.abc import Iterable, Mapping
from typing import Callable
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from ..config import LocalWorkerConfig
from .base import ConnectorError, RawPage


def normalize_channel_url(url: str) -> str:
    parts = urlsplit(url)
    segments = [segment for segment in parts.path.split("/") if segment]
    if len(segments) >= 3 and segments[0] == "channels":
        segments = segments[:3]
    path = "/" + "/".join(segments)
    return urlunsplit((parts.scheme, parts.netloc, path.rstrip("/"), "", ""))


def _normalize_request_url(url: str) -> str:
    parts = urlsplit(url)
    query = [(key, value) for key, value in parse_qsl(parts.query, keep_blank_values=True) if key not in {"_v0", "cache_buster"}]
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(sorted(query)), ""))


class DiscordActiveAdapter:
    def __init__(
        self,
        invoker: object,
        *,
        page_timeout_seconds: float = 90.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.invoker = invoker
        self.page_timeout_seconds = page_timeout_seconds
        self.clock = clock

    def collect(
        self,
        source: LocalWorkerConfig,
        checkpoint: str | None,
        *,
        max_pages: int = 1,
        collection_mode: str = "history",
    ) -> Iterable[RawPage]:
        if max_pages < 1:
            raise ConnectorError("Discord page limit must be positive", code="preflight")
        if collection_mode not in {"history", "incremental"}:
            raise ConnectorError("Discord collection mode is invalid", code="preflight")
        cursor = checkpoint
        for _page_index in range(max_pages):
            started = self.clock()
            self._check_deadline(started)
            response = self._fetch(source, cursor, cache_buster=None, collection_mode=collection_mode)
            self._check_deadline(started)
            entry, match_state = self._match(response)
            network_attempts = 1
            if entry is None:
                self._check_deadline(started)
                response = self._fetch(
                    source,
                    cursor,
                    cache_buster=f"v0-{uuid.uuid4().hex}",
                    collection_mode=collection_mode,
                )
                self._check_deadline(started)
                entry, match_state = self._match(response)
                network_attempts = 2
            if entry is None:
                code = "opencli_missing" if match_state == "missing" else "opencli_stale"
                raise ConnectorError(f"Discord network response is {match_state}", code=code)

            cursor_after = entry.get("cursor_after", response.get("cursor_after"))
            page_id = str(entry.get("page_id") or response.get("page_id") or f"page-{uuid.uuid4().hex}")
            messages = entry.get("messages") or []
            if not isinstance(messages, list):
                raise ConnectorError("Discord network messages must be a list", code="opencli_contract")
            yield RawPage(
                page_id=page_id,
                source_id=source.source_id,
                cursor_before=cursor,
                cursor_after=str(cursor_after) if cursor_after is not None else None,
                messages=tuple(item for item in messages if isinstance(item, dict)),
                raw_payload_ref=f"local://discord/{page_id}",
                telemetry={"network_attempts": network_attempts, "match_state": "matched_new"},
            )
            if cursor_after is None:
                return
            cursor = str(cursor_after)

    def _fetch(
        self,
        source: LocalWorkerConfig,
        cursor: str | None,
        cache_buster: str | None,
        collection_mode: str,
    ) -> Mapping[str, object]:
        try:
            response = self.invoker.fetch_page(
                channel_url=normalize_channel_url(source.channel_url),
                profile_ref=source.profile_ref,
                cursor=cursor,
                cache_buster=cache_buster,
                collection_mode=collection_mode,
            )
        except ConnectorError:
            raise
        except Exception as exc:
            raise ConnectorError("Active Adapter invocation failed", code="opencli_contract") from exc
        if not isinstance(response, Mapping):
            raise ConnectorError("Active Adapter response must be an object", code="opencli_contract")
        return response

    @staticmethod
    def _match(response: Mapping[str, object]) -> tuple[Mapping[str, object] | None, str]:
        network = response.get("network")
        if not isinstance(network, list):
            return None, "missing"
        if not network:
            return None, "missing"
        expected_key = response.get("expected_request_key")
        expected_url = response.get("expected_request_url")
        if not isinstance(expected_key, str) or not isinstance(expected_url, str):
            return None, "missing"
        normalized_expected = _normalize_request_url(expected_url)
        for candidate in network:
            if not isinstance(candidate, Mapping):
                continue
            if candidate.get("request_key") == expected_key and isinstance(candidate.get("request_url"), str):
                if _normalize_request_url(str(candidate["request_url"])) == normalized_expected:
                    return candidate, "matched_new"
        return None, "stale"

    def _check_deadline(self, started: float) -> None:
        if self.clock() - started >= self.page_timeout_seconds:
            raise ConnectorError("Discord page hard deadline exceeded", code="timeout")
