from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from invest_hub_worker.worker import Worker


class FixtureProviderFailure(RuntimeError):
    failure_class = "provider_failure"


class V1FixtureControlPlane:
    """Public deterministic model of the V1 scheduling and reader boundaries."""

    def __init__(self) -> None:
        self.sources: dict[str, dict[str, Any]] = {}
        self.tasks: dict[str, dict[str, Any]] = {}
        self.windows: dict[tuple[str, str], str] = {}
        self.checkpoints: dict[str, str | None] = {}
        self.daily_summaries: dict[str, dict[str, Any]] = {}
        self._task_number = 0

    def configure_source(self, source_key: str, *, worker_id: str, target_authors: tuple[str, ...] = ()) -> None:
        self.sources[source_key] = {
            "source_key": source_key,
            "worker_id": worker_id,
            "target_authors": tuple(sorted(set(target_authors))),
        }
        self.checkpoints.setdefault(source_key, None)

    def schedule_tick(self, worker_id: str, window_key: str) -> list[dict[str, Any]]:
        scheduled: list[dict[str, Any]] = []
        for source_key, source in sorted(self.sources.items()):
            if source["worker_id"] != worker_id:
                continue
            key = (source_key, window_key)
            task_id = self.windows.get(key)
            if task_id is None:
                self._task_number += 1
                task_id = f"scheduled-task-{self._task_number}"
                self.windows[key] = task_id
                self.tasks[task_id] = {
                    "id": task_id,
                    "source_key": source_key,
                    "worker_id": worker_id,
                    "status": "queued",
                    "attempt": 0,
                    "safe_checkpoint": self.checkpoints[source_key],
                    "rule_snapshot": {"version": 1, "target_author_ids": list(source["target_authors"])},
                    "collection_scope": {"mode": "incremental", "max_pages": 5},
                }
                idempotent = False
            else:
                idempotent = True
            scheduled.append({"id": task_id, "source_id": source_key, "idempotent": idempotent})
        return scheduled

    def schedule_due(self, worker_id: str, latest_window: str, last_seen_window: str | None) -> list[dict[str, Any]]:
        windows = tuple(window for window in (
            "2026-07-20T08:00+08:00",
            "2026-07-20T20:50+08:00",
            "2026-07-21T08:00+08:00",
            "2026-07-21T20:50+08:00",
        ) if (last_seen_window is None or window > last_seen_window) and window <= latest_window)
        scheduled: list[dict[str, Any]] = []
        for window in windows:
            scheduled.extend(self.schedule_tick(worker_id, window))
        return scheduled

    def claim(self, worker_id: str) -> dict[str, Any] | None:
        for task in self.tasks.values():
            if task["worker_id"] != worker_id or task["status"] != "queued":
                continue
            task["status"] = "leased"
            task["attempt"] += 1
            return {
                "contract_version": "v0",
                "task_id": task["id"],
                "attempt": task["attempt"],
                "task_type": "discord_sync",
                "source_id": task["source_key"],
                "parameter_version": "v1-fixture",
                "lease_expires_at": "2099-01-01T00:10:00Z",
                "safe_checkpoint": task["safe_checkpoint"],
                "rule_snapshot": task["rule_snapshot"],
                "collection_scope": task["collection_scope"],
            }
        return None

    def accept_result(self, worker_id: str, result: dict[str, Any]) -> dict[str, Any]:
        task = self.tasks[str(result["task_id"])]
        if task["worker_id"] != worker_id or task["attempt"] != result["attempt"] or task["status"] != "leased":
            raise RuntimeError("lease mismatch")
        source_key = task["source_key"]
        checkpoint = str(result["safe_checkpoint"])
        task["status"] = "succeeded"
        task["safe_checkpoint"] = checkpoint
        self.checkpoints[source_key] = checkpoint
        previous = self.daily_summaries.get(source_key)
        version = 1 if previous is None else int(previous["version"]) + 1
        batch = {
            "id": f"batch-{task['id']}",
            "input_message_ids": [f"{source_key}-message-1"],
            "structured_run_ids": [f"run-{task['id']}"],
            "output": {"topics": [{"label": f"{source_key}-fixture-topic"}], "warnings": []},
            "coverage": {"unparsed_media": False},
        }
        self.daily_summaries[source_key] = {
            "source_key": source_key,
            "natural_date": "2026-07-19",
            "version": version,
            "output": batch["output"],
            "coverage": batch["coverage"],
            "batches": [batch],
            "messages": [{
                "external_message_id": f"{source_key}-message-1",
                "occurred_at": "2026-07-19T00:00:00Z",
                "author_display": "Public Fixture Author",
                "content": f"Public fixture message for {source_key}.",
                "has_unparsed_media": False,
                "unresolved": False,
            }],
        }
        return {"status": "succeeded", "idempotent": False}

    def fail(self, worker_id: str, failure: dict[str, Any]) -> dict[str, Any]:
        task = self.tasks[str(failure["task_id"])]
        if task["worker_id"] != worker_id:
            raise RuntimeError("lease mismatch")
        task["status"] = "retryable_failed"
        return {"status": "retryable_failed"}

    def tasks_for(self, source_key: str) -> list[dict[str, Any]]:
        return [dict(task) for task in self.tasks.values() if task["source_key"] == source_key]

    def read_as_user(self, user_id: str) -> list[dict[str, Any]]:
        if user_id != "user-1":
            raise PermissionError("unauthenticated")
        return [
            {
                "source_key": day["source_key"],
                "natural_date": day["natural_date"],
                "daily_summary": {"version": day["version"], "output": day["output"], "coverage": day["coverage"]},
                "batches": day["batches"],
                "messages": day["messages"],
            }
            for _source_key, day in sorted(self.daily_summaries.items())
        ]

    def list_admin_tasks(self, user_id: str) -> list[dict[str, Any]]:
        if user_id != "admin-1":
            raise PermissionError("forbidden")
        return [dict(task) for task in self.tasks.values()]


