from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import StrEnum
from typing import Any, Callable

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
        preflight: Callable[[dict[str, Any]], None] | None = None,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self.protocol = protocol
        self.execute = execute or self._not_configured
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
            result = self.execute(claim)
            self.state = WorkerState.REPORTING
            acknowledgement = self.protocol.report_result(result)
            if acknowledgement.get("status") != "succeeded":
                raise LeaseUncertain("control plane did not acknowledge success")
            self.state = WorkerState.IDLE
            return RunOutcome("succeeded", task_id, acknowledgement=acknowledgement)
        except Exception as exc:
            return self._recover(task_id, exc)

    def stop(self) -> None:
        self.state = WorkerState.STOPPED

    @staticmethod
    def _not_configured(_claim: dict[str, Any]) -> dict[str, Any]:
        raise RuntimeError("worker executor is not configured")

    def _recover(self, task_id: str | None, error: Exception) -> RunOutcome:
        self.state = WorkerState.RECOVERING
        return RunOutcome("recovering", task_id, error=type(error).__name__)
