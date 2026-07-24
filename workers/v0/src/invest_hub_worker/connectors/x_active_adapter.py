from __future__ import annotations

import json
import subprocess
import time
import uuid
from collections.abc import Mapping
from datetime import datetime, timezone
from typing import Any, Callable
from urllib.parse import urlsplit

from ..config import LocalWorkerConfig
from .base import ConnectorError, RawPage


_RECEIPT_KEYS = {"completed", "stop_reason", "requested_until", "pages_fetched", "oldest_seen_at"}
_STOP_REASONS = {"time_boundary_reached", "cursor_exhausted"}
_X_LEGACY_TIMESTAMP_FORMAT = "%a %b %d %H:%M:%S %z %Y"


class XActiveAdapter:
    """Map one verified OpenCLI Collection response into a bounded X page."""

    def __init__(self, invoker: object, *, page_timeout_seconds: float = 90.0, clock: Callable[[], float] = time.monotonic) -> None:
        self.invoker = invoker
        self.page_timeout_seconds = page_timeout_seconds
        self.clock = clock

    def fetch_page(
        self,
        source: LocalWorkerConfig,
        cursor: str | None,
        *,
        lower_bound_at: datetime,
        end_at: datetime | None = None,
    ) -> RawPage:
        if source.source_type != "x":
            raise ConnectorError("X adapter requires an X source", code="preflight")
        if cursor is not None:
            raise ConnectorError("Collection does not accept a resumable cursor", code="opencli_contract")
        started = self.clock()
        response = self._fetch(source, cursor, lower_bound_at, end_at)
        self._deadline(started)
        posts, receipt = _validate_collection_payload(response, lower_bound_at)
        if not all(isinstance(post, dict) for post in posts):
            raise ConnectorError("Collection posts must be normalized objects", code="opencli_contract")
        page_id = f"opencli-{uuid.uuid4().hex}"
        telemetry: dict[str, object] = {
            "match_state": "collection_receipt_verified",
            "collection_receipt_verified": True,
            "collection_stop_reason": receipt["stop_reason"],
            "collection_requested_until": receipt["requested_until"],
            "collection_oldest_seen_at": receipt["oldest_seen_at"],
            "collection_pages_fetched": receipt["pages_fetched"],
            "history_exhausted": receipt["stop_reason"] == "cursor_exhausted",
            "post_count": len(posts),
        }
        if end_at is not None:
            telemetry["collection_end_at"] = _instant_text(end_at)
        return RawPage(
            page_id=page_id,
            source_id=source.source_id,
            cursor_before=None,
            cursor_after=None,
            messages=tuple(posts),
            raw_payload_ref=f"local://x/{page_id}",
            telemetry=telemetry,
            source_type="x",
        )

    def _fetch(
        self,
        source: LocalWorkerConfig,
        cursor: str | None,
        lower_bound_at: datetime,
        end_at: datetime | None,
    ) -> Mapping[str, object]:
        try:
            response = self.invoker.fetch_page(
                source_url=source.source_url,
                profile_ref=source.profile_ref,
                cursor=cursor,
                cache_buster=None,
                lower_bound_at=lower_bound_at,
                end_at=end_at,
            )
        except ConnectorError:
            raise
        except Exception as exc:
            raise ConnectorError("X Collection invocation failed", code="opencli_contract") from exc
        if not isinstance(response, Mapping):
            raise ConnectorError("X Collection response must be an object", code="opencli_contract")
        return response

    def _deadline(self, started: float) -> None:
        if self.clock() - started >= self.page_timeout_seconds:
            raise ConnectorError("X Collection hard deadline exceeded", code="timeout")


