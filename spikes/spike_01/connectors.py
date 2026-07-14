from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Protocol

from .model import Checkpoint, RawMessage, RawPage, SourceConfig


class ConnectorError(RuntimeError):
    """Raised when a source cannot provide the next page."""


class Connector(Protocol):
    def iter_pages(
        self,
        config: SourceConfig,
        checkpoint: Checkpoint | None,
    ) -> Iterator[RawPage]:
        raise NotImplementedError


class FakeConnector:
    def __init__(
        self,
        pages: tuple[RawPage, ...],
        *,
        fail_after_page: int | None = None,
    ) -> None:
        self._pages = pages
        self._fail_after_page = fail_after_page

    @classmethod
    def from_fixture(
        cls,
        path: Path,
        *,
        source_container_id: str,
        fail_after_page: int | None = None,
    ) -> "FakeConnector":
        payload = json.loads(path.read_text(encoding="utf-8"))
        raw_pages = payload.get("pages")
        if raw_pages is None:
            raw_pages = [payload]
        pages = []
        for page in raw_pages:
            if page.get("source_container_id", source_container_id) != source_container_id:
                raise ConnectorError("fixture source container mismatch")
            messages = tuple(
                RawMessage(ordinal=index, payload=message)
                for index, message in enumerate(page.get("messages", []))
            )
            pages.append(
                RawPage(
                    page_id=str(page["page_id"]),
                    source_container_id=source_container_id,
                    cursor_before=page.get("cursor_before"),
                    cursor_after=page.get("cursor_after"),
                    messages=messages,
                    raw_payload_ref=f"fixture://{path.name}/{page['page_id']}",
                )
            )
        return cls(tuple(pages), fail_after_page=fail_after_page)

    def iter_pages(
        self,
        config: SourceConfig,
        checkpoint: Checkpoint | None,
    ) -> Iterator[RawPage]:
        start = 0
        if checkpoint is not None and checkpoint.cursor is not None:
            found = False
            for index, page in enumerate(self._pages):
                if page.cursor_before == checkpoint.cursor:
                    start = index
                    found = True
                    break
                if page.cursor_after == checkpoint.cursor:
                    start = index + 1
                    found = True
                    break
            if not found:
                raise ConnectorError(
                    f"checkpoint cursor not found: {checkpoint.cursor}"
                )
        for relative_index, page in enumerate(self._pages[start:]):
            if (
                self._fail_after_page is not None
                and relative_index >= self._fail_after_page
            ):
                raise ConnectorError(f"fixture failure before {page.page_id}")
            yield page
