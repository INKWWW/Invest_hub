from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import StrEnum
from typing import Any, Callable, Mapping

from .errors import LeaseUncertain
from .lease import LeaseState


class WorkerState(StrEnum):
    IDLE = "idle"
    CLAIMED = "claimed"
    EXECUTING = "executing"
    REPORTING = "reporting"
    RECOVERING = "recovering"
    STOPPED = "stopped"


@dataclass(frozen=True)
class RunOutcome:
    status: str
    task_id: str | None = None
    error: str | None = None
    acknowledgement: dict[str, Any] | None = None


class Worker:
    def __init__(
        self,
        protocol: Any,
        *,
        execute: Callable[[dict[str, Any]], dict[str, Any]] | None = None,
        execute_windowed: Callable[..., dict[str, Any]] | None = None,
        preflight: Callable[[dict[str, Any]], None] | None = None,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self.protocol = protocol
        self.execute = execute or self._not_configured
        self.execute_windowed = execute_windowed
        self.preflight = preflight or (lambda _claim: None)
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self.state = WorkerState.IDLE

    def run_once(self) -> RunOutcome:
        try:
            self.protocol.heartbeat("idle", ["discord_sync"], self.clock().isoformat())
        except Exception as exc:
            return self._recover(None, exc)

        try:
            claim = self.protocol.claim()
        except Exception as exc:
            return self._recover(None, exc)
        if claim is None:
            self.state = WorkerState.IDLE
            return RunOutcome("no_task")

        task_id = str(claim.get("task_id"))
        self.state = WorkerState.CLAIMED
        try:
            lease = LeaseState(task_id, int(claim["attempt"]), str(claim["lease_expires_at"]))
            if lease.is_expired(self.clock()):
                raise LeaseUncertain("lease expired before execution")
            self.preflight(claim)
            self.state = WorkerState.EXECUTING
            execution = self._execute_claim(claim)
            window_acknowledgement = self._complete_windowed_execution(execution)
            if window_acknowledgement is not None:
                self.state = WorkerState.IDLE
                return RunOutcome("succeeded", task_id, acknowledgement=window_acknowledgement)
            result = self._persist_before_result(execution)
            self.state = WorkerState.REPORTING
            acknowledgement = self.protocol.report_result(result)
            if acknowledgement.get("status") != "succeeded":
                raise LeaseUncertain("control plane did not acknowledge success")
            self.state = WorkerState.IDLE
            return RunOutcome("succeeded", task_id, acknowledgement=acknowledgement)
        except Exception as exc:
            self._report_failure(claim, exc)
            return self._recover(task_id, exc)

    def schedule_tick(self) -> dict[str, Any]:
        """Ask the control plane to enqueue every due source window."""

        return self.protocol.schedule_tick()

    def stop(self) -> None:
        self.state = WorkerState.STOPPED

    @staticmethod
    def _not_configured(_claim: dict[str, Any]) -> dict[str, Any]:
        raise RuntimeError("worker executor is not configured")

    def _execute_claim(self, claim: dict[str, Any]) -> dict[str, Any]:
        scope = claim.get("collection_scope")
        if not isinstance(scope, Mapping) or scope.get("mode") != "window":
            return self.execute(claim)
        if self.execute_windowed is None:
            raise RuntimeError("window task requires a streaming executor")
        daily_context = getattr(self.protocol, "get_daily_fact_context", None)
        if not callable(daily_context):
            return self.execute_windowed(claim, on_capture_page=self._persist_windowed_capture_page)
        task_id = claim.get("task_id")
        attempt = claim.get("attempt")
        if not isinstance(task_id, str) or not task_id or isinstance(attempt, bool) or not isinstance(attempt, int) or attempt < 1:
            raise RuntimeError("invalid window task identity")
        return self.execute_windowed(
            claim,
            on_capture_page=self._persist_windowed_capture_page,
            load_daily_fact_context=lambda: daily_context(task_id, attempt),
        )

    def _persist_windowed_capture_page(self, page_execution: dict[str, Any]) -> None:
        persistence = page_execution.get("persistence")
        segment_payload = page_execution.get("capture_segment")
        if not isinstance(persistence, Mapping) or not isinstance(segment_payload, Mapping):
            raise RuntimeError("invalid window page execution")
        segment = persistence.get("capture_segment")
        if not isinstance(segment, Mapping) or segment_payload.get("capture_segment") != segment:
            raise RuntimeError("window page segment does not match its persistence")
        acknowledgement = self.protocol.persist(dict(persistence))
        if acknowledgement.get("persisted") is not True:
            raise LeaseUncertain("control plane did not acknowledge window page persistence")
        expected_cursor = segment.get("next_cursor")
        if acknowledgement.get("resume_cursor") != expected_cursor:
            raise LeaseUncertain("control plane acknowledged an unexpected window resume cursor")
        task_id = persistence.get("task_id")
        attempt = persistence.get("attempt")
        if not isinstance(task_id, str) or not task_id or isinstance(attempt, bool) or not isinstance(attempt, int) or attempt < 1:
            raise RuntimeError("invalid window page identity")
        self.protocol.renew(task_id, attempt)

    def _persist_before_result(self, execution: dict[str, Any]) -> dict[str, Any]:
        """Persist a complete execution before allowing a success result.

        Legacy deterministic executors return a task-result directly.  The
        authorized runtime returns ``{persistence, result}``, which makes the
        remote persistence acknowledgement an explicit state transition.
        """

        persistence = execution.get("persistence")
        nested_result = execution.get("result")
        if persistence is None and nested_result is None:
            return execution
        if not isinstance(persistence, Mapping) or not isinstance(nested_result, Mapping):
            raise RuntimeError("invalid execution bundle")

        acknowledgement = self.protocol.persist(dict(persistence))
        if acknowledgement.get("persisted") is not True:
            raise LeaseUncertain("control plane did not acknowledge persistence")
        run_ids = acknowledgement.get("structured_run_ids")
        if not isinstance(run_ids, list) or not all(isinstance(run_id, str) and run_id for run_id in run_ids):
            raise LeaseUncertain("control plane returned invalid structured run IDs")
        summary_batch_ids = acknowledgement.get("summary_batch_ids")
        daily_summary_ids = acknowledgement.get("daily_summary_ids")
        if not isinstance(summary_batch_ids, list) or not all(isinstance(summary_id, str) and summary_id for summary_id in summary_batch_ids):
            raise LeaseUncertain("control plane returned invalid summary batch IDs")
        if not isinstance(daily_summary_ids, list) or not all(isinstance(summary_id, str) and summary_id for summary_id in daily_summary_ids):
            raise LeaseUncertain("control plane returned invalid daily summary IDs")
        result = dict(nested_result)
        result["structured_run_ids"] = run_ids
        result["summary_batch_ids"] = summary_batch_ids
        result["daily_summary_ids"] = daily_summary_ids
        return result

    def _complete_windowed_execution(self, execution: dict[str, Any]) -> dict[str, Any] | None:
        """Complete a V1.1 window without invoking the legacy checkpoint result API."""

        completion = execution.get("range_completion")
        if completion is None:
            return None
        persistence = execution.get("persistence")
        segments = execution.get("capture_segments", [])
        if not isinstance(completion, Mapping) or not isinstance(persistence, Mapping) or not isinstance(segments, list):
            raise RuntimeError("invalid windowed execution bundle")

        acknowledgement = self.protocol.persist(dict(persistence))
        if acknowledgement.get("persisted") is not True:
            raise LeaseUncertain("control plane did not acknowledge window persistence")
        summary_batch_ids = acknowledgement.get("summary_batch_ids")
        daily_summary_ids = acknowledgement.get("daily_summary_ids")
        if not isinstance(summary_batch_ids, list) or not all(isinstance(value, str) and value for value in summary_batch_ids):
            raise LeaseUncertain("control plane returned invalid window summary batch IDs")
        if not isinstance(daily_summary_ids, list) or not all(isinstance(value, str) and value for value in daily_summary_ids):
            raise LeaseUncertain("control plane returned invalid window daily summary IDs")

        for segment in segments:
            if not isinstance(segment, Mapping):
                raise RuntimeError("invalid window capture segment")
            self.protocol.record_capture_segment(dict(segment))

        completion_payload = dict(completion)
        if completion_payload.get("summary_batch_ids") != summary_batch_ids or completion_payload.get("daily_summary_ids") != daily_summary_ids:
            raise LeaseUncertain("window completion receipts do not match persisted evidence")
        final_acknowledgement = self.protocol.complete_capture_range(completion_payload)
        if final_acknowledgement.get("status") != "succeeded":
            raise LeaseUncertain("control plane did not acknowledge window completion")
        return final_acknowledgement

    def _report_failure(self, claim: Mapping[str, Any], error: Exception) -> None:
        failure_class = str(getattr(error, "failure_class", "unknown"))
        allowed = {
            "timeout", "provider_failure", "empty_response", "invalid_json", "schema_error",
            "persistence_failure", "lease_expired", "network_error", "preflight", "unauthorized",
            "opencli_contract", "opencli_missing", "opencli_stale", "unknown",
        }
        if failure_class not in allowed:
            failure_class = "unknown"
        try:
            self.protocol.report_failure(
                {
                    "contract_version": "v0",
                    "task_id": str(claim["task_id"]),
                    "attempt": int(claim["attempt"]),
                    "status": "retryable_failed",
                    "failure_class": failure_class,
                    "safe_checkpoint": claim.get("safe_checkpoint"),
                    "retryable": True,
                }
            )
        except Exception:
            # A failed failure report must not be mistaken for a successful
            # task completion; the lease will remain conservative for retry.
            return

    def _recover(self, task_id: str | None, error: Exception) -> RunOutcome:
        self.state = WorkerState.RECOVERING
        return RunOutcome("recovering", task_id, error=type(error).__name__)
