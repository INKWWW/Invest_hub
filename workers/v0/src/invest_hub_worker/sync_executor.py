from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Iterable

from .canonical import CanonicalValidationError, Canonicalizer
from .checkpoint import CheckpointGuard, CheckpointNotAdvanced
from .connectors.base import ConnectorError


@dataclass(frozen=True)
class ExecutionResult:
    status: str
    safe_checkpoint: str | None
    raw_count: int = 0
    canonical_count: int = 0
    duplicate_count: int = 0
    unresolved_count: int = 0
    unparsed_media_count: int = 0
    structured_run_ids: tuple[str, ...] = ()
    failure_class: str | None = None


class SyncExecutor:
    def __init__(
        self,
        *,
        connector: Any,
        evidence: Any,
        canonicalizer: Canonicalizer,
        provider: Callable[[tuple[Any, ...]], dict[str, Any]],
        checkpoint_ack: Callable[[ExecutionResult], str],
    ) -> None:
        self.connector = connector
        self.evidence = evidence
        self.canonicalizer = canonicalizer
        self.provider = provider
        self.checkpoint_ack = checkpoint_ack

    def execute(self, task_claim: dict[str, Any], source: Any) -> ExecutionResult:
        previous = task_claim.get("safe_checkpoint")
        raw_count = canonical_count = duplicate_count = unresolved_count = 0
        all_messages: list[Any] = []
        candidates: list[str | None] = [previous]
        try:
            for page in self.connector.collect(source, previous):
                raw_count += len(page.messages)
                self.evidence.persist_raw(page)
                mapped = self.canonicalizer.map(page)
                persistence = self.evidence.persist_canonical(mapped)
                canonical_count += int(persistence.get("canonical_count", len(mapped)))
                duplicate_count += int(persistence.get("duplicate_count", 0))
                unresolved_count += sum(1 for message in mapped if message.unresolved)
                all_messages.extend(mapped)
                candidates.append(page.cursor_after)
        except ConnectorError as exc:
            return self._failure(previous, exc.code)
        except CanonicalValidationError:
            return self._failure(previous, "schema_error")
        except Exception:
            return self._failure(previous, "persistence_failure")

        try:
            provider_result = self.provider(tuple(all_messages))
        except Exception:
            return self._failure(previous, "provider_failure")

        candidate = candidates[-1]
        result = ExecutionResult(
            status="succeeded",
            safe_checkpoint=candidate,
            raw_count=raw_count,
            canonical_count=canonical_count,
            duplicate_count=duplicate_count,
            unresolved_count=unresolved_count,
            structured_run_ids=tuple(str(value) for value in provider_result.get("structured_run_ids", [])),
        )
        try:
            ack = self.checkpoint_ack(result)
            CheckpointGuard(previous, tuple(candidates)).commit(candidate, persistence_ack=ack)
        except CheckpointNotAdvanced:
            return self._failure(previous, "persistence_failure")
        except Exception:
            return self._failure(previous, "persistence_failure")
        return result

    @staticmethod
    def _failure(previous: str | None, failure_class: str) -> ExecutionResult:
        return ExecutionResult(status="retryable_failed", safe_checkpoint=previous, failure_class=failure_class)
