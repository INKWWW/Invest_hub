from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping
from zoneinfo import ZoneInfo

from .canonical import CanonicalMessage, Canonicalizer
from .config import LocalWorkerConfig, LocalWorkerConfigSet
from .connectors.base import ConnectorError, RawPage
from .connectors.discord_active_adapter import DiscordActiveAdapter, normalize_channel_url
from .evidence import LocalEvidenceStore
from .providers.base import Provider, ProviderContext
from .retry import RetryPolicy
from .summaries import SummaryError, build_batch_summaries


class RuntimeExecutionError(RuntimeError):
    def __init__(self, failure_class: str, message: str) -> None:
        super().__init__(message)
        self.failure_class = failure_class


@dataclass(frozen=True)
class TaskScope:
    mode: str
    max_pages: int

    @classmethod
    def from_claim(cls, claim: Mapping[str, Any]) -> "TaskScope":
        scope = claim.get("collection_scope")
        if not isinstance(scope, Mapping):
            raise ValueError("task collection_scope is required")
        mode = scope.get("mode")
        max_pages = scope.get("max_pages")
        if mode not in {"incremental", "history"} or isinstance(max_pages, bool) or not isinstance(max_pages, int):
            raise ValueError("task collection_scope is invalid")
        if not 1 <= max_pages <= 25 or (mode == "incremental" and max_pages > 5):
            raise ValueError("task collection_scope is out of range")
        return cls(mode=mode, max_pages=max_pages)


@dataclass(frozen=True)
class WindowedCaptureRange:
    """An immutable V1.1 capture range, expressed as UTC instants."""

    capture_range: dict[str, Any]
    start_at: datetime
    end_at: datetime
    resume_cursor: str | None

    @classmethod
    def from_claim(cls, claim: Mapping[str, Any]) -> "WindowedCaptureRange":
        scope = claim.get("collection_scope")
        if not isinstance(scope, Mapping) or dict(scope) != {"mode": "window"}:
            raise ValueError("window task collection_scope is invalid")
        raw_range = claim.get("capture_range")
        if not isinstance(raw_range, Mapping) or set(raw_range) != {
            "mode", "trigger", "timezone", "start_at", "end_at", "scheduled_window_key",
        }:
            raise ValueError("window task capture_range is invalid")
        if raw_range.get("mode") != "window" or raw_range.get("timezone") != "Asia/Shanghai":
            raise ValueError("window task capture_range is invalid")
        if raw_range.get("trigger") not in {"scheduled", "manual", "bootstrap"}:
            raise ValueError("window task capture_range trigger is invalid")
        scheduled_window_key = raw_range.get("scheduled_window_key")
        if raw_range.get("trigger") in {"manual", "bootstrap"} and scheduled_window_key is not None:
            raise ValueError("manual and bootstrap windows cannot carry a scheduled_window_key")
        if raw_range.get("trigger") == "scheduled" and (not isinstance(scheduled_window_key, str) or not scheduled_window_key):
            raise ValueError("scheduled window task requires a scheduled_window_key")
        if scheduled_window_key is not None and not isinstance(scheduled_window_key, str):
            raise ValueError("window task scheduled_window_key is invalid")
        start_at = _required_instant(raw_range.get("start_at"), "window start_at")
        end_at = _required_instant(raw_range.get("end_at"), "window end_at")
        if start_at >= end_at:
            raise ValueError("window task range is empty or inverted")
        if isinstance(scheduled_window_key, str):
            scheduled_end_at = _required_instant(scheduled_window_key, "scheduled_window_key")
            local_boundary = scheduled_end_at.astimezone(ZoneInfo("Asia/Shanghai"))
            if not scheduled_window_key.endswith("+08:00") or local_boundary.strftime("%H:%M") not in {"00:00", "08:00", "16:00", "20:50"}:
                raise ValueError("scheduled_window_key is not a Shanghai schedule boundary")
            if scheduled_end_at != end_at:
                raise ValueError("scheduled_window_key does not equal window end_at")

        progress = claim.get("capture_progress")
        if not isinstance(progress, Mapping) or set(progress) != {"resume_cursor", "page_count", "range_complete"}:
            raise ValueError("window task capture_progress is invalid")
        resume_cursor = progress.get("resume_cursor")
        if resume_cursor is not None and (not isinstance(resume_cursor, str) or not resume_cursor):
            raise ValueError("window task resume_cursor is invalid")
        if isinstance(progress.get("page_count"), bool) or not isinstance(progress.get("page_count"), int) or progress["page_count"] < 0:
            raise ValueError("window task page_count is invalid")
        if progress.get("range_complete") is not False:
            raise ValueError("window task is already complete")
        return cls(capture_range=dict(raw_range), start_at=start_at, end_at=end_at, resume_cursor=resume_cursor)


