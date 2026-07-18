from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

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
