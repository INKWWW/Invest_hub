from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
from urllib.parse import urlparse

from .connectors.base import RawPage


class CanonicalValidationError(ValueError):
    pass


@dataclass(frozen=True)
class CanonicalMessage:
    source_id: str
    external_message_id: str
    author_id: str
    author_name: str
    occurred_at: str
    content: str
    reply_to_message_id: str | None
    quote: dict[str, Any] | None
    attachments: tuple[dict[str, Any], ...]
    unresolved: bool = False
    metadata: dict[str, Any] = field(default_factory=dict)


class Canonicalizer:
    def map(self, page: RawPage) -> tuple[CanonicalMessage, ...]:
        if page.source_type == "x":
            return self._map_x(page)
        ids = {str(item.get("id")) for item in page.messages if item.get("id") is not None}
        messages: list[CanonicalMessage] = []
        for item in page.messages:
            external_id = str(item.get("id") or "")
            if not external_id:
                raise CanonicalValidationError("message id is required")
            author = item.get("author") if isinstance(item.get("author"), dict) else {}
            author_id = str(author.get("id") or "")
            if not author_id:
                raise CanonicalValidationError(f"author id is required for {external_id}")
            reply = item.get("reply_to") if isinstance(item.get("reply_to"), dict) else None
            reply_id = str(reply.get("id")) if reply and reply.get("id") else None
            quote = item.get("quote") if isinstance(item.get("quote"), dict) else None
            attachments = item.get("attachments") if isinstance(item.get("attachments"), list) else []
            messages.append(
                CanonicalMessage(
                    source_id=page.source_id,
                    external_message_id=external_id,
                    author_id=author_id,
                    author_name=str(author.get("name") or ""),
                    occurred_at=str(item.get("published_at") or item.get("occurred_at") or ""),
                    content=str(item.get("content") or ""),
                    reply_to_message_id=reply_id,
                    quote=quote,
                    attachments=tuple(attachment for attachment in attachments if isinstance(attachment, dict)),
                    unresolved=reply_id is not None and reply_id not in ids,
                    metadata={"raw_payload_ref": page.raw_payload_ref},
                )
            )
        return tuple(messages)

    def _map_x(self, page: RawPage) -> tuple[CanonicalMessage, ...]:
        seen_ids: set[str] = set()
        messages: list[CanonicalMessage] = []
        for item in page.messages:
            external_id = str(item.get("id") or "")
            if not external_id or external_id in seen_ids:
                raise CanonicalValidationError("X post id must be stable and unique per page")
            seen_ids.add(external_id)
            author = item.get("author") if isinstance(item.get("author"), dict) else {}
            author_id = str(author.get("id") or "")
            if not author_id:
                raise CanonicalValidationError(f"X author id is required for {external_id}")
            occurred_at = str(item.get("created_at") or "")
            try:
                parsed_time = datetime.fromisoformat(occurred_at.replace("Z", "+00:00"))
            except ValueError as exc:
                raise CanonicalValidationError(f"X post time is invalid for {external_id}") from exc
            if parsed_time.tzinfo is None:
                raise CanonicalValidationError(f"X post time must include a timezone for {external_id}")
            post_type = str(item.get("post_type") or "")
            if post_type not in {"original", "quote", "reply", "repost"}:
                raise CanonicalValidationError(f"X post type is invalid for {external_id}")
            post_url = str(item.get("url") or "")
            url = urlparse(post_url)
            if url.scheme != "https" or (url.hostname or "").lower() not in {"x.com", "www.x.com", "twitter.com", "www.twitter.com"} or "/status/" not in url.path:
                raise CanonicalValidationError(f"X post URL is invalid for {external_id}")
            relation_names = {"quote": "quoted_post_id", "reply": "reply_to_post_id", "repost": "reposted_post_id"}
            relation_values = {name: item.get(name) for name in relation_names.values()}
            expected_relation = relation_names.get(post_type)
            if any((name == expected_relation) != bool(value) for name, value in relation_values.items()):
                raise CanonicalValidationError(f"X post context relation is invalid for {external_id}")
            content = str(item.get("text") or "")
            attachments = item.get("attachments") if isinstance(item.get("attachments"), list) else []
            context_status = str(item.get("context_status") or "complete")
            if context_status not in {"complete", "unavailable", "deleted", "unresolved"}:
                raise CanonicalValidationError(f"X context status is invalid for {external_id}")
            context_post = item.get("context_post")
            compact_context: dict[str, Any] | None = None
            if context_post is not None:
                if not isinstance(context_post, dict) or expected_relation is None:
                    raise CanonicalValidationError(f"X context post is invalid for {external_id}")
                context_id = str(context_post.get("id") or "")
                if context_id != str(item.get(expected_relation) or ""):
                    raise CanonicalValidationError(f"X context post does not match relation for {external_id}")
                context_url = str(context_post.get("url") or "")
                parsed_context_url = urlparse(context_url)
                if parsed_context_url.scheme != "https" or (parsed_context_url.hostname or "").lower() not in {"x.com", "www.x.com", "twitter.com", "www.twitter.com"} or "/status/" not in parsed_context_url.path:
                    raise CanonicalValidationError(f"X context URL is invalid for {external_id}")
                context_author = context_post.get("author") if isinstance(context_post.get("author"), dict) else {}
                compact_context = {
                    "id": context_id,
                    "author_id": str(context_author.get("id") or "") or None,
                    "author_name": str(context_author.get("name") or "") or None,
                    "text": str(context_post.get("text") or ""),
                    "url": context_url,
                }
            if context_status == "complete" and expected_relation is not None and compact_context is None:
                raise CanonicalValidationError(f"X complete context content is required for {external_id}")
            messages.append(CanonicalMessage(
                source_id=page.source_id, external_message_id=external_id, author_id=author_id,
                author_name=str(author.get("name") or ""), occurred_at=occurred_at, content=content,
                reply_to_message_id=str(item.get("reply_to_post_id") or "") or None, quote=None,
                attachments=tuple(value for value in attachments if isinstance(value, dict)),
                metadata={"raw_payload_ref": page.raw_payload_ref, "x": {
                    "post_type": post_type, "post_url": post_url, "quoted_post_id": str(item.get("quoted_post_id") or "") or None,
                    "reply_to_post_id": str(item.get("reply_to_post_id") or "") or None, "reposted_post_id": str(item.get("reposted_post_id") or "") or None,
                    "context_status": context_status, "attachments": [value for value in attachments if isinstance(value, dict)],
                    "context_post": compact_context,
                }},
            ))
        return tuple(messages)
