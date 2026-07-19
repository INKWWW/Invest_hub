from __future__ import annotations

import json
import subprocess
import time
from collections.abc import Iterator
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol
from urllib.parse import parse_qs, urlparse

from .model import Checkpoint, RawMessage, RawPage, SourceConfig


class ConnectorError(RuntimeError):
    """Raised when a source cannot provide the next page."""

    def __init__(self, message: str, *, code: str = "command_failed") -> None:
        super().__init__(message)
        self.code = code


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


class BrowserBridgeOpenCLIInvoker:
    """Capture Discord pages through OpenCLI's read-only Browser Bridge.

    This is Spike-only glue for the installed OpenCLI surface. It deliberately
    does not read a Chrome profile or make authenticated HTTP requests itself;
    the bound OpenCLI browser session performs navigation and exposes the
    already-captured message response through ``browser network``.
    """

    def __init__(
        self,
        contract_path: Path,
        *,
        executable_override: str | None = None,
        page_timeout_seconds: int | None = None,
        runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ) -> None:
        try:
            self._contract = json.loads(contract_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ConnectorError(f"contract read failed: {exc}") from exc
        if self._contract.get("mode") != "browser_bridge_discord_network":
            raise ConnectorError("unsupported Browser Bridge contract mode")
        if executable_override is not None:
            self._contract["executable"] = executable_override
        self._runner = runner
        self._page_timeout_seconds = page_timeout_seconds
        self._deadline_ns: int | None = None
        self._version_checked = False
        self._initial_fetch_count = 0
        self.last_timing: dict[str, Any] = {}

    def fetch_page(
        self,
        *,
        channel_url: str,
        profile_path: Path,
        cursor: str | None,
    ) -> Mapping[str, Any]:
        del profile_path
        started_ns = time.monotonic_ns()
        if self._page_timeout_seconds is not None:
            self._deadline_ns = started_ns + self._page_timeout_seconds * 1_000_000_000
        else:
            self._deadline_ns = None
        phase_ms: dict[str, int] = {}
        network_attempts = 0
        match_state = "command_failed"
        self._ensure_version()
        channel_id = self._channel_id(channel_url)
        session = str(self._contract.get("browser_session") or "")
        if not session:
            raise ConnectorError("Browser Bridge session is missing")

        route = self._channel_route(channel_url)
        if cursor is not None:
            route = f"{route}/{cursor}"
        cache_buster = str(self._contract.get("cache_buster_param") or "")
        if cache_buster:
            route = self._cache_busted_route(route)
        try:
            baseline = self._run_json(self._network_command(session))
            baseline_keys = self._network_keys(baseline)

            phase_started_ns = time.monotonic_ns()
            self._run_json(["browser", session, "open", route])
            phase_ms["open_ms"] = self._elapsed_ms(phase_started_ns)

            phase_started_ns = time.monotonic_ns()
            wait_seconds = str(self._contract.get("wait_seconds", 1))
            self._run(["browser", session, "wait", "time", wait_seconds], timeout=120)
            phase_ms["wait_ms"] = self._elapsed_ms(phase_started_ns)

            phase_started_ns = time.monotonic_ns()
            key, network_attempts, match_state = self._wait_for_message_network(
                session,
                channel_id,
                cursor=cursor,
                baseline_keys=baseline_keys,
                route=route,
            )
            phase_ms["network_observation_ms"] = self._elapsed_ms(phase_started_ns)

            phase_started_ns = time.monotonic_ns()
            detail = self._run_json(
                ["browser", session, "network", "--detail", key]
            )
            phase_ms["detail_ms"] = self._elapsed_ms(phase_started_ns)
            messages = self._message_body(detail)
            if cursor is not None:
                older_messages = [
                    message
                    for message in messages
                    if self._is_older(str(message.get("id") or ""), cursor)
                ]
                if messages and not older_messages:
                    raise ConnectorError(
                        "Discord message response did not advance cursor",
                        code="cursor_not_advanced",
                    )
                messages = older_messages

            phase_started_ns = time.monotonic_ns()
            messages = [
                self._map_discord_message(message, channel_url)
                for message in messages
            ]
            phase_ms["mapping_ms"] = self._elapsed_ms(phase_started_ns)

            ids = [str(message.get("id") or "") for message in messages]
            ids = [message_id for message_id in ids if message_id]
            cursor_after = min(ids, key=self._numeric_or_text) if ids else None
            # A genuinely empty cursor-scoped response is the retained-history
            # boundary. A nonempty response with no older messages is rejected
            # above: it is not pagination progress.
            page_id = f"discord-{channel_id}-{cursor_after or 'initial'}"
            self.last_timing = {
                "elapsed_ms": self._elapsed_ms(started_ns),
                "network_attempts": network_attempts,
                "match_state": match_state,
                "error_code": None,
                **phase_ms,
            }
            return {
                "page_id": page_id,
                "source_container_id": channel_id,
                "cursor_before": cursor,
                "cursor_after": cursor_after,
                "messages": messages,
                "raw_payload_ref": f"opencli://browser-bridge/{page_id}",
                "_telemetry": self.last_timing,
            }
        except ConnectorError as exc:
            self.last_timing = {
                "elapsed_ms": self._elapsed_ms(started_ns),
                "network_attempts": getattr(exc, "network_attempts", network_attempts),
                "match_state": (
                    "timeout"
                    if exc.code == "timeout"
                    else (
                        exc.code
                        if exc.code in {
                            "matched_stale",
                            "missing",
                            "cursor_not_advanced",
                        }
                        else getattr(exc, "match_state", match_state)
                    )
                ),
                "error_code": exc.code,
                **phase_ms,
            }
            raise

    @staticmethod
    def _elapsed_ms(started_ns: int) -> int:
        return max(0, (time.monotonic_ns() - started_ns) // 1_000_000)

    @staticmethod
    def _network_keys(network: Mapping[str, Any]) -> frozenset[tuple[str, str]]:
        entries = network.get("entries")
        if not isinstance(entries, list):
            return frozenset()
        return frozenset(
            (str(entry.get("key")), str(entry.get("url") or ""))
            for entry in entries
            if isinstance(entry, dict) and entry.get("key")
        )

    def _wait_for_message_network(
        self,
        session: str,
        channel_id: str,
        *,
        cursor: str | None,
        baseline_keys: frozenset[tuple[str, str]],
        route: str,
    ) -> tuple[str, int, str]:
        retries = int(self._contract.get("network_retries", 5))
        wait_seconds = str(self._contract.get("network_wait_seconds", 1))
        last_error: ConnectorError | None = None
        reopened = False
        for attempt in range(max(1, retries)):
            network = self._run_json(self._network_command(session))
            try:
                key = self._message_network_key(
                    network,
                    channel_id,
                    cursor=cursor,
                    baseline_keys=baseline_keys,
                )
                return key, attempt + 1, "matched_new"
            except ConnectorError as exc:
                exc.network_attempts = attempt + 1
                last_error = exc
                if attempt + 1 >= max(1, retries):
                    break
                if exc.code == "missing" and not reopened:
                    reopened_route = self._cache_busted_route(route)
                    self._run_json(["browser", session, "open", reopened_route])
                    reopened = True
                self._run(
                    ["browser", session, "wait", "time", wait_seconds],
                    timeout=120,
                )
        raise last_error or ConnectorError(
            "Discord message network entry is missing",
            code="missing",
        )

    def _cache_busted_route(self, route: str) -> str:
        cache_buster = str(self._contract.get("cache_buster_param") or "")
        if not cache_buster:
            return route
        separator = "&" if "?" in route else "?"
        self._initial_fetch_count += 1
        nonce = f"{time.time_ns()}-{self._initial_fetch_count}"
        return f"{route}{separator}{cache_buster}={nonce}"

    def _network_command(self, session: str) -> list[str]:
        configured = self._contract.get("network_args", ["--all"])
        if not isinstance(configured, list) or not all(
            isinstance(item, str) for item in configured
        ):
            raise ConnectorError("Browser Bridge network_args contract is invalid")
        return ["browser", session, "network", *configured]

    def _ensure_version(self) -> None:
        if self._version_checked:
            return
        executable = str(self._contract.get("executable") or "")
        expected = str(self._contract.get("version") or "")
        if not executable or not expected:
            raise ConnectorError("Browser Bridge contract version is incomplete")
        completed = self._run(["--version"], timeout=15)
        actual = completed.stdout.strip()
        if actual != expected:
            raise ConnectorError(
                f"OpenCLI version mismatch: expected {expected}, got {actual}"
            )
        self._version_checked = True

    def _run(
        self,
        args: list[str],
        *,
        timeout: int,
    ) -> subprocess.CompletedProcess[str]:
        effective_timeout = float(timeout)
        if self._deadline_ns is not None:
            remaining_seconds = (
                self._deadline_ns - time.monotonic_ns()
            ) / 1_000_000_000
            if remaining_seconds <= 0:
                raise ConnectorError(
                    "OpenCLI Browser page operation timed out",
                    code="timeout",
                )
            effective_timeout = min(effective_timeout, remaining_seconds)
        executable = str(self._contract["executable"])
        try:
            completed = self._runner(
                [executable, *args],
                check=False,
                capture_output=True,
                text=True,
                timeout=max(0.1, effective_timeout),
            )
        except subprocess.TimeoutExpired as exc:
            raise ConnectorError(
                "OpenCLI Browser command timed out",
                code="timeout",
            ) from exc
        if completed.returncode != 0:
            detail = completed.stderr.strip()
            suffix = f": {detail}" if detail else ""
            raise ConnectorError(
                f"OpenCLI Browser command exit code {completed.returncode}{suffix}"
            )
        return completed

    def _run_json(self, args: list[str]) -> Mapping[str, Any]:
        completed = self._run(args, timeout=120)
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise ConnectorError("OpenCLI Browser output is invalid JSON") from exc
        if not isinstance(payload, dict):
            raise ConnectorError("OpenCLI Browser output must be an object")
        return payload

    @staticmethod
    def _channel_id(channel_url: str) -> str:
        parts = [part for part in urlparse(channel_url).path.split("/") if part]
        if len(parts) < 3 or parts[0] != "channels":
            raise ConnectorError("Discord channel URL is invalid")
        return parts[2]

    @staticmethod
    def _channel_route(channel_url: str) -> str:
        parsed = urlparse(channel_url)
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) < 3 or parts[0] != "channels":
            raise ConnectorError("Discord channel URL is invalid")
        return (
            f"{parsed.scheme}://{parsed.netloc}/channels/"
            f"{parts[1]}/{parts[2]}"
        )

    @staticmethod
    def _message_network_key(
        network: Mapping[str, Any],
        channel_id: str,
        *,
        cursor: str | None,
        baseline_keys: frozenset[tuple[str, str]],
    ) -> str:
        entries = network.get("entries")
        if not isinstance(entries, list):
            raise ConnectorError(
                "OpenCLI network output has no entries",
                code="missing",
            )
        expected_path = f"/api/v9/channels/{channel_id}/messages"
        saw_stale = False
        saw_wrong_cursor = False
        for entry in reversed(entries):
            if not isinstance(entry, dict):
                continue
            if entry.get("status") != 200:
                continue
            url = str(entry.get("url") or "")
            if urlparse(url).path != expected_path:
                continue
            key = str(entry.get("key") or "")
            if not key:
                continue
            if (key, url) in baseline_keys:
                saw_stale = True
                continue
            if cursor is not None:
                query = parse_qs(urlparse(url).query)
                if cursor in query.get("after", []):
                    saw_wrong_cursor = True
                    continue
                cursor_values = set(
                    query.get("around", []) + query.get("before", [])
                )
                if cursor not in cursor_values:
                    saw_wrong_cursor = True
                    continue
            return key
        if saw_wrong_cursor:
            raise ConnectorError(
                "Discord message network entry does not match cursor",
                code="cursor_not_advanced",
            )
        if saw_stale:
            error = ConnectorError(
                "Discord message network entry is stale",
                code="matched_stale",
            )
            error.match_state = "matched_stale"
            raise error
        raise ConnectorError(
            "Discord message network entry is missing",
            code="missing",
        )

    @staticmethod
    def _message_body(detail: Mapping[str, Any]) -> list[dict[str, Any]]:
        body = detail.get("body")
        if isinstance(body, str):
            try:
                body = json.loads(body)
            except json.JSONDecodeError as exc:
                raise ConnectorError("Discord message body is invalid JSON") from exc
        if not isinstance(body, list):
            raise ConnectorError("Discord message body must be a list")
        return [message for message in body if isinstance(message, dict)]

    @staticmethod
    def _map_discord_message(
        message: dict[str, Any],
        channel_url: str,
    ) -> dict[str, Any]:
        """Add the harness aliases while retaining the native Discord payload."""
        mapped = dict(message)
        raw_author = message.get("author")
        author = dict(raw_author) if isinstance(raw_author, dict) else {}
        author["name"] = str(
            author.get("global_name")
            or author.get("display_name")
            or author.get("username")
            or ""
        )
        mapped["author"] = author
        mapped["published_at"] = str(message.get("timestamp") or "")
        mapped["content_type"] = "text"

        reference = message.get("message_reference")
        if isinstance(reference, dict) and reference.get("message_id"):
            reply_id = str(reference["message_id"])
            mapped["reply_to"] = {"id": reply_id}
            referenced = message.get("referenced_message")
            if isinstance(referenced, dict) and referenced.get("id"):
                mapped["quote"] = {
                    "id": str(referenced["id"]),
                    "content": referenced.get("content"),
                    "resolved": True,
                }
            else:
                mapped["quote"] = {
                    "id": reply_id,
                    "content": None,
                    "resolved": False,
                }
        else:
            mapped["reply_to"] = None
            mapped["quote"] = None

        attachments = []
        raw_attachments = message.get("attachments")
        if isinstance(raw_attachments, list):
            for attachment in raw_attachments:
                if not isinstance(attachment, dict):
                    continue
                item = dict(attachment)
                item["name"] = str(
                    attachment.get("filename") or attachment.get("name") or ""
                )
                attachments.append(item)
        mapped["attachments"] = attachments

        parts = [part for part in urlparse(channel_url).path.split("/") if part]
        if len(parts) >= 3 and message.get("id"):
            base = f"{urlparse(channel_url).scheme}://{urlparse(channel_url).netloc}/channels/{parts[1]}/{parts[2]}"
            mapped["source_url"] = f"{base}/{message['id']}"
        else:
            mapped["source_url"] = None
        mapped["_discord_raw"] = message
        return mapped

    @staticmethod
    def _numeric_or_text(value: str) -> int | str:
        return int(value) if value.isdigit() else value

    @classmethod
    def _is_older(cls, message_id: str, cursor: str) -> bool:
        message_key = cls._numeric_or_text(message_id)
        cursor_key = cls._numeric_or_text(cursor)
        return message_key < cursor_key


def build_opencli_invoker(
    contract_path: Path,
    *,
    executable_override: str | None = None,
    page_timeout_seconds: int | None = None,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> OpenCLIInvoker:
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ConnectorError(f"contract read failed: {exc}") from exc
    if contract.get("mode") == "browser_bridge_discord_network":
        return BrowserBridgeOpenCLIInvoker(
            contract_path,
            executable_override=executable_override,
            page_timeout_seconds=page_timeout_seconds,
            runner=runner,
        )
    return SubprocessOpenCLIInvoker(
        contract_path,
        executable_override=executable_override,
        runner=runner,
    )


class OpenCLIConnector:
    def __init__(
        self,
        invoker: OpenCLIInvoker,
        *,
        source_account_id: str,
    ) -> None:
        self._invoker = invoker
        self._source_account_id = source_account_id
        self.last_page_timing: dict[str, Any] = {}

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
            try:
                payload = self._invoker.fetch_page(
                    channel_url=config.channel_url,
                    profile_path=Path(config.profile_path or ""),
                    cursor=cursor,
                )
            except ConnectorError:
                self.last_page_timing = dict(
                    getattr(self._invoker, "last_timing", {})
                )
                raise
            self.last_page_timing = dict(
                payload.get("_telemetry")
                if isinstance(payload.get("_telemetry"), dict)
                else getattr(self._invoker, "last_timing", {})
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
                telemetry=(
                    payload.get("_telemetry")
                    if isinstance(payload.get("_telemetry"), dict)
                    else None
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