class OpenCLICollectionInvoker:
    """Constrained bridge to ``opencli twitter collection`` with a completion receipt."""

    def __init__(self, executable: str = "opencli", *, limit: int = 10_000, timeout_seconds: float = 180.0, runner: Callable[..., Any] = subprocess.run) -> None:
        if not executable.strip() or not 1 <= limit <= 10_000 or timeout_seconds <= 0:
            raise ValueError("invalid OpenCLI X Collection invoker configuration")
        self.executable = executable
        self.limit = limit
        self.timeout_seconds = timeout_seconds
        self.runner = runner

    def fetch_page(
        self,
        *,
        source_url: str,
        profile_ref: str,
        cursor: str | None,
        cache_buster: str | None,
        lower_bound_at: datetime,
        end_at: datetime | None,
    ) -> Mapping[str, object]:
        del profile_ref, cache_buster
        if cursor is not None:
            raise ConnectorError("OpenCLI Collection does not expose a resumable cursor", code="opencli_contract")
        parts = urlsplit(source_url)
        handle = next((part for part in parts.path.split("/") if part), "")
        if not handle:
            raise ConnectorError("X source URL must name an account handle", code="preflight")
        lower_text = _collection_boundary_text(lower_bound_at)
        command = [
            self.executable,
            "twitter",
            "collection",
            handle,
            "--until",
            lower_text,
            "--limit",
            str(self.limit),
            "--page-delay",
            "0",
            "--site-session",
            "persistent",
            "-f",
            "json",
        ]
        try:
            result = self.runner(command, capture_output=True, text=True, timeout=self.timeout_seconds, check=False)
        except subprocess.TimeoutExpired as exc:
            raise ConnectorError("OpenCLI X Collection timed out", code="timeout") from exc
        except OSError as exc:
            raise ConnectorError("OpenCLI X command is unavailable", code="opencli_missing") from exc
        if getattr(result, "returncode", 1) != 0:
            raise ConnectorError("OpenCLI X Collection command failed", code="opencli_contract")
        try:
            payload = json.loads(str(getattr(result, "stdout", "")))
        except json.JSONDecodeError as exc:
            raise ConnectorError("OpenCLI X Collection output is not JSON", code="opencli_contract") from exc
        posts, receipt = _validate_collection_payload(payload, lower_bound_at)
        normalized = [self._normalize_row(post, handle) for post in posts]
        if end_at is not None:
            normalized = [post for post in normalized if _post_time(post) <= end_at]
        return {"posts": normalized, "receipt": receipt}

    @staticmethod
    def _normalize_row(row: Mapping[str, object], configured_handle: str) -> dict[str, object]:
        post_id = row.get("id")
        created_at = row.get("created_at")
        url = row.get("url")
        author_handle = row.get("author")
        if not all(isinstance(value, str) and value for value in (post_id, created_at, url, author_handle)):
            raise ConnectorError("OpenCLI Collection row lacks stable post fields", code="opencli_contract")
        created_at = _instant_text(_post_time({"created_at": created_at}))
        relation = row.get("relationship")
        if not isinstance(relation, Mapping):
            raise ConnectorError("OpenCLI Collection row lacks relationship facts", code="opencli_contract")
        kind = relation.get("kind")
        if kind not in {"original", "quote", "reply", "repost"}:
            raise ConnectorError("OpenCLI Collection relationship kind is invalid", code="opencli_contract")
        target = relation.get("target")
        if kind == "original":
            if target is not None:
                raise ConnectorError("OpenCLI Collection original has a relationship target", code="opencli_contract")
            return {
                "id": post_id,
                "author": {"id": author_handle.lower(), "name": str(row.get("name") or configured_handle)},
                "text": str(row.get("text") or ""),
                "created_at": created_at,
                "url": url,
                "post_type": "original",
                "context_status": "complete",
                "attachments": _attachments(row),
            }
        if not isinstance(target, Mapping):
            raise ConnectorError("OpenCLI Collection relationship target is missing", code="opencli_contract")
        target_id = target.get("post_id")
        if not isinstance(target_id, str) or not target_id:
            raise ConnectorError("OpenCLI Collection relationship target lacks a stable post ID", code="opencli_contract")
        relation_field = {"quote": "quoted_post_id", "reply": "reply_to_post_id", "repost": "reposted_post_id"}[str(kind)]
        context_status = _context_status(target.get("context_status"))
        post: dict[str, object] = {
            "id": post_id,
            "author": {"id": author_handle.lower(), "name": str(row.get("name") or configured_handle)},
            "text": "" if kind == "repost" else str(row.get("text") or ""),
            "created_at": created_at,
            "url": url,
            "post_type": kind,
            relation_field: target_id,
            "context_status": context_status,
            "attachments": _attachments(row),
        }
        if kind == "quote" and context_status == "complete":
            quoted = row.get("quoted_tweet")
            if not isinstance(quoted, Mapping):
                post["context_status"] = "unavailable"
            else:
                context = _quote_context(quoted, target_id)
                if context is None:
                    post["context_status"] = "unavailable"
                else:
                    post["context_post"] = context
        elif context_status == "complete":
            post["context_status"] = "unavailable"
        return post