class BrowserBridgeRuntimeInvoker:
    """Bridge the validated Spike-01 Browser Bridge result into the V0 adapter.

    The underlying invoker navigates the explicitly bound Browser Bridge
    session and reads its captured Discord network response.  This wrapper
    does not access a Chrome profile or Discord HTTP API itself.
    """

    def __init__(self, contract_path: Path, *, executable_override: str | None = None) -> None:
        try:
            from spikes.spike_01.connectors import build_opencli_invoker
        except ImportError as exc:  # pragma: no cover - execution environment guard
            raise RuntimeExecutionError("opencli_missing", "Spike-01 Browser Bridge runtime is unavailable") from exc
        self._invoker = build_opencli_invoker(
            Path(contract_path),
            executable_override=executable_override,
            page_timeout_seconds=90,
        )

    def fetch_page(
        self,
        *,
        channel_url: str,
        profile_ref: str,
        cursor: str | None,
        cache_buster: str | None,
        collection_mode: str = "history",
    ) -> Mapping[str, object]:
        del cache_buster
        try:
            payload = self._invoker.fetch_page(
                channel_url=channel_url,
                profile_path=Path(profile_ref),
                cursor=cursor,
                cursor_mode=collection_mode,
            )
        except Exception as exc:
            code = getattr(exc, "code", "opencli_contract")
            raise ConnectorError("Browser Bridge collection failed", code=str(code)) from exc
        if not isinstance(payload, Mapping):
            raise ConnectorError("Browser Bridge payload must be an object", code="opencli_contract")
        page_id = payload.get("page_id")
        messages = payload.get("messages")
        if not isinstance(page_id, str) or not isinstance(messages, list):
            raise ConnectorError("Browser Bridge payload is incomplete", code="opencli_contract")
        request_url = f"{normalize_channel_url(channel_url)}?before={cursor or ''}"
        return {
            "expected_request_key": "discord-channel-messages",
            "expected_request_url": request_url,
            "network": [
                {
                    "request_key": "discord-channel-messages",
                    "request_url": request_url,
                    "page_id": page_id,
                    "cursor_after": payload.get("cursor_after"),
                    "messages": messages,
                }
            ],
        }


