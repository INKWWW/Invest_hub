from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal, Mapping

RecordState = Literal[
    "accepted",
    "duplicate",
    "invalid",
    "unresolved_relation",
    "failed",
]


@dataclass(frozen=True)
class SourceConfig:
    source_container_id: str
    channel_url: str
    source_account_id: str
    max_messages: int = 1000
    profile_path: str | None = None


@dataclass(frozen=True)
class RawMessage:
    ordinal: int
    payload: Mapping[str, Any]


@dataclass(frozen=True)
class RawPage:
    page_id: str
    source_container_id: str
    cursor_before: str | None
    cursor_after: str | None
    messages: tuple[RawMessage, ...]
    raw_payload_ref: str
    telemetry: Mapping[str, Any] | None = None


@dataclass(frozen=True)
class Attachment:
    name: str
    content_type: str | None
    url: str | None


@dataclass(frozen=True)
class QuoteReference:
    external_item_id: str
    content_text: str | None
    resolved: bool


@dataclass(frozen=True)
class CanonicalMessage:
    source_type: Literal["discord"]
    source_account_id: str
    source_container_id: str
    external_item_id: str
    author_id: str
    author_name: str
    published_at: str
    content_text: str
    content_type: str
    parent_item_id: str | None
    quoted_item: QuoteReference | None
    attachments: tuple[Attachment, ...]
    source_url: str | None
    raw_payload_ref: str
    collected_at: str


@dataclass(frozen=True)
class ValidationIssue:
    code: str
    item_id: str | None
    field: str | None
    detail: str


@dataclass(frozen=True)
class ValidationReport:
    state: RecordState
    issues: tuple[ValidationIssue, ...]
    accepted_ids: tuple[str, ...]
    duplicate_ids: tuple[str, ...]
    unresolved_ids: tuple[str, ...]
    checkpoint_safe: bool


@dataclass(frozen=True)
class Checkpoint:
    source_container_id: str
    cursor: str | None
    last_external_item_id: str | None


@dataclass(frozen=True)
class RunReport:
    run_id: str
    source_container_id: str
    pages_seen: int
    raw_messages_seen: int
    accepted_messages: int
    duplicate_messages: int
    invalid_messages: int
    unresolved_messages: int
    checkpoint_before: Checkpoint | None
    checkpoint_after: Checkpoint | None
    status: Literal["success", "partial", "failed", "unverified"]
    errors: tuple[str, ...]
