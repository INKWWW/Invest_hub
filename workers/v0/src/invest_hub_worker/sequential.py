from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Mapping, Protocol

from .config import LocalWorkerConfigSet
from .worker import RunOutcome, Worker


@dataclass(frozen=True)
class FrozenXSource:
    source_id: str
    display_name: str
    resolution_status: str
    account_id: str | None = None


@dataclass(frozen=True)
class SequentialSourceOutcome:
    source_id: str
    status: str
    task_id: str | None = None
    error: str | None = None


@dataclass(frozen=True)
class SequentialRunOutcome:
    status: str
    run_id: str | None
    cutoff_at: str
    sources: tuple[SequentialSourceOutcome, ...] = ()
    judgement_id: str | None = None
    error: str | None = None
    idempotent: bool = False


class SequentialRunProtocol(Protocol):
    def begin_x_demo_fixed_window_run(self, cutoff_at: str) -> Mapping[str, Any]: ...
    def create_x_demo_fixed_window_task_for_run(self, run_id: str, source_id: str, cutoff_at: str, account_id: str) -> Mapping[str, Any]: ...
    def create_x_demo_fixed_window_task(self, source_id: str, cutoff_at: str, account_id: str) -> Mapping[str, Any]: ...
    def attach_x_demo_fixed_window_task(self, run_id: str, source_id: str, task_id: str) -> Mapping[str, Any]: ...
    def mark_x_demo_fixed_window_source_failed(self, run_id: str, source_id: str, reason: str) -> Mapping[str, Any]: ...
    def settle_x_demo_fixed_window_run(self, run_id: str) -> Mapping[str, Any]: ...
    def terminalize_x_demo_fixed_window_judgement(self, demo_run_id: str, judgement_run_id: str) -> Mapping[str, Any]: ...


def _sources(value: object) -> tuple[FrozenXSource, ...]:
    if not isinstance(value, list):
        raise ValueError("invalid_x_demo_fixed_window_snapshot")
    result: list[FrozenXSource] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, Mapping):
            raise ValueError("invalid_x_demo_fixed_window_snapshot")
        source_id = item.get("source_id")
        display_name = item.get("display_name")
        resolution_status = item.get("resolution_status")
        account_id = item.get("account_id")
        if not isinstance(source_id, str) or not source_id or source_id in seen:
            raise ValueError("invalid_x_demo_fixed_window_snapshot")
        if not isinstance(display_name, str) or not display_name:
            raise ValueError("invalid_x_demo_fixed_window_snapshot")
        if resolution_status not in {"pending", "resolved", "identity_failed", "unavailable"}:
            raise ValueError("invalid_x_demo_fixed_window_snapshot")
        if account_id is not None and (not isinstance(account_id, str) or not account_id):
            raise ValueError("invalid_x_demo_fixed_window_snapshot")
        seen.add(source_id)
        result.append(FrozenXSource(source_id, display_name, str(resolution_status), account_id))
    return tuple(sorted(result, key=lambda source: source.source_id))


def _source_outcome(source: FrozenXSource, outcome: RunOutcome) -> SequentialSourceOutcome:
    if outcome.status == "succeeded":
        acknowledgement = outcome.acknowledgement or {}
        if acknowledgement.get("no_new_data") is True or acknowledgement.get("source_status") == "no_new_information":
            return SequentialSourceOutcome(source.source_id, "no_new", outcome.task_id)
        return SequentialSourceOutcome(source.source_id, "included", outcome.task_id)
    return SequentialSourceOutcome(source.source_id, "excluded", outcome.task_id, outcome.error or outcome.status)


def run_sequential_x_fixed_window(
    worker: Worker,
    _config: LocalWorkerConfigSet,
    cutoff_at: str,
    judgement_execute: Callable[[dict[str, object], dict[str, object]], dict[str, object]] | None = None,
) -> SequentialRunOutcome:
    """Drain one frozen X source snapshot in stable order using Ticket 01 seams."""

    protocol = worker.protocol
    started = protocol.begin_x_demo_fixed_window_run(cutoff_at)
    run_id = started.get("run_id")
    if not isinstance(run_id, str) or not run_id:
        raise ValueError("invalid_x_demo_fixed_window_run")
    if started.get("idempotent") is True or started.get("status") in {"complete", "partial", "no_new", "failed"}:
        return SequentialRunOutcome(
            str(started.get("status") or "existing"), run_id, cutoff_at,
            idempotent=started.get("idempotent") is True,
        )

    frozen = _sources(started.get("sources"))
    results: list[SequentialSourceOutcome] = []
    for source in frozen:
        account_id = source.account_id
        if source.resolution_status != "resolved" or not account_id:
            raise ValueError("x_demo_sources_not_ready")

        create_for_run = getattr(protocol, "create_x_demo_fixed_window_task_for_run", None)
        if callable(create_for_run):
            task = create_for_run(run_id, source.source_id, cutoff_at, account_id)
        else:
            task = protocol.create_x_demo_fixed_window_task(source.source_id, cutoff_at, account_id)
        task_id = task.get("id")
        if not isinstance(task_id, str) or not task_id or task.get("source_id") != source.source_id:
            raise ValueError("invalid_x_demo_fixed_window_task")
        protocol.attach_x_demo_fixed_window_task(run_id, source.source_id, task_id)

        outcome = worker.run_once_for_task(task_id, x_external_max_attempts=2)
        result = _source_outcome(source, outcome)
        if result.status == "excluded":
            protocol.mark_x_demo_fixed_window_source_failed(run_id, source.source_id, result.error or "source_failed")
        results.append(result)

    settled = protocol.settle_x_demo_fixed_window_run(run_id)
    status = settled.get("status")
    if status == "judgement_pending" and judgement_execute is not None:
        judgement = worker.run_x_daily_judgement_for_run(run_id, judgement_execute)
        if judgement.status != "succeeded":
            judgement = worker.run_x_daily_judgement_for_run(run_id, judgement_execute)
        if judgement.status != "succeeded":
            if not isinstance(judgement.task_id, str) or not judgement.task_id or judgement.task_id == run_id:
                return SequentialRunOutcome("failed", run_id, cutoff_at, tuple(results), judgement.task_id, "invalid_judgement_identity")
            protocol.terminalize_x_demo_fixed_window_judgement(run_id, judgement.task_id)
            return SequentialRunOutcome("failed", run_id, cutoff_at, tuple(results), judgement.task_id, judgement.error or "judgement_failed")
        return SequentialRunOutcome(
            str(settled.get("coverage_status") or "partial"), run_id, cutoff_at, tuple(results), judgement.task_id,
        )
    if status not in {"complete", "partial", "no_new", "failed"}:
        status = "failed"
    if not frozen and status == "no_new":
        return SequentialRunOutcome("failed", run_id, cutoff_at, tuple(results), error="no_available_input")
    return SequentialRunOutcome(str(status), run_id, cutoff_at, tuple(results), error=settled.get("error"))
