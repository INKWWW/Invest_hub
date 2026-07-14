from __future__ import annotations

from datetime import datetime, timezone

from .model import (
    Attachment,
    CanonicalMessage,
    QuoteReference,
    RawPage,
)


def normalize_page(
    page: RawPage,
    source_account_id: str,
) -> tuple[CanonicalMessage, ...]:
    collected_at = datetime.now(timezone.utc).isoformat()
    normalized: list[CanonicalMessage] = []
    for raw in page.messages:
        payload = raw.payload
        author = payload.get("author") or {}
        quote_payload = payload.get("quote")
        quote = None
        if quote_payload is not None:
            quote_data = quote_payload if isinstance(quote_payload, dict) else {}
            quote = QuoteReference(
                external_item_id=str(quote_data.get("id") or ""),
                content_text=quote_data.get("content"),
                resolved=bool(quote_data.get("resolved", False)),
            )

        attachments = tuple(
            Attachment(
                name=str(item.get("name") or ""),
                content_type=item.get("content_type"),
                url=item.get("url"),
            )
            for item in (
                payload.get("attachments") or []
                if isinstance(payload.get("attachments") or [], list)
                else []
            )
            if isinstance(item, dict)
        )
        reply_to = payload.get("reply_to")
        reply_id = None
        if isinstance(reply_to, dict) and reply_to.get("id"):
            reply_id = str(reply_to["id"])

        normalized.append(
            CanonicalMessage(
                source_type="discord",
                source_account_id=source_account_id,
                source_container_id=str(payload.get("channel_id") or ""),
                external_item_id=str(payload.get("id") or ""),
                author_id=str(author.get("id") or ""),
                author_name=str(author.get("name") or ""),
                published_at=str(payload.get("published_at") or ""),
                content_text=str(payload.get("content") or ""),
                content_type=str(payload.get("content_type") or "unknown"),
                parent_item_id=reply_id,
                quoted_item=quote,
                attachments=attachments,
                source_url=payload.get("source_url"),
                raw_payload_ref=page.raw_payload_ref,
                collected_at=collected_at,
            )
        )
    return tuple(normalized)