def _validate_collection_payload(payload: object, lower_bound_at: datetime) -> tuple[list[Mapping[str, object]], dict[str, object]]:
    if not isinstance(payload, Mapping) or set(payload) != {"posts", "receipt"}:
        raise ConnectorError("OpenCLI X Collection output must contain only posts and receipt", code="opencli_contract")
    posts = payload.get("posts")
    receipt = payload.get("receipt")
    if not isinstance(posts, list) or not all(isinstance(post, Mapping) for post in posts):
        raise ConnectorError("OpenCLI X Collection posts must be a list", code="opencli_contract")
    if not isinstance(receipt, Mapping) or set(receipt) != _RECEIPT_KEYS:
        raise ConnectorError("OpenCLI X Collection receipt shape is invalid", code="opencli_contract")
    if receipt.get("completed") is not True or receipt.get("stop_reason") not in _STOP_REASONS:
        raise ConnectorError("OpenCLI X Collection did not prove completion", code="opencli_contract")
    requested_until = _required_instant(receipt.get("requested_until"), "Collection receipt requested_until")
    if requested_until != collection_boundary_at(lower_bound_at):
        raise ConnectorError("OpenCLI X Collection receipt lower boundary does not match the request", code="opencli_contract")
    pages_fetched = receipt.get("pages_fetched")
    if isinstance(pages_fetched, bool) or not isinstance(pages_fetched, int) or pages_fetched < 1:
        raise ConnectorError("OpenCLI X Collection receipt page count is invalid", code="opencli_contract")
    oldest_raw = receipt.get("oldest_seen_at")
    oldest_seen_at = None if oldest_raw is None else _required_instant(oldest_raw, "Collection receipt oldest_seen_at")
    if receipt["stop_reason"] == "time_boundary_reached" and (oldest_seen_at is None or oldest_seen_at > requested_until):
        raise ConnectorError("OpenCLI X Collection receipt did not reach the requested lower boundary", code="opencli_contract")
    return list(posts), {
        "completed": True,
        "stop_reason": str(receipt["stop_reason"]),
        "requested_until": _collection_boundary_text(requested_until),
        "pages_fetched": pages_fetched,
        "oldest_seen_at": _collection_boundary_text(oldest_seen_at) if oldest_seen_at is not None else None,
    }


def _attachments(row: Mapping[str, object]) -> list[dict[str, str]]:
    media_urls = row.get("media_urls")
    if not isinstance(media_urls, list):
        return []
    return [{"type": "media", "url": value} for value in media_urls if isinstance(value, str) and value]


def _context_status(value: object) -> str:
    if value == "complete":
        return "complete"
    if value == "deleted":
        return "deleted"
    if value in {"unavailable", "unresolved", "unknown", None}:
        return "unavailable" if value == "unavailable" else "unresolved"
    raise ConnectorError("OpenCLI Collection context status is invalid", code="opencli_contract")


def _quote_context(quoted: Mapping[str, object], expected_id: str) -> dict[str, object] | None:
    quoted_id = quoted.get("id")
    quoted_url = quoted.get("url")
    quoted_author = quoted.get("author")
    if not all(isinstance(value, str) and value for value in (quoted_id, quoted_url, quoted_author)) or quoted_id != expected_id:
        return None
    return {
        "id": quoted_id,
        "author": {"id": quoted_author.lower(), "name": str(quoted.get("name") or quoted_author)},
        "text": str(quoted.get("text") or ""),
        "url": quoted_url,
    }


def _required_aware_instant(value: datetime, label: str) -> datetime:
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise ConnectorError(f"{label} must include a timezone", code="opencli_contract")
    return value.astimezone(timezone.utc)


def _required_instant(value: object, label: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise ConnectorError(f"{label} is missing", code="opencli_contract")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ConnectorError(f"{label} is invalid", code="opencli_contract") from exc
    return _required_aware_instant(parsed, label)


def _instant_text(value: datetime) -> str:
    return _required_aware_instant(value, "timestamp").isoformat().replace("+00:00", "Z")


def collection_boundary_at(value: datetime) -> datetime:
    """Floor a collection boundary to OpenCLI's RFC3339 millisecond precision.

    The project can persist microsecond timestamps, whereas the pinned OpenCLI
    collection command accepts at most three fractional-second digits.  Floor,
    rather than round up, so the verified read includes a superset of the
    required overlap; downstream range filtering still uses the exact task
    boundary.
    """

    instant = _required_aware_instant(value, "Collection lower boundary")
    return instant.replace(microsecond=(instant.microsecond // 1_000) * 1_000)


def _collection_boundary_text(value: datetime) -> str:
    instant = collection_boundary_at(value)
    if instant.microsecond == 0:
        return _instant_text(instant)
    return instant.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _post_time(post: Mapping[str, object]) -> datetime:
    value = post.get("created_at")
    try:
        return _required_instant(value, "OpenCLI X post time")
    except ConnectorError as iso_error:
        if not isinstance(value, str):
            raise
        try:
            return _required_aware_instant(
                datetime.strptime(value, _X_LEGACY_TIMESTAMP_FORMAT),
                "OpenCLI X post time",
            )
        except ValueError:
            raise iso_error
