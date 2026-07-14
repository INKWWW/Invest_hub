from __future__ import annotations

import json
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol

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


class OpenCLIInvoker(Protocol):
    def fetch_page(
        self,
        *,
        channel_url: str,
        profile_path: Path,
        cursor: str | None,
    ) -> Mapping[str, Any]:
        raise NotImplementedError


class SubprocessOpenCLIInvoker:
    def __init__(
        self,
        contract_path: Path,
        *,
        executable_override: str | None = None,
        runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ) -> None:
        try:
            self._contract = json.loads(contract_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ConnectorError(f"contract read failed: {exc}") from exc
        if executable_override is not None:
            self._contract["executable"] = executable_override
        self._runner = runner
        self._version_checked = False

    def fetch_page(
        self,
        *,
        channel_url: str,
        profile_path: Path,
        cursor: str | None,
    ) -> Mapping[str, Any]:
        self._ensure_version()
        command = [
            str(self._contract["executable"]),
            *self._render_args(
                channel_url=channel_url,
                profile_path=profile_path,
                cursor=cursor,
            ),
        ]
        completed = self._runner(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if completed.returncode != 0:
            raise ConnectorError(f"OpenCLI exit code {completed.returncode}")
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise ConnectorError("OpenCLI output is invalid JSON") from exc
        if not isinstance(payload, dict):
            raise ConnectorError("OpenCLI JSON output must be an object")
        return payload

    def _ensure_version(self) -> None:
        if self._version_checked:
            return
        executable = str(self._contract["executable"])
        completed = self._runner(
            [executable, "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        if completed.returncode != 0:
            raise ConnectorError("OpenCLI version check failed")
        actual = completed.stdout.strip()
        expected = str(self._contract["version"])
        if actual != expected:
            raise ConnectorError(
                f"OpenCLI version mismatch: expected {expected}, got {actual}"
            )
        self._version_checked = True

    def _render_args(
        self,
        *,
        channel_url: str,
        profile_path: Path,
        cursor: str | None,
    ) -> list[str]:
        template = list(self._contract["args_template"])
        rendered: list[str] = []
        for token in template:
            if token == "{cursor}":
                if cursor is not None:
                    rendered.append(cursor)
                elif rendered and rendered[-1] in {"--cursor", "--checkpoint"}:
                    rendered.pop()
                continue
            rendered.append(
                str(token)
                .replace("{channel_url}", channel_url)
                .replace("{profile_path}", str(profile_path))
            )
        return rendered


class OpenCLIConnector:
    def __init__(
        self,
        invoker: OpenCLIInvoker,
        *,
        source_account_id: str,
    ) -> None:
        self._invoker = invoker
        self._source_account_id = source_account_id

    def iter_pages(
        self,
        config: SourceConfig,
        checkpoint: Checkpoint | None,
    ) -> Iterator[RawPage]:
        cursor = checkpoint.cursor if checkpoint is not None else None
        collected = 0
        while collected < config.max_messages:
            if not config.profile_path:
                raise ConnectorError("Chrome Profile path is missing")
            payload = self._invoker.fetch_page(
                channel_url=config.channel_url,
                profile_path=Path(config.profile_path or ""),
                cursor=cursor,
            )
            page_id = str(payload.get("page_id") or "")
            if not page_id:
                raise ConnectorError("OpenCLI page_id is missing")
            raw_messages = payload.get("messages")
            if not isinstance(raw_messages, list):
                raise ConnectorError("OpenCLI messages must be a list")
            page = RawPage(
                page_id=page_id,
                source_container_id=str(payload.get("source_container_id") or ""),
                cursor_before=payload.get("cursor_before", cursor),
                cursor_after=payload.get("cursor_after"),
                messages=tuple(
                    RawMessage(ordinal=index, payload=message)
                    for index, message in enumerate(raw_messages)
                    if isinstance(message, dict)
                ),
                raw_payload_ref=str(
                    payload.get("raw_payload_ref") or f"opencli://{page_id}"
                ),
            )
            yield page
            collected += len(page.messages)
            next_cursor = page.cursor_after
            if next_cursor is None:
                break
            if next_cursor == cursor:
                raise ConnectorError("OpenCLI cursor did not advance")
            cursor = next_cursor