class V1FixtureProtocol:
    def __init__(self, control: V1FixtureControlPlane, worker_id: str) -> None:
        self.control = control
        self.worker_id = worker_id

    def heartbeat(self, *_args: object, **_kwargs: object) -> dict[str, Any]:
        return {"status": "online"}

    def claim(self) -> dict[str, Any] | None:
        return self.control.claim(self.worker_id)

    def report_result(self, result: dict[str, Any]) -> dict[str, Any]:
        return self.control.accept_result(self.worker_id, result)

    def report_failure(self, failure: dict[str, Any]) -> dict[str, Any]:
        return self.control.fail(self.worker_id, failure)


def build_v1_fixture_worker(
    control: V1FixtureControlPlane,
    *,
    source_id: str,
    failure_class: str | None = None,
) -> Worker:
    source = control.sources[source_id]

    def execute(claim: dict[str, Any]) -> dict[str, Any]:
        if claim["source_id"] != source_id:
            raise RuntimeError("unexpected fixture source")
        if failure_class:
            raise FixtureProviderFailure(failure_class)
        return {
            "contract_version": "v0",
            "task_id": claim["task_id"],
            "attempt": claim["attempt"],
            "status": "succeeded",
            "safe_checkpoint": f"{source_id}-cursor-1",
            "raw_count": 1,
            "canonical_count": 1,
            "duplicate_count": 0,
            "unresolved_count": 0,
            "unparsed_media_count": 0,
            "structured_run_ids": [],
            "telemetry": {"elapsed_ms": 1, "retry_count": 0, "failure_class": None},
        }

    return Worker(
        V1FixtureProtocol(control, str(source["worker_id"])),
        execute=execute,
        clock=lambda: datetime.now(timezone.utc) + timedelta(seconds=1),
    )
