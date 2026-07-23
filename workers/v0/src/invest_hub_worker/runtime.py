from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping
from zoneinfo import ZoneInfo

from .canonical import CanonicalMessage, Canonicalizer
from .config import LocalWorkerConfig, LocalWorkerConfigSet
from .connectors.base import ConnectorError, RawPage
from .connectors.discord_active_adapter import DiscordActiveAdapter, normalize_channel_url
from .connectors.x_active_adapter import OpenCLITweetsInvoker, XActiveAdapter
from .evidence import LocalEvidenceStore
from .providers.base import Provider, ProviderContext
from .retry import RetryPolicy
from .structured import (
    SchemaError,
    parse_v1_1_chunk_output,
    parse_v2_x_chunk_output,
    parse_v2_x_window_output,
    validate_v1_1_chunk_output,
    validate_v1_1_daily_output,
)
from .summaries import SummaryError, build_batch_summaries, build_v1_1_batch_summaries


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
    overlap_start_at: datetime | None = None

    @classmethod
    def from_claim(cls, claim: Mapping[str, Any]) -> "WindowedCaptureRange":
        scope = claim.get("collection_scope")
        if not isinstance(scope, Mapping) or scope.get("mode") not in {"window", "history"} or set(scope) != {"mode"}:
            raise ValueError("window task collection_scope is invalid")
        raw_range = claim.get("capture_range")
        allowed_range_keys = {"mode", "trigger", "timezone", "start_at", "end_at", "scheduled_window_key", "overlap_start_at"}
        if not isinstance(raw_range, Mapping) or not set(raw_range) <= allowed_range_keys:
            raise ValueError("window task capture_range is invalid")
        mode = scope["mode"]
        if raw_range.get("mode") != mode or raw_range.get("timezone") != "Asia/Shanghai":
            raise ValueError("window task capture_range is invalid")
        scheduled_window_key = raw_range.get("scheduled_window_key")
        if mode == "history":
            if set(raw_range) != {"mode", "trigger", "timezone", "start_at", "end_at"} or raw_range.get("trigger") != "history":
                raise ValueError("history task capture_range is invalid")
        else:
            if not {"mode", "trigger", "timezone", "start_at", "end_at", "scheduled_window_key"} <= set(raw_range):
                raise ValueError("window task capture_range is invalid")
            if raw_range.get("trigger") not in {"scheduled", "manual", "bootstrap"}:
                raise ValueError("window task capture_range trigger is invalid")
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
        overlap_start_at = None
        if "overlap_start_at" in raw_range:
            overlap_start_at = _required_instant(raw_range.get("overlap_start_at"), "window overlap_start_at")
            if overlap_start_at > start_at:
                raise ValueError("window overlap cannot be after the continuous start")
        if isinstance(scheduled_window_key, str):
            scheduled_end_at = _required_instant(scheduled_window_key, "scheduled_window_key")
            local_boundary = scheduled_end_at.astimezone(ZoneInfo("Asia/Shanghai"))
            if not scheduled_window_key.endswith("+08:00") or local_boundary.strftime("%H:%M") not in {"00:00", "08:00", "12:00", "16:00", "20:00", "20:50"}:
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
        return cls(capture_range=dict(raw_range), start_at=start_at, end_at=end_at, resume_cursor=resume_cursor, overlap_start_at=overlap_start_at)


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
        self.v1_1_chunk_template = _read_public_prompt("v1_1_discord_chunk.md")
        self.v1_1_daily_template = _read_public_prompt("v1_1_discord_daily.md")
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
        load_daily_fact_context: Callable[[], Mapping[str, Any]] | None = None,
        resolve_author_profiles: Callable[[], Mapping[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """Collect one immutable range until its lower boundary is proven.

        ``on_capture_page`` is supplied by :class:`Worker` in the real path.
        It acknowledges a page's durable facts and its resume segment before
        this method requests another page.  Leaving it unset is only retained
        for deterministic direct-runtime tests and produces the same segment
        payloads for the compatibility worker path.
        """

        capture_range, author_profile_snapshot = self._validate_windowed_claim(claim)
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
        author_profiles = self._resolve_windowed_author_profiles(
            author_profile_snapshot,
            resolve_author_profiles,
        )
        structured_runs, retry_count, elapsed_ms = self._structured_runs_v1_1(claim, canonical_messages, author_profiles)
        try:
            daily_outputs, daily_retries, daily_elapsed_ms = self._v1_1_daily_outputs(
                claim,
                canonical_messages,
                structured_runs,
                author_profiles,
                capture_range.end_at,
                self._load_daily_fact_context(load_daily_fact_context),
            )
            batch_summaries = build_v1_1_batch_summaries(canonical_messages, structured_runs, daily_outputs) if canonical_messages else []
        except SummaryError as exc:
            raise RuntimeExecutionError("schema_error", "structured output cannot form a batch summary") from exc
        retry_count += daily_retries
        elapsed_ms += daily_elapsed_ms
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

    def _validate_windowed_claim(self, claim: Mapping[str, Any]) -> tuple[WindowedCaptureRange, list[dict[str, Any]]]:
        if claim.get("source_id") != self.config.source_id:
            raise RuntimeExecutionError("unauthorized", "task source does not match the local authorized source")
        if claim.get("parameter_version") != self.config.parameter_version:
            raise RuntimeExecutionError("preflight", "task parameter version does not match local worker config")
        try:
            capture_range = WindowedCaptureRange.from_claim(claim)
            profiles = claim.get("author_profile_snapshot")
            if not isinstance(profiles, list):
                raise ValueError("window task author profile snapshot is invalid")
            author_profiles: list[dict[str, Any]] = []
            profile_ids: set[str] = set()
            legacy_author_ids: set[str] = set()
            for profile in profiles:
                if not isinstance(profile, Mapping):
                    raise ValueError("window task author profile snapshot is invalid")
                if set(profile) == {"author_id", "author_display", "author_handle", "enabled"}:
                    author_id = profile.get("author_id")
                    display = profile.get("author_display")
                    handle = profile.get("author_handle")
                    if not isinstance(author_id, str) or not author_id or not isinstance(display, str) or not display:
                        raise ValueError("window task author profile snapshot is invalid")
                    if handle is not None and not isinstance(handle, str):
                        raise ValueError("window task author profile snapshot is invalid")
                    if profile.get("enabled") is not True or author_id in legacy_author_ids:
                        raise ValueError("window task author profile snapshot is invalid")
                    legacy_author_ids.add(author_id)
                    author_profiles.append({
                        "profile_id": None,
                        "requested_author": display,
                        "resolution_status": "resolved",
                        "author_id": author_id,
                        "author_display": display,
                        "author_handle": handle,
                        "enabled": True,
                    })
                    continue
                if set(profile) != {"profile_id", "requested_author", "resolution_status", "author_id", "author_display", "author_handle", "enabled"}:
                    raise ValueError("window task author profile snapshot is invalid")
                profile_id = profile.get("profile_id")
                requested_author = profile.get("requested_author")
                status = profile.get("resolution_status")
                author_id = profile.get("author_id")
                display = profile.get("author_display")
                handle = profile.get("author_handle")
                if not isinstance(profile_id, str) or not profile_id or profile_id in profile_ids:
                    raise ValueError("window task author profile snapshot is invalid")
                if not isinstance(requested_author, str) or not requested_author or not isinstance(display, str) or not display:
                    raise ValueError("window task author profile snapshot is invalid")
                if status not in {"pending", "resolved", "ambiguous"} or profile.get("enabled") is not True:
                    raise ValueError("window task author profiles are duplicated")
                if handle is not None and not isinstance(handle, str):
                    raise ValueError("window task author profile snapshot is invalid")
                if status == "resolved":
                    if not isinstance(author_id, str) or not author_id:
                        raise ValueError("window task author profile snapshot is invalid")
                elif author_id is not None:
                    raise ValueError("window task author profile snapshot is invalid")
                profile_ids.add(profile_id)
                author_profiles.append(dict(profile))
        except ValueError as exc:
            raise RuntimeExecutionError("preflight", str(exc)) from exc
        return capture_range, author_profiles

    @staticmethod
    def _resolve_windowed_author_profiles(
        snapshot: list[dict[str, Any]],
        resolver: Callable[[], Mapping[str, Any]] | None,
    ) -> dict[str, str]:
        """Use only server-resolved stable identities in V1.1 author cards.

        New snapshots name a profile row and are re-resolved after every page is
        durably persisted.  Legacy snapshots already carry a stable identity
        and deliberately bypass the new endpoint so old queued work remains
        executable during the migration.
        """

        new_profiles = [profile for profile in snapshot if profile["profile_id"] is not None]
        resolved: list[Mapping[str, Any]] = [profile for profile in snapshot if profile["profile_id"] is None]
        if new_profiles:
            if resolver is None:
                raise RuntimeExecutionError("preflight", "window task author selectors require a resolver")
            value = resolver()
            if not isinstance(value, Mapping) or set(value) != {"author_profiles"} or not isinstance(value.get("author_profiles"), list):
                raise RuntimeExecutionError("schema_error", "resolved author profiles must be a safe object")
            expected = {str(profile["profile_id"]): profile for profile in new_profiles}
            returned_ids: set[str] = set()
            for profile in value["author_profiles"]:
                if not isinstance(profile, Mapping) or set(profile) != {"profile_id", "requested_author", "resolution_status", "author_id", "author_display", "author_handle", "enabled"}:
                    raise RuntimeExecutionError("schema_error", "resolved author profile is invalid")
                profile_id = profile.get("profile_id")
                author_id = profile.get("author_id")
                display = profile.get("author_display")
                handle = profile.get("author_handle")
                if not isinstance(profile_id, str) or profile_id not in expected or profile_id in returned_ids:
                    raise RuntimeExecutionError("schema_error", "resolved author profile is outside its task snapshot")
                if profile.get("requested_author") != expected[profile_id]["requested_author"] or profile.get("resolution_status") != "resolved":
                    raise RuntimeExecutionError("schema_error", "resolved author profile does not match its selector")
                if not isinstance(author_id, str) or not author_id or not isinstance(display, str) or not display or profile.get("enabled") is not True:
                    raise RuntimeExecutionError("schema_error", "resolved author profile is invalid")
                if handle is not None and not isinstance(handle, str):
                    raise RuntimeExecutionError("schema_error", "resolved author profile is invalid")
                returned_ids.add(profile_id)
                resolved.append(profile)

        profiles_by_author: dict[str, str] = {}
        for profile in resolved:
            author_id = profile.get("author_id")
            display = profile.get("author_display")
            if not isinstance(author_id, str) or not author_id or not isinstance(display, str) or not display:
                raise RuntimeExecutionError("schema_error", "resolved author profile is invalid")
            if author_id in profiles_by_author:
                raise RuntimeExecutionError("schema_error", "resolved author profiles are duplicated")
            profiles_by_author[author_id] = display
        return profiles_by_author

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

    def _structured_runs_v1_1(
        self,
        claim: Mapping[str, Any],
        messages: list[CanonicalMessage],
        author_profiles: Mapping[str, str],
    ) -> tuple[list[dict[str, Any]], int, int]:
        """Extract message-backed fact units without crossing Shanghai dates."""

        by_day: dict[str, list[CanonicalMessage]] = {}
        for message in messages:
            by_day.setdefault(_shanghai_natural_date(message.occurred_at), []).append(message)

        runs: list[dict[str, Any]] = []
        retries = 0
        elapsed_ms = 0
        chunk_index = 0
        for natural_date in sorted(by_day):
            day_messages = by_day[natural_date]
            for index in range(0, len(day_messages), 100):
                chunk_index += 1
                chunk = tuple(day_messages[index : index + 100])
                message_ids = [message.external_message_id for message in chunk]
                media_ids = {message.external_message_id for message in chunk if message.attachments}
                identities = tuple((message.external_message_id, message.author_id, message.author_name) for message in chunk)
                context = ProviderContext(
                    chunk_id=f"{claim['task_id']}-{claim['attempt']}-v1-1-chunk-{chunk_index}",
                    prompt_version=self.config.parameter_version,
                    prompt_text=self._v1_1_chunk_prompt_for(chunk),
                    input_message_ids=frozenset(message_ids),
                    unparsed_media_message_ids=frozenset(media_ids),
                    operation="v1_1_chunk",
                    input_message_authors=identities,
                    configured_author_profiles=tuple(sorted(author_profiles.items())),
                )
                response = self.retry_policy.execute(self.provider, chunk, context)
                retries += max(0, response.attempt - 1)
                elapsed_ms += response.elapsed_ms
                if response.status != "success" or response.parsed_output is None:
                    failure = response.failure_class or response.error_code or "provider_failure"
                    raise RuntimeExecutionError(str(failure), "Codex CLI did not produce valid V1.1 fact units")
                try:
                    output = validate_v1_1_chunk_output(
                        response.parsed_output,
                        {message_id: (author_id, author_display) for message_id, author_id, author_display in identities},
                        media_ids,
                    )
                except SchemaError as exc:
                    raise RuntimeExecutionError("schema_error", "V1.1 chunk output failed evidence validation") from exc
                runs.append({
                    "chunk_key": context.chunk_id,
                    "provider": response.provider,
                    "parameter_version": self.config.parameter_version,
                    "input_message_ids": message_ids,
                    "media_source_message_ids": sorted(media_ids),
                    "output": output,
                })
        return runs, retries, elapsed_ms

    def _v1_1_daily_outputs(
        self,
        claim: Mapping[str, Any],
        messages: list[CanonicalMessage],
        runs: list[dict[str, Any]],
        author_profiles: Mapping[str, str],
        end_at: datetime,
        daily_fact_context: Mapping[str, Any],
    ) -> tuple[dict[str, dict[str, Any]], int, int]:
        """Generate one V1.1 daily output from validated fact units per day."""

        if not messages:
            return {}, 0, 0
        context_catalog, prior_batches = _parse_daily_fact_context(daily_fact_context)
        by_day: dict[str, list[CanonicalMessage]] = {}
        for message in messages:
            by_day.setdefault(_shanghai_natural_date(message.occurred_at), []).append(message)
        outputs: dict[str, dict[str, Any]] = {}
        retries = 0
        elapsed_ms = 0
        as_of = _instant_text(end_at)
        for natural_date in sorted(by_day):
            day_messages = by_day[natural_date]
            day_ids = {message.external_message_id for message in day_messages}
            catalog = {
                message_id: (author_id, author_display)
                for message_id, author_id, author_display in context_catalog.get(natural_date, ())
            }
            for message in day_messages:
                identity = (message.author_id, message.author_name)
                existing = catalog.get(message.external_message_id)
                if existing is not None and existing != identity:
                    raise RuntimeExecutionError("schema_error", "daily fact context conflicts with current message identity")
                catalog[message.external_message_id] = identity
            identities = tuple((message_id, author_id, author_display) for message_id, (author_id, author_display) in sorted(catalog.items()))
            facts: list[dict[str, Any]] = []
            for run in runs:
                if set(run["input_message_ids"]) <= day_ids:
                    facts.extend(run["output"]["facts"])
            media_ids = {message.external_message_id for message in day_messages if message.attachments}
            for prior in prior_batches.get(natural_date, ()):
                facts.extend(prior["facts"])
                media_ids.update(prior["unparsed_media_message_ids"])
            context = ProviderContext(
                chunk_id=f"{claim['task_id']}-{claim['attempt']}-v1-1-daily-{natural_date}",
                prompt_version=self.config.parameter_version,
                prompt_text=self._v1_1_daily_prompt_for(
                    natural_date,
                    as_of,
                    identities,
                    author_profiles,
                    facts,
                    media_ids,
                ),
                input_message_ids=frozenset(day_ids),
                unparsed_media_message_ids=frozenset(media_ids),
                operation="v1_1_daily",
                input_message_authors=identities,
                configured_author_profiles=tuple(sorted(author_profiles.items())),
                expected_natural_date=natural_date,
                expected_as_of=as_of,
            )
            response = self.retry_policy.execute(self.provider, tuple(facts), context)
            retries += max(0, response.attempt - 1)
            elapsed_ms += response.elapsed_ms
            if response.status != "success" or response.parsed_output is None:
                failure = response.failure_class or response.error_code or "provider_failure"
                raise RuntimeExecutionError(str(failure), "Codex CLI did not produce a valid V1.1 daily summary")
            try:
                outputs[natural_date] = validate_v1_1_daily_output(
                    response.parsed_output,
                    {message_id: (author_id, author_display) for message_id, author_id, author_display in identities},
                    author_profiles,
                    fact_units=facts,
                    expected_natural_date=natural_date,
                    expected_as_of=as_of,
                    unparsed_media_ids=media_ids,
                )
            except SchemaError as exc:
                raise RuntimeExecutionError("schema_error", "V1.1 daily output failed evidence validation") from exc
        return outputs, retries, elapsed_ms

    @staticmethod
    def _load_daily_fact_context(
        loader: Callable[[], Mapping[str, Any]] | None,
    ) -> Mapping[str, Any]:
        if loader is None:
            return {"message_catalog": [], "prior_batches": []}
        value = loader()
        if not isinstance(value, Mapping):
            raise RuntimeExecutionError("schema_error", "daily fact context must be an object")
        return value

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

    def _v1_1_chunk_prompt_for(self, chunk: Iterable[CanonicalMessage]) -> str:
        return f"{self.v1_1_chunk_template}\n\n本地私有补充说明：\n{self.prompt_template}\n\n输入消息（仅本地 Codex CLI 可见）：\n{json.dumps(self._prompt_messages(chunk), ensure_ascii=False)}"

    def _v1_1_daily_prompt_for(
        self,
        natural_date: str,
        as_of: str,
        identities: tuple[tuple[str, str, str], ...],
        author_profiles: Mapping[str, str],
        facts: list[dict[str, Any]],
        media_ids: set[str],
    ) -> str:
        payload = {
            "natural_date": natural_date,
            "as_of": as_of,
            "configured_author_profiles": [
                {"author_id": author_id, "author_display": display}
                for author_id, display in sorted(author_profiles.items())
            ],
            "message_identity_catalog": [
                {"external_message_id": message_id, "author_id": author_id, "author_display": display}
                for message_id, author_id, display in identities
            ],
            "fact_units": facts,
            "unparsed_media_message_ids": sorted(media_ids),
        }
        return f"{self.v1_1_daily_template}\n\n本地私有补充说明：\n{self.prompt_template}\n\n已验证输入（不含原始正文）：\n{json.dumps(payload, ensure_ascii=False)}"

    @staticmethod
    def _prompt_messages(chunk: Iterable[CanonicalMessage]) -> list[dict[str, Any]]:
        return [
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


class XWindowedRuntime:
    """Execute one X window with page-level durability and immutable analysis.

    The adapter supplies only a bounded, logged-in OpenCLI read.  This runtime
    owns the range boundary, overlap, local evidence, per-post model calls and
    the exact payload that the control plane may atomically complete.
    """

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
        if config.source_type != "x":
            raise ValueError("X runtime requires an X source config")
        if not prompt_template.strip():
            raise ValueError("prompt_template must be non-empty")
        self.config = config
        self.connector = connector
        self.evidence = evidence
        self.canonicalizer = canonicalizer
        self.provider = provider
        self.prompt_template = prompt_template
        self.chunk_template = _read_public_prompt("v2_x_chunk.md")
        self.window_template = _read_public_prompt("v2_x_window.md")
        self.retry_policy = retry_policy or RetryPolicy(max_attempts=3, timeout_seconds=240)
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def execute(self, claim: dict[str, Any]) -> dict[str, Any]:
        scope = claim.get("collection_scope")
        if not isinstance(scope, Mapping) or scope.get("mode") != "window":
            raise RuntimeExecutionError("preflight", "X only supports a bounded window task")
        return self.execute_windowed(claim)

    def execute_windowed(
        self,
        claim: dict[str, Any],
        *,
        on_capture_page: Callable[[dict[str, Any]], None] | None = None,
        load_daily_fact_context: Callable[[], Mapping[str, Any]] | None = None,
        resolve_author_profiles: Callable[[], Mapping[str, Any]] | None = None,
    ) -> dict[str, Any]:
        del load_daily_fact_context, resolve_author_profiles
        capture_range, source_snapshot = self._validate_claim(claim)
        cursor = capture_range.resume_cursor
        candidate_by_id: dict[str, CanonicalMessage] = {}
        capture_segments: list[dict[str, Any]] = []
        duplicate_count = 0
        boundary: dict[str, str] | None = None
        overlap_start = capture_range.overlap_start_at or capture_range.start_at

        try:
            while boundary is None:
                page = self.connector.fetch_page(self.config, cursor, end_at=capture_range.end_at)
                self._validate_page(page, cursor)
                mapped = self.canonicalizer.map(page)
                page_times = [_required_instant(message.occurred_at, "X post occurred_at") for message in mapped]
                if any(occurred_at > capture_range.end_at for occurred_at in page_times):
                    raise RuntimeExecutionError("opencli_contract", "X page contains a post after its fixed end_at")
                if any(message.author_id != source_snapshot["account_id"] for message in mapped):
                    raise RuntimeExecutionError("opencli_contract", "X page author does not match the task source snapshot")
                self.evidence.persist_raw(page)
                local_counts = self.evidence.persist_canonical(mapped)
                duplicate_count += int(local_counts.get("duplicate_count", 0))

                page_execution = self._page_execution(claim, page, mapped, page_times, cursor)
                if on_capture_page is None:
                    capture_segments.append(page_execution["capture_segment"])
                else:
                    on_capture_page(page_execution)

                for message, occurred_at in zip(mapped, page_times, strict=True):
                    if not (capture_range.start_at < occurred_at <= capture_range.end_at):
                        continue
                    if message.external_message_id in candidate_by_id:
                        duplicate_count += 1
                        continue
                    candidate_by_id[message.external_message_id] = message

                if not mapped:
                    boundary = {"kind": "history_exhausted", "observed_at": _instant_text(self.clock())}
                elif min(page_times) <= overlap_start:
                    boundary = {"kind": "oldest_at_or_before_start", "observed_at": _instant_text(min(page_times))}
                elif page.cursor_after is None:
                    if page.telemetry.get("history_exhausted") is not True:
                        raise RuntimeExecutionError("opencli_contract", "X collection cannot prove its lower boundary")
                    boundary = {"kind": "history_exhausted", "observed_at": _instant_text(min(page_times))}
                else:
                    cursor = page.cursor_after
        except ConnectorError as exc:
            raise RuntimeExecutionError(str(exc.code), "X collection failed") from exc
        except RuntimeExecutionError:
            raise
        except (ValueError, SchemaError) as exc:
            raise RuntimeExecutionError("schema_error", "X page or model output is invalid") from exc
        except Exception as exc:
            raise RuntimeExecutionError("persistence_failure", "X local evidence persistence failed") from exc

        messages = sorted(candidate_by_id.values(), key=lambda item: (_required_instant(item.occurred_at, "X post occurred_at"), item.external_message_id))
        analyses, retries, elapsed_ms = self._post_analyses(claim, messages)
        segment, window_retries, window_elapsed = self._window_segment(claim, capture_range, messages, analyses)
        completion = {
            "contract_version": "v0",
            "task_id": str(claim["task_id"]),
            "attempt": int(claim["attempt"]),
            "range_complete": True,
            "capture_range": capture_range.capture_range,
            "boundary": boundary,
            "summary_batch_ids": [],
            "daily_summary_ids": [],
            "x_post_analyses": analyses,
            "x_daily_segments": [] if segment is None else [segment],
            "no_new_data": not messages,
        }
        return {
            "persistence": {
                "contract_version": "v0", "task_id": str(claim["task_id"]), "attempt": int(claim["attempt"]),
                "source_id": self.config.source_id, "raw_messages": [], "canonical_messages": [], "structured_runs": [],
            },
            "capture_segments": capture_segments,
            "range_completion": completion,
            "telemetry": {"elapsed_ms": elapsed_ms + window_elapsed, "retry_count": retries + window_retries, "duplicate_count": duplicate_count},
        }

    def _validate_claim(self, claim: Mapping[str, Any]) -> tuple[WindowedCaptureRange, dict[str, str]]:
        if claim.get("task_type") != "x_sync" or claim.get("source_id") != self.config.source_id:
            raise RuntimeExecutionError("unauthorized", "task does not name this local X source")
        if claim.get("parameter_version") != self.config.parameter_version:
            raise RuntimeExecutionError("preflight", "task parameter version does not match local X config")
        try:
            capture_range = WindowedCaptureRange.from_claim(claim)
            if capture_range.capture_range.get("mode") == "window" and capture_range.overlap_start_at is None:
                raise ValueError("X window requires overlap_start_at")
            if capture_range.capture_range.get("trigger") == "scheduled":
                local_time = capture_range.end_at.astimezone(ZoneInfo("Asia/Shanghai")).strftime("%H:%M")
                if local_time not in {"00:00", "08:00", "12:00", "16:00", "20:00"}:
                    raise ValueError("X scheduled window is not an approved cutoff")
            snapshot = claim.get("source_snapshot")
            if not isinstance(snapshot, Mapping) or set(snapshot) != {"source_type", "account_id", "display_name", "parameter_version"}:
                raise ValueError("X source snapshot is invalid")
            normalized = {key: str(snapshot[key]) for key in snapshot}
            if normalized["source_type"] != "x" or any(not value.strip() for value in normalized.values()):
                raise ValueError("X source snapshot is invalid")
            if normalized["parameter_version"] != self.config.parameter_version:
                raise ValueError("X source snapshot parameter version is stale")
        except ValueError as exc:
            raise RuntimeExecutionError("preflight", str(exc)) from exc
        return capture_range, normalized

    def _validate_page(self, page: object, requested_cursor: str | None) -> None:
        if not isinstance(page, RawPage) or page.source_type != "x" or page.source_id != self.config.source_id:
            raise RuntimeExecutionError("opencli_contract", "X collection returned an invalid page")
        if page.cursor_before != requested_cursor or (page.cursor_after is not None and page.cursor_after == requested_cursor):
            raise RuntimeExecutionError("opencli_contract", "X page cursor does not advance")
        if page.telemetry.get("match_state") != "matched_new":
            raise RuntimeExecutionError("opencli_stale", "X page is not a fresh validated response")

    def _page_execution(
        self, claim: Mapping[str, Any], page: RawPage, mapped: tuple[CanonicalMessage, ...], page_times: list[datetime], cursor: str | None,
    ) -> dict[str, Any]:
        segment = AuthorizedDiscordRuntime._capture_segment(page, cursor, page_times)
        return {
            "persistence": {
                "contract_version": "v0", "task_id": str(claim["task_id"]), "attempt": int(claim["attempt"]),
                "source_id": self.config.source_id,
                "raw_messages": [self._raw_message(page, message) for message in mapped],
                "canonical_messages": [self._canonical_message(message) for message in mapped],
                "structured_runs": [], "capture_segment": segment,
                "x_post_contexts": [self._context(message) for message in mapped],
            },
            "capture_segment": {"contract_version": "v0", "task_id": str(claim["task_id"]), "attempt": int(claim["attempt"]), "capture_segment": segment},
        }

    def _post_analyses(self, claim: Mapping[str, Any], messages: list[CanonicalMessage]) -> tuple[list[dict[str, Any]], int, int]:
        analyses: list[dict[str, Any]] = []
        retries = elapsed_ms = 0
        for message in messages:
            context = self._context_for_prompt(message)
            provider_context = ProviderContext(
                chunk_id=f"{claim['task_id']}-{claim['attempt']}-x-post-{message.external_message_id}", prompt_version=self.config.parameter_version,
                prompt_text=self._chunk_prompt(message, context), input_message_ids=frozenset({message.external_message_id}),
                operation="v2_x_chunk", visible_context_post_ids=frozenset({context["id"]}) if context is not None else frozenset(),
            )
            response = self.retry_policy.execute(self.provider, (message,), provider_context)
            retries += max(0, response.attempt - 1)
            elapsed_ms += response.elapsed_ms
            if response.status != "success" or response.parsed_output is None:
                raise RuntimeExecutionError(str(response.failure_class or response.error_code or "provider_failure"), "Codex CLI did not produce an X post analysis")
            try:
                output = parse_v2_x_chunk_output(json.dumps(response.parsed_output, ensure_ascii=False), {message.external_message_id}, set(provider_context.visible_context_post_ids))
            except SchemaError as exc:
                raise RuntimeExecutionError("schema_error", "X post analysis failed evidence validation") from exc
            analysis = output["analyses"][0]
            analyses.append({
                "post_id": message.external_message_id, "analysis_version": 1,
                "blogger_viewpoint": analysis["blogger_viewpoint"], "arguments": analysis["arguments"],
                "quoted_post_viewpoint": analysis["quoted_post_viewpoint"], "uncertainties": analysis["uncertainties"],
                "evidence_post_ids": analysis["evidence_post_ids"], "post_link": analysis["post_link"],
                "analysis_id": f"{message.external_message_id}@1",
            })
        return analyses, retries, elapsed_ms

    def _window_segment(
        self, claim: Mapping[str, Any], capture_range: WindowedCaptureRange, messages: list[CanonicalMessage], analyses: list[dict[str, Any]],
    ) -> tuple[dict[str, Any] | None, int, int]:
        if not analyses:
            return None, 0, 0
        natural_date = _shanghai_natural_date(messages[0].occurred_at)
        if any(_shanghai_natural_date(message.occurred_at) != natural_date for message in messages):
            raise RuntimeExecutionError("schema_error", "X window may not cross a Shanghai date")
        analysis_ids = {str(analysis["analysis_id"]) for analysis in analyses}
        visible_evidence = {message.external_message_id for message in messages}
        for message in messages:
            context = self._context_for_prompt(message)
            if context is not None:
                visible_evidence.add(context["id"])
        provider_context = ProviderContext(
            chunk_id=f"{claim['task_id']}-{claim['attempt']}-x-window", prompt_version=self.config.parameter_version,
            prompt_text=self._window_prompt(claim, capture_range, analyses), input_message_ids=frozenset(analysis_ids), operation="v2_x_window",
        )
        response = self.retry_policy.execute(self.provider, tuple(analyses), provider_context)
        if response.status != "success" or response.parsed_output is None:
            raise RuntimeExecutionError(str(response.failure_class or response.error_code or "provider_failure"), "Codex CLI did not produce an X window viewpoint")
        try:
            output = parse_v2_x_window_output(json.dumps(response.parsed_output, ensure_ascii=False), analysis_ids)
        except SchemaError as exc:
            raise RuntimeExecutionError("schema_error", "X window viewpoint failed analysis validation") from exc
        if output["range_task_id"] != str(claim["task_id"]) or output["natural_date"] != natural_date or not set(output["evidence_post_ids"]) <= visible_evidence:
            raise RuntimeExecutionError("schema_error", "X window viewpoint does not match its immutable evidence")
        return {
            "natural_date": natural_date, "occurred_from_at": _instant_text(min(_required_instant(message.occurred_at, "X post occurred_at") for message in messages)),
            "occurred_through_at": _instant_text(max(_required_instant(message.occurred_at, "X post occurred_at") for message in messages)),
            "window_viewpoints": output["window_viewpoints"], "analysis_ids": output["analysis_ids"],
            "evidence_post_ids": output["evidence_post_ids"], "uncertainties": output["uncertainties"],
        }, max(0, response.attempt - 1), response.elapsed_ms

    def _chunk_prompt(self, message: CanonicalMessage, context: dict[str, str] | None) -> str:
        payload = {"post": self._prompt_post(message), "context_post": context, "context_status": message.metadata["x"]["context_status"]}
        return f"{self.chunk_template}\n\n本地私有补充说明：\n{self.prompt_template}\n\n输入帖子包（仅本地 Codex CLI 可见）：\n{json.dumps(payload, ensure_ascii=False)}"

    def _window_prompt(self, claim: Mapping[str, Any], capture_range: WindowedCaptureRange, analyses: list[dict[str, Any]]) -> str:
        payload = {"range_task_id": str(claim["task_id"]), "natural_date": _shanghai_natural_date(_instant_text(capture_range.end_at)), "occurred_from_at": _instant_text(capture_range.start_at), "occurred_through_at": _instant_text(capture_range.end_at), "post_analyses": analyses}
        return f"{self.window_template}\n\n本地私有补充说明：\n{self.prompt_template}\n\n已验证且待持久化的逐帖分析（仅本地 Codex CLI 可见）：\n{json.dumps(payload, ensure_ascii=False)}"

    @staticmethod
    def _prompt_post(message: CanonicalMessage) -> dict[str, Any]:
        return {"id": message.external_message_id, "author_id": message.author_id, "author_name": message.author_name, "occurred_at": message.occurred_at, "text": message.content, "post_type": message.metadata["x"]["post_type"], "url": message.metadata["x"]["post_url"], "attachments_present": bool(message.attachments)}

    @staticmethod
    def _context_for_prompt(message: CanonicalMessage) -> dict[str, str] | None:
        value = message.metadata.get("x", {}).get("context_post")
        if not isinstance(value, Mapping):
            return None
        required = ("id", "text", "url")
        if not all(isinstance(value.get(key), str) and value[key] for key in required):
            return None
        return {"id": str(value["id"]), "text": str(value["text"]), "url": str(value["url"]), "author_id": str(value.get("author_id") or ""), "author_name": str(value.get("author_name") or "")}

    @staticmethod
    def _context(message: CanonicalMessage) -> dict[str, Any]:
        x = message.metadata["x"]
        return {"external_message_id": message.external_message_id, "post_type": x["post_type"], "post_url": x["post_url"], "quoted_post_id": x["quoted_post_id"], "reply_to_post_id": x["reply_to_post_id"], "reposted_post_id": x["reposted_post_id"], "context_status": x["context_status"], "attachments": x["attachments"]}

    def _raw_message(self, page: RawPage, message: CanonicalMessage) -> dict[str, Any]:
        item = next((value for value in page.messages if str(value.get("id")) == message.external_message_id), {})
        occurred_at = _required_instant(message.occurred_at, "X post occurred_at")
        payload = json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return {"external_message_id": message.external_message_id, "occurred_at": _instant_text(occurred_at), "local_raw_ref": page.raw_payload_ref, "payload_hash": hashlib.sha256(payload).hexdigest(), "retention_expires_at": _instant_text(_one_year_later(occurred_at))}

    @staticmethod
    def _canonical_message(message: CanonicalMessage) -> dict[str, Any]:
        return {"external_message_id": message.external_message_id, "occurred_at": _valid_datetime(message.occurred_at), "author_display": message.author_name or None, "content": message.content, "has_unparsed_media": bool(message.attachments), "metadata": {"author_id": message.author_id, "post_url": message.metadata["x"]["post_url"], "post_type": message.metadata["x"]["post_type"], "unresolved": message.metadata["x"]["context_status"] != "complete"}}


class AuthorizedDiscordRuntimeSet:
    """Route each claim to exactly one owner-configured local source."""

    def __init__(self, runtimes: Mapping[str, Any]) -> None:
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
        load_daily_fact_context: Callable[[], Mapping[str, Any]] | None = None,
        resolve_author_profiles: Callable[[], Mapping[str, Any]] | None = None,
    ) -> dict[str, Any]:
        source_id = claim.get("source_id")
        if not isinstance(source_id, str) or source_id not in self._runtimes:
            raise RuntimeExecutionError("unauthorized", "task source is not configured for this local Worker")
        return self._runtimes[source_id].execute_windowed(
            claim,
            on_capture_page=on_capture_page,
            load_daily_fact_context=load_daily_fact_context,
            resolve_author_profiles=resolve_author_profiles,
        )


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


def build_authorized_x_runtime(
    *,
    config: LocalWorkerConfig,
    evidence_dir: Path,
    prompt_path: Path,
    opencli_executable: str | None = None,
) -> XWindowedRuntime:
    if config.source_type != "x":
        raise ValueError("X runtime builder requires an X config")
    return XWindowedRuntime(
        config=config,
        connector=XActiveAdapter(OpenCLITweetsInvoker(opencli_executable or "opencli")),
        evidence=LocalEvidenceStore(Path(evidence_dir)),
        canonicalizer=Canonicalizer(),
        provider=_codex_provider(evidence_dir),
        prompt_template=Path(prompt_path).read_text(encoding="utf-8"),
    )


def build_authorized_runtime_set(
    *,
    config: LocalWorkerConfigSet,
    evidence_dir: Path,
    prompt_path: Path,
    opencli_contract_path: Path,
    opencli_executable: str | None = None,
) -> AuthorizedDiscordRuntimeSet:
    """Build source-specific runtimes without ever sending an X claim to Discord."""

    runtimes: dict[str, Any] = {}
    for source in config.sources:
        target_evidence_dir = Path(evidence_dir) / source.source_id
        if source.source_type == "discord":
            runtimes[source.source_id] = build_authorized_discord_runtime(
                config=source, evidence_dir=target_evidence_dir, prompt_path=prompt_path,
                opencli_contract_path=opencli_contract_path, opencli_executable=opencli_executable,
            )
        elif source.source_type == "x":
            runtimes[source.source_id] = build_authorized_x_runtime(
                config=source, evidence_dir=target_evidence_dir, prompt_path=prompt_path,
                opencli_executable=opencli_executable,
            )
        else:  # LocalWorkerConfig validates this, kept as a defensive fence.
            raise RuntimeExecutionError("preflight", "unsupported configured source type")
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


def _one_year_later(value: datetime) -> datetime:
    """Match PostgreSQL's ``+ interval '1 year'`` retention semantics."""

    try:
        return value.replace(year=value.year + 1)
    except ValueError:  # Feb 29 becomes Feb 28 in a non-leap following year.
        return value.replace(year=value.year + 1, month=2, day=28)


def _shanghai_natural_date(value: str) -> str:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError) as exc:
        raise RuntimeExecutionError("schema_error", "canonical message occurred_at is invalid") from exc
    if parsed.tzinfo is None:
        raise RuntimeExecutionError("schema_error", "canonical message occurred_at must be timezone-aware")
    return parsed.astimezone(ZoneInfo("Asia/Shanghai")).date().isoformat()


def _read_public_prompt(name: str) -> str:
    path = Path(__file__).resolve().parents[2] / "prompts" / name
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise RuntimeError("V1.1 public prompt template is unavailable") from exc
    if not value:
        raise RuntimeError("V1.1 public prompt template is empty")
    return value


def _parse_daily_fact_context(
    value: Mapping[str, Any],
) -> tuple[dict[str, list[tuple[str, str, str]]], dict[str, list[dict[str, Any]]]]:
    if set(value) != {"message_catalog", "prior_batches"}:
        raise RuntimeExecutionError("schema_error", "daily fact context has unknown fields")
    raw_catalog = value.get("message_catalog")
    raw_batches = value.get("prior_batches")
    if not isinstance(raw_catalog, list) or not isinstance(raw_batches, list):
        raise RuntimeExecutionError("schema_error", "daily fact context collections are invalid")

    catalog_by_day: dict[str, list[tuple[str, str, str]]] = {}
    catalog_by_id: dict[str, tuple[str, str]] = {}
    catalog_day_by_id: dict[str, str] = {}
    for item in raw_catalog:
        if not isinstance(item, Mapping) or set(item) != {
            "external_message_id", "natural_date", "author_id", "author_display", "has_unparsed_media",
        }:
            raise RuntimeExecutionError("schema_error", "daily message catalog entry is invalid")
        message_id = item.get("external_message_id")
        natural_date = item.get("natural_date")
        author_id = item.get("author_id")
        author_display = item.get("author_display")
        if (not isinstance(message_id, str) or not message_id
                or not isinstance(natural_date, str)
                or not isinstance(author_id, str) or not author_id
                or not isinstance(author_display, str) or not author_display
                or not isinstance(item.get("has_unparsed_media"), bool)):
            raise RuntimeExecutionError("schema_error", "daily message catalog identity is invalid")
        try:
            date.fromisoformat(natural_date)
        except ValueError as exc:
            raise RuntimeExecutionError("schema_error", "daily message catalog date is invalid") from exc
        identity = (author_id, author_display)
        if message_id in catalog_by_id and (catalog_by_id[message_id] != identity or catalog_day_by_id[message_id] != natural_date):
            raise RuntimeExecutionError("schema_error", "daily message catalog repeats a conflicting message")
        if message_id not in catalog_by_id:
            catalog_by_id[message_id] = identity
            catalog_day_by_id[message_id] = natural_date
            catalog_by_day.setdefault(natural_date, []).append((message_id, author_id, author_display))

    prior_by_day: dict[str, list[dict[str, Any]]] = {}
    for item in raw_batches:
        if not isinstance(item, Mapping) or set(item) != {
            "natural_date", "facts", "warnings", "unparsed_media_message_ids",
        }:
            raise RuntimeExecutionError("schema_error", "daily prior batch is invalid")
        natural_date = item.get("natural_date")
        if not isinstance(natural_date, str):
            raise RuntimeExecutionError("schema_error", "daily prior batch date is invalid")
        try:
            date.fromisoformat(natural_date)
        except ValueError as exc:
            raise RuntimeExecutionError("schema_error", "daily prior batch date is invalid") from exc
        try:
            parsed = parse_v1_1_chunk_output(json.dumps({
                "schema_version": "v1.1-chunk",
                "facts": item.get("facts"),
                "media_source_message_ids": item.get("unparsed_media_message_ids"),
                "warnings": item.get("warnings"),
            }, ensure_ascii=False))
            validated = validate_v1_1_chunk_output(
                parsed,
                catalog_by_id,
                set(parsed["media_source_message_ids"]),
            )
        except SchemaError as exc:
            raise RuntimeExecutionError("schema_error", "daily prior batch has invalid fact evidence") from exc
        cited_ids = {
            message_id
            for fact in validated["facts"]
            for message_id in fact["source_message_ids"]
        } | set(validated["media_source_message_ids"])
        if any(catalog_day_by_id[message_id] != natural_date for message_id in cited_ids):
            raise RuntimeExecutionError("schema_error", "daily prior batch crosses Shanghai days")
        prior_by_day.setdefault(natural_date, []).append({
            "facts": validated["facts"],
            "unparsed_media_message_ids": list(validated["media_source_message_ids"]),
        })
    return catalog_by_day, prior_by_day