class AuthorizedDiscordRuntime:
    """Build one V0 execution bundle for an explicitly authorized Worker."""

    def __init__(
        self,
        *,
        config: LocalWorkerConfig,
        connector: Any,
        evidence: LocalEvidenceStore,
        canonicalizer: Canonicalizer,
        provider: Provider,
        prompt_template: str,
        retry_policy: RetryPolicy | None = None,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        if not prompt_template.strip():
            raise ValueError("prompt_template must be non-empty")
        self.config = config
        self.connector = connector
        self.evidence = evidence
        self.canonicalizer = canonicalizer
        self.provider = provider
        self.prompt_template = prompt_template
        self.retry_policy = retry_policy or RetryPolicy(max_attempts=3, timeout_seconds=240)
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def execute(self, claim: dict[str, Any]) -> dict[str, Any]:
        scope = claim.get("collection_scope")
        if isinstance(scope, Mapping) and scope.get("mode") == "window":
            return self.execute_windowed(claim)
        scope, target_author_ids = self._validate_claim(claim)
        raw_messages: list[dict[str, Any]] = []
        canonical_by_id: dict[str, CanonicalMessage] = {}
        checkpoints: list[str | None] = [claim.get("safe_checkpoint")]
        duplicate_count = 0

        try:
            for page in self.connector.collect(
                self.config,
                claim.get("safe_checkpoint"),
                max_pages=scope.max_pages,
                collection_mode=scope.mode,
            ):
                self.evidence.persist_raw(page)
                mapped = self.canonicalizer.map(page)
                local_counts = self.evidence.persist_canonical(mapped)
                duplicate_count += int(local_counts.get("duplicate_count", 0))
                for message in mapped:
                    if message.external_message_id in canonical_by_id:
                        duplicate_count += 1
                        continue
                    canonical_by_id[message.external_message_id] = message
                    raw_messages.append(self._raw_message(page, message.external_message_id))
                checkpoints.append(page.cursor_after if page.cursor_after is not None else checkpoints[-1])
        except ConnectorError as exc:
            raise RuntimeExecutionError(str(exc.code), "Discord collection failed") from exc
        except Exception as exc:
            raise RuntimeExecutionError("persistence_failure", "local evidence persistence failed") from exc

        canonical_messages = list(canonical_by_id.values())
        structured_runs, retry_count, elapsed_ms = self._structured_runs(claim, canonical_messages, target_author_ids)
        try:
            batch_summaries = build_batch_summaries(canonical_messages, structured_runs) if canonical_messages else []
        except SummaryError as exc:
            raise RuntimeExecutionError("schema_error", "structured output cannot form a batch summary") from exc
        unresolved_count = sum(1 for message in canonical_messages if message.unresolved)
        unparsed_media_count = sum(1 for message in canonical_messages if message.attachments)
        persistence = {
            "contract_version": "v0",
            "task_id": str(claim["task_id"]),
            "attempt": int(claim["attempt"]),
            "source_id": self.config.source_id,
            "raw_messages": raw_messages,
            "canonical_messages": [self._canonical_message(message) for message in canonical_messages],
            "structured_runs": structured_runs,
            "batch_summaries": batch_summaries,
        }
        result = {
            "contract_version": "v0",
            "task_id": str(claim["task_id"]),
            "attempt": int(claim["attempt"]),
            "status": "succeeded",
            "safe_checkpoint": checkpoints[-1],
            "raw_count": len(raw_messages),
            "canonical_count": len(canonical_messages),
            "duplicate_count": duplicate_count,
            "unresolved_count": unresolved_count,
            "unparsed_media_count": unparsed_media_count,
            "structured_run_ids": [],
            "telemetry": {
                "elapsed_ms": elapsed_ms,
                "retry_count": retry_count,
                "failure_class": None,
            },
        }
        return {"persistence": persistence, "result": result}

    def execute_windowed(
        self,
        claim: dict[str, Any],
        *,
        on_capture_page: Callable[[dict[str, Any]], None] | None = None,
    ) -> dict[str, Any]:
        """Collect one immutable range until its lower boundary is proven.

        ``on_capture_page`` is supplied by :class:`Worker` in the real path.
        It acknowledges a page's durable facts and its resume segment before
        this method requests another page.  Leaving it unset is only retained
        for deterministic direct-runtime tests and produces the same segment
        payloads for the compatibility worker path.
        """

        capture_range, target_author_ids = self._validate_windowed_claim(claim)
        cursor = capture_range.resume_cursor
        canonical_by_id: dict[str, CanonicalMessage] = {}
        duplicate_count = 0
        capture_segments: list[dict[str, Any]] = []
        boundary: dict[str, str] | None = None

        try:
            while boundary is None:
                page = self.connector.fetch_page(self.config, cursor, end_at=capture_range.end_at)
                self._validate_window_page(page, cursor)
                page_times = [_required_instant(message.occurred_at, "Discord message occurred_at") for message in self.canonicalizer.map(page)]
                self.evidence.persist_raw(page)
                mapped = self.canonicalizer.map(page)
                local_counts = self.evidence.persist_canonical(mapped)
                duplicate_count += int(local_counts.get("duplicate_count", 0))

                page_raw_messages = [self._raw_message(page, message.external_message_id) for message in mapped]
                page_canonical_messages = [self._canonical_message(message) for message in mapped]
                for message, occurred_at in zip(mapped, page_times, strict=True):
                    if message.external_message_id in canonical_by_id:
                        duplicate_count += 1
                        continue
                    if capture_range.start_at < occurred_at <= capture_range.end_at:
                        canonical_by_id[message.external_message_id] = message

                segment = self._capture_segment(page, cursor, page_times)
                page_execution = {
                    "persistence": {
                        "contract_version": "v0",
                        "task_id": str(claim["task_id"]),
                        "attempt": int(claim["attempt"]),
                        "source_id": self.config.source_id,
                        "raw_messages": page_raw_messages,
                        "canonical_messages": page_canonical_messages,
                        "structured_runs": [],
                        "capture_segment": segment,
                    },
                    "capture_segment": {
                        "contract_version": "v0",
                        "task_id": str(claim["task_id"]),
                        "attempt": int(claim["attempt"]),
                        "capture_segment": segment,
                    },
                }
                if on_capture_page is None:
                    capture_segments.append(page_execution["capture_segment"])
                else:
                    on_capture_page(page_execution)

                if not mapped:
                    boundary = {
                        "kind": "history_exhausted",
                        "observed_at": _instant_text(self.clock()),
                    }
                elif min(page_times) <= capture_range.start_at:
                    boundary = {
                        "kind": "oldest_at_or_before_start",
                        "observed_at": _instant_text(min(page_times)),
                    }
                elif page.cursor_after is None:
                    boundary = {
                        "kind": "history_exhausted",
                        "observed_at": _instant_text(min(page_times)),
                    }
                else:
                    cursor = page.cursor_after
        except ConnectorError as exc:
            raise RuntimeExecutionError(str(exc.code), "Discord collection failed") from exc
        except RuntimeExecutionError:
            raise
        except ValueError as exc:
            raise RuntimeExecutionError("schema_error", "window page has an invalid timestamp or shape") from exc
        except Exception as exc:
            raise RuntimeExecutionError("persistence_failure", "windowed local evidence persistence failed") from exc

        canonical_messages = list(canonical_by_id.values())
        structured_runs, retry_count, elapsed_ms = self._structured_runs(claim, canonical_messages, target_author_ids)
        try:
            batch_summaries = build_batch_summaries(canonical_messages, structured_runs) if canonical_messages else []
        except SummaryError as exc:
            raise RuntimeExecutionError("schema_error", "structured output cannot form a batch summary") from exc
        completion = {
            "contract_version": "v0",
            "task_id": str(claim["task_id"]),
            "attempt": int(claim["attempt"]),
            "range_complete": True,
            "capture_range": capture_range.capture_range,
            "boundary": boundary,
            "summary_batch_ids": [],
            "daily_summary_ids": [],
            "no_new_data": not canonical_messages,
        }
        return {
            "persistence": {
                "contract_version": "v0",
                "task_id": str(claim["task_id"]),
                "attempt": int(claim["attempt"]),
                "source_id": self.config.source_id,
                "raw_messages": [],
                "canonical_messages": [],
                "structured_runs": structured_runs,
                "batch_summaries": batch_summaries,
            },
            "capture_segments": capture_segments,
            "range_completion": completion,
            "telemetry": {
                "elapsed_ms": elapsed_ms,
                "retry_count": retry_count,
                "duplicate_count": duplicate_count,
            },
        }

    def _validate_claim(self, claim: Mapping[str, Any]) -> tuple[TaskScope, frozenset[str]]:
        if claim.get("source_id") != self.config.source_id:
            raise RuntimeExecutionError("unauthorized", "task source does not match the local authorized source")
        if claim.get("parameter_version") != self.config.parameter_version:
            raise RuntimeExecutionError("preflight", "task parameter version does not match local worker config")
        try:
            scope = TaskScope.from_claim(claim)
            snapshot = claim.get("rule_snapshot")
            if not isinstance(snapshot, Mapping):
                raise ValueError("task rule_snapshot is required")
            version = snapshot.get("version")
            target_author_ids = snapshot.get("target_author_ids")
            if isinstance(version, bool) or not isinstance(version, int) or version < 0:
                raise ValueError("task rule_snapshot version is invalid")
            if not isinstance(target_author_ids, list) or any(not isinstance(author_id, str) or not author_id for author_id in target_author_ids):
                raise ValueError("task rule_snapshot target authors are invalid")
            if len(set(target_author_ids)) != len(target_author_ids):
                raise ValueError("task rule_snapshot target authors are duplicated")
        except ValueError as exc:
            raise RuntimeExecutionError("preflight", str(exc)) from exc
        return scope, frozenset(target_author_ids)

    def _validate_windowed_claim(self, claim: Mapping[str, Any]) -> tuple[WindowedCaptureRange, frozenset[str]]:
        if claim.get("source_id") != self.config.source_id:
            raise RuntimeExecutionError("unauthorized", "task source does not match the local authorized source")
        if claim.get("parameter_version") != self.config.parameter_version:
            raise RuntimeExecutionError("preflight", "task parameter version does not match local worker config")
        try:
            capture_range = WindowedCaptureRange.from_claim(claim)
            profiles = claim.get("author_profile_snapshot")
            if not isinstance(profiles, list):
                raise ValueError("window task author profile snapshot is invalid")
            author_ids: list[str] = []
            for profile in profiles:
                if not isinstance(profile, Mapping) or set(profile) != {"author_id", "author_display", "author_handle", "enabled"}:
                    raise ValueError("window task author profile snapshot is invalid")
                author_id = profile.get("author_id")
                display = profile.get("author_display")
                handle = profile.get("author_handle")
                if not isinstance(author_id, str) or not author_id or not isinstance(display, str) or not display:
                    raise ValueError("window task author profile snapshot is invalid")
                if handle is not None and not isinstance(handle, str):
                    raise ValueError("window task author profile snapshot is invalid")
                if profile.get("enabled") is not True:
                    raise ValueError("window task author profile snapshot is invalid")
                author_ids.append(author_id)
            if len(set(author_ids)) != len(author_ids):
                raise ValueError("window task author profiles are duplicated")
        except ValueError as exc:
            raise RuntimeExecutionError("preflight", str(exc)) from exc
        return capture_range, frozenset(author_ids)

    def _validate_window_page(self, page: object, requested_cursor: str | None) -> None:
        if not isinstance(page, RawPage) or page.source_id != self.config.source_id:
            raise RuntimeExecutionError("opencli_contract", "window collection returned an invalid page")
        if page.cursor_before != requested_cursor:
            raise RuntimeExecutionError("opencli_contract", "window page cursor does not match the request")
        if page.cursor_after is not None and page.cursor_after == requested_cursor:
            raise RuntimeExecutionError("opencli_contract", "window cursor did not advance")
        telemetry = page.telemetry
        if telemetry.get("match_state") != "matched_new":
            raise RuntimeExecutionError("opencli_stale", "window page is not a fresh validated response")

    @staticmethod
    def _capture_segment(
        page: RawPage,
        request_cursor: str | None,
        page_times: list[datetime],
    ) -> dict[str, Any]:
        return {
            "idempotency_key": f"page:{page.page_id}",
            "request_cursor": request_cursor,
            "next_cursor": page.cursor_after,
            "oldest_occurred_at": _instant_text(min(page_times)) if page_times else None,
            "newest_occurred_at": _instant_text(max(page_times)) if page_times else None,
            "response_matched": True,
            "response_fresh": True,
        }

    def _structured_runs(
        self,
        claim: Mapping[str, Any],
        messages: list[CanonicalMessage],
        target_author_ids: frozenset[str],
    ) -> tuple[list[dict[str, Any]], int, int]:
        runs: list[dict[str, Any]] = []
        retries = 0
        elapsed_ms = 0
        for index in range(0, len(messages), 100):
            chunk = tuple(messages[index : index + 100])
            chunk_index = index // 100 + 1
            message_ids = [message.external_message_id for message in chunk]
            media_ids = [message.external_message_id for message in chunk if message.attachments]
            context = ProviderContext(
                chunk_id=f"{claim['task_id']}-{claim['attempt']}-chunk-{chunk_index}",
                prompt_version=self.config.parameter_version,
                prompt_text=self._prompt_for(chunk),
                input_message_ids=frozenset(message_ids),
                unparsed_media_message_ids=frozenset(media_ids),
                target_author_ids=target_author_ids,
            )
            response = self.retry_policy.execute(self.provider, chunk, context)
            retries += max(0, response.attempt - 1)
            elapsed_ms += response.elapsed_ms
            if response.status != "success" or response.parsed_output is None:
                failure = response.failure_class or response.error_code or "provider_failure"
                raise RuntimeExecutionError(str(failure), "Codex CLI did not produce a valid structured result")
            runs.append(
                {
                    "chunk_key": context.chunk_id,
                    "provider": response.provider,
                    "parameter_version": self.config.parameter_version,
                    "input_message_ids": message_ids,
                    "media_source_message_ids": media_ids,
                    "output": response.parsed_output,
                }
            )
        return runs, retries, elapsed_ms

    def _prompt_for(self, chunk: Iterable[CanonicalMessage]) -> str:
        payload = [
            {
                "external_message_id": message.external_message_id,
                "author_id": message.author_id,
                "author_name": message.author_name,
                "occurred_at": message.occurred_at,
                "content": message.content,
                "attachments_present": bool(message.attachments),
            }
            for message in chunk
        ]
        return f"{self.prompt_template}\n\n输入消息（仅本地 Codex CLI 可见）：\n{json.dumps(payload, ensure_ascii=False)}"

    def _raw_message(self, page: RawPage, external_message_id: str) -> dict[str, Any]:
        item = next((message for message in page.messages if str(message.get("id")) == external_message_id), {})
        occurred_at = _valid_datetime(item.get("published_at") or item.get("occurred_at"))
        payload = json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return {
            "external_message_id": external_message_id,
            "occurred_at": occurred_at,
            "local_raw_ref": page.raw_payload_ref,
            "payload_hash": hashlib.sha256(payload).hexdigest(),
            "retention_expires_at": (self.clock() + timedelta(days=365)).isoformat().replace("+00:00", "Z"),
        }

    @staticmethod
    def _canonical_message(message: CanonicalMessage) -> dict[str, Any]:
        return {
            "external_message_id": message.external_message_id,
            "occurred_at": _valid_datetime(message.occurred_at),
            "author_display": message.author_name or None,
            "content": message.content,
            "has_unparsed_media": bool(message.attachments),
            "metadata": {
                "author_id": message.author_id,
                "reply_to_message_id": message.reply_to_message_id,
                "unresolved": message.unresolved,
            },
        }


class AuthorizedDiscordRuntimeSet:
    """Route each claim to exactly one owner-configured local source."""

    def __init__(self, runtimes: Mapping[str, AuthorizedDiscordRuntime]) -> None:
        self._runtimes = dict(runtimes)

    def execute(self, claim: dict[str, Any]) -> dict[str, Any]:
        source_id = claim.get("source_id")
        if not isinstance(source_id, str) or source_id not in self._runtimes:
            raise RuntimeExecutionError("unauthorized", "task source is not configured for this local Worker")
        return self._runtimes[source_id].execute(claim)

    def execute_windowed(
        self,
        claim: dict[str, Any],
        *,
        on_capture_page: Callable[[dict[str, Any]], None],
    ) -> dict[str, Any]:
        source_id = claim.get("source_id")
        if not isinstance(source_id, str) or source_id not in self._runtimes:
            raise RuntimeExecutionError("unauthorized", "task source is not configured for this local Worker")
        return self._runtimes[source_id].execute_windowed(claim, on_capture_page=on_capture_page)


def build_authorized_discord_runtime(
    *,
    config: LocalWorkerConfig,
    evidence_dir: Path,
    prompt_path: Path,
    opencli_contract_path: Path,
    opencli_executable: str | None = None,
) -> AuthorizedDiscordRuntime:
    prompt_template = Path(prompt_path).read_text(encoding="utf-8")
    invoker = BrowserBridgeRuntimeInvoker(Path(opencli_contract_path), executable_override=opencli_executable)
    return AuthorizedDiscordRuntime(
        config=config,
        connector=DiscordActiveAdapter(invoker),
        evidence=LocalEvidenceStore(Path(evidence_dir)),
        canonicalizer=Canonicalizer(),
        provider=_codex_provider(evidence_dir),
        prompt_template=prompt_template,
    )


def build_authorized_discord_runtime_set(
    *,
    config: LocalWorkerConfigSet,
    evidence_dir: Path,
    prompt_path: Path,
    opencli_contract_path: Path,
    opencli_executable: str | None = None,
) -> AuthorizedDiscordRuntimeSet:
    runtimes = {
        source.source_id: build_authorized_discord_runtime(
            config=source,
            evidence_dir=Path(evidence_dir) / source.source_id,
            prompt_path=prompt_path,
            opencli_contract_path=opencli_contract_path,
            opencli_executable=opencli_executable,
        )
        for source in config.sources
    }
    return AuthorizedDiscordRuntimeSet(runtimes)


def _codex_provider(evidence_dir: Path) -> Provider:
    from .providers.codex_cli import CodexCLIProvider

    return CodexCLIProvider(evidence_dir=Path(evidence_dir))


def _valid_datetime(value: object) -> str | None:
    if not isinstance(value, str) or not value.strip():
        return None
    normalized = value.strip().replace("Z", "+00:00")
    try:
        datetime.fromisoformat(normalized)
    except ValueError:
        return None
    return value.strip()


def _required_instant(value: object, field_name: str) -> datetime:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} is required")
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field_name} is invalid") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"{field_name} must be timezone-aware")
    return parsed.astimezone(timezone.utc)


def _instant_text(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
