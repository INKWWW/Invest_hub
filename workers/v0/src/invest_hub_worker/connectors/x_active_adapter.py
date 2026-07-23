from __future__ import annotations

import json
import subprocess
import time
import uuid
from collections.abc import Mapping
from datetime import datetime
from typing import Any, Callable
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
        response = self._fetch(source, cursor, None, end_at)
        entry, state = self._match(response)
        attempts = 1
        if entry is None:
            self._deadline(started)
            response = self._fetch(source, cursor, f"v2-{uuid.uuid4().hex}", end_at)
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
        telemetry: dict[str, object] = {"network_attempts": attempts, "match_state": "matched_new", "post_count": len(posts), "history_exhausted": entry.get("history_exhausted") is True}
        if end_at is not None:
            telemetry["collection_end_at"] = end_at.isoformat().replace("+00:00", "Z")
        return RawPage(page_id=page_id, source_id=source.source_id, cursor_before=cursor, cursor_after=str(cursor_after) if cursor_after is not None else None, messages=tuple(posts), raw_payload_ref=f"local://x/{page_id}", telemetry=telemetry, source_type="x")

    def _fetch(self, source: LocalWorkerConfig, cursor: str | None, cache_buster: str | None, end_at: datetime | None) -> Mapping[str, object]:
        try:
            response = self.invoker.fetch_page(source_url=source.source_url, profile_ref=source.profile_ref, cursor=cursor, cache_buster=cache_buster, end_at=end_at)
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


class OpenCLITweetsInvoker:
    """Constrained bridge to the installed ``opencli twitter tweets`` adapter.

    OpenCLI retains the logged-in browser session; this class never reads a
    cookie or calls X directly.  It asks OpenCLI for a bounded chronological
    history in one invocation.  If that bounded history cannot prove the
    configured lower boundary, ``XWindowedRuntime`` refuses completion rather
    than silently advancing the checkpoint.
    """

    def __init__(self, executable: str = "opencli", *, limit: int = 10_000, timeout_seconds: float = 180.0, runner: Callable[..., Any] = subprocess.run) -> None:
        if not executable.strip() or not 1 <= limit <= 10_000 or timeout_seconds <= 0:
            raise ValueError("invalid OpenCLI X invoker configuration")
        self.executable = executable
        self.limit = limit
        self.timeout_seconds = timeout_seconds
        self.runner = runner

    def fetch_page(self, *, source_url: str, profile_ref: str, cursor: str | None, cache_buster: str | None, end_at: datetime | None) -> Mapping[str, object]:
        del profile_ref, cache_buster
        if cursor is not None:
            raise ConnectorError("OpenCLI tweets invocation does not expose a resumable cursor", code="opencli_contract")
        parts = urlsplit(source_url)
        handle = next((part for part in parts.path.split("/") if part), "")
        if not handle:
            raise ConnectorError("X source URL must name an account handle", code="preflight")
        command = [self.executable, "twitter", "tweets", handle, "--limit", str(self.limit), "--page-delay", "0", "--site-session", "persistent", "-f", "json"]
        try:
            result = self.runner(command, capture_output=True, text=True, timeout=self.timeout_seconds, check=False)
        except subprocess.TimeoutExpired as exc:
            raise ConnectorError("OpenCLI X collection timed out", code="timeout") from exc
        except OSError as exc:
            raise ConnectorError("OpenCLI X command is unavailable", code="opencli_missing") from exc
        if getattr(result, "returncode", 1) != 0:
            raise ConnectorError("OpenCLI X command failed", code="opencli_contract")
        try:
            rows = json.loads(str(getattr(result, "stdout", "")))
        except json.JSONDecodeError as exc:
            raise ConnectorError("OpenCLI X output is not JSON", code="opencli_contract") from exc
        if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
            raise ConnectorError("OpenCLI X output must be a post list", code="opencli_contract")
        posts = [self._normalize_row(row, handle) for row in rows]
        if end_at is not None:
            posts = [post for post in posts if _post_time(post) <= end_at]
        request_url = f"opencli://twitter/tweets/{handle}?limit={self.limit}"
        return {"expected_request_key": "opencli-twitter-tweets", "expected_request_url": request_url, "page_id": f"opencli-{uuid.uuid4().hex}", "network": [{"request_key": "opencli-twitter-tweets", "request_url": request_url, "posts": posts, "cursor_after": None, "history_exhausted": len(rows) < self.limit}]}

    @staticmethod
    def _normalize_row(row: Mapping[str, object], handle: str) -> dict[str, object]:
        post_id = row.get("id")
        created_at = row.get("created_at")
        url = row.get("url")
        if not all(isinstance(value, str) and value for value in (post_id, created_at, url)):
            raise ConnectorError("OpenCLI X row lacks stable post fields", code="opencli_contract")
        if row.get("is_retweet") is True:
            raise ConnectorError("OpenCLI tweets output lacks the original ID needed for a safe repost relation", code="opencli_contract")
        quoted = row.get("quoted_tweet")
        post: dict[str, object] = {"id": post_id, "author": {"id": handle.lower(), "name": str(row.get("author") or handle)}, "text": str(row.get("text") or ""), "created_at": created_at, "url": url, "post_type": "original", "context_status": "complete", "attachments": [{"type": "media", "url": value} for value in row.get("media_urls", []) if isinstance(value, str)] if isinstance(row.get("media_urls"), list) else []}
        if isinstance(quoted, Mapping):
            quoted_id = quoted.get("id")
            quoted_url = quoted.get("url")
            if not isinstance(quoted_id, str) or not quoted_id or not isinstance(quoted_url, str) or not quoted_url:
                raise ConnectorError("OpenCLI quote context is incomplete", code="opencli_contract")
            post.update({"post_type": "quote", "quoted_post_id": quoted_id, "context_status": "complete", "context_post": {"id": quoted_id, "author": {"id": str(quoted.get("author") or ""), "name": str(quoted.get("author") or "")}, "text": str(quoted.get("text") or ""), "url": quoted_url}})
        if row.get("in_reply_to_status_id") is not None:
            raise ConnectorError("OpenCLI reply context is incomplete", code="opencli_contract")
        return post


def _post_time(post: Mapping[str, object]) -> datetime:
    value = post.get("created_at")
    if not isinstance(value, str):
        raise ConnectorError("OpenCLI X post time is missing", code="opencli_contract")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ConnectorError("OpenCLI X post time is invalid", code="opencli_contract") from exc
    if parsed.tzinfo is None:
        raise ConnectorError("OpenCLI X post time has no timezone", code="opencli_contract")
    return parsed
