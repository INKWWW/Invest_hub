from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping

from .canonical import CanonicalMessage, Canonicalizer
from .config import LocalWorkerConfig
from .connectors.base import ConnectorError, RawPage
from .connectors.discord_active_adapter import DiscordActiveAdapter, normalize_channel_url
from .evidence import LocalEvidenceStore
from .providers.base import Provider, ProviderContext
from .retry import RetryPolicy


class RuntimeExecutionError(RuntimeError):
    def __init__(self, failure_class: str, message: str) -> None:
        super().__init__(message)
        self.failure_class = failure_class


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
    ) -> Mapping[str, object]:
        del cache_buster
        try:
            payload = self._invoker.fetch_page(
                channel_url=channel_url,
                profile_path=Path(profile_ref),
                cursor=cursor,
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
        self._validate_claim(claim)
        raw_messages: list[dict[str, Any]] = []
        canonical_by_id: dict[str, CanonicalMessage] = {}
        checkpoints: list[str | None] = [claim.get("safe_checkpoint")]
        duplicate_count = 0

        try:
            for page in self.connector.collect(self.config, claim.get("safe_checkpoint")):
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
                checkpoints.append(page.cursor_after)
        except ConnectorError as exc:
            raise RuntimeExecutionError(str(exc.code), "Discord collection failed") from exc
        except Exception as exc:
            raise RuntimeExecutionError("persistence_failure", "local evidence persistence failed") from exc

        canonical_messages = list(canonical_by_id.values())
        structured_runs, retry_count, elapsed_ms = self._structured_runs(claim, canonical_messages)
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

    def _validate_claim(self, claim: Mapping[str, Any]) -> None:
        if claim.get("source_id") != self.config.source_id:
            raise RuntimeExecutionError("unauthorized", "task source does not match the local authorized source")
        if claim.get("parameter_version") != self.config.parameter_version:
            raise RuntimeExecutionError("preflight", "task parameter version does not match local worker config")

    def _structured_runs(
        self,
        claim: Mapping[str, Any],
        messages: list[CanonicalMessage],
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
