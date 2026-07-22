from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone
from typing import Any, Iterable
from zoneinfo import ZoneInfo


SHANGHAI = ZoneInfo("Asia/Shanghai")
WINDOW_TIMES = (time(0, 0), time(8, 0), time(16, 0), time(20, 50))


def instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def instant_text(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def scheduled_window_ends(start_at: datetime, end_at: datetime) -> list[datetime]:
    """Return Shanghai 00:00/08:00/16:00/20:50 ends in (start_at, end_at]."""
    local_start = start_at.astimezone(SHANGHAI)
    local_end = end_at.astimezone(SHANGHAI)
    day = local_start.date()
    result: list[datetime] = []
    while day <= local_end.date():
        for boundary_time in WINDOW_TIMES:
            boundary = datetime.combine(day, boundary_time, tzinfo=SHANGHAI)
            if local_start < boundary <= local_end:
                result.append(boundary.astimezone(timezone.utc))
        day += timedelta(days=1)
    return result


@dataclass(frozen=True)
class FixtureMessage:
    external_id: str
    occurred_at: datetime
    author_id: str
    content: str
    has_unparsed_media: bool = False


@dataclass(frozen=True)
class FixturePage:
    cursor: str
    next_cursor: str | None
    messages: tuple[FixtureMessage, ...]


@dataclass(frozen=True)
class CollectionProgress:
    complete: bool
    next_cursor: str | None
    page_count: int
    message_ids: tuple[str, ...]


def collect_window_pages(
    pages: Iterable[FixturePage],
    *,
    start_at: datetime,
    end_at: datetime,
    resume_cursor: str | None = None,
    persisted_message_ids: Iterable[str] = (),
    interrupt_after_pages: int | None = None,
) -> CollectionProgress:
    """Public deterministic model of page-by-page V1.1 capture and resume."""
    page_list = tuple(pages)
    start_index = 0
    if resume_cursor is not None:
        matches = [index for index, page in enumerate(page_list) if page.cursor == resume_cursor]
        if len(matches) != 1:
            raise ValueError("unknown_resume_cursor")
        start_index = matches[0]

    seen = set(persisted_message_ids)
    selected: list[str] = []
    processed_pages = 0
    boundary_proven = False
    next_cursor: str | None = resume_cursor
    for page in page_list[start_index:]:
        processed_pages += 1
        next_cursor = page.next_cursor
        if not page.messages:
            boundary_proven = True
        for message in page.messages:
            if start_at < message.occurred_at <= end_at and message.external_id not in seen:
                seen.add(message.external_id)
                selected.append(message.external_id)
        if page.messages and min(message.occurred_at for message in page.messages) <= start_at:
            boundary_proven = True
        if interrupt_after_pages is not None and processed_pages == interrupt_after_pages:
            return CollectionProgress(
                complete=False,
                next_cursor=page.next_cursor,
                page_count=processed_pages,
                message_ids=tuple(selected),
            )
    return CollectionProgress(
        complete=boundary_proven,
        next_cursor=None if boundary_proven else next_cursor,
        page_count=processed_pages,
        message_ids=tuple(selected),
    )


class V11FixtureControlPlane:
    """Public cross-layer fixture: schedule -> capture -> safe reader projection."""

    def __init__(self) -> None:
        self.sources: dict[str, dict[str, Any]] = {}
        self.tasks: dict[str, dict[str, Any]] = {}
        self._task_by_range: dict[tuple[str, str, str], str] = {}
        self._reader_days: dict[str, dict[str, Any]] = {}
        self._next_task_number = 0

    def configure_source(
        self,
        source_key: str,
        *,
        worker_id: str,
        coverage_through_at: str,
        author_profiles: tuple[dict[str, str], ...] = (),
    ) -> None:
        self.sources[source_key] = {
            "worker_id": worker_id,
            "coverage_through_at": instant(coverage_through_at),
            "author_profiles": tuple(author_profiles),
        }

    def schedule_due(self, worker_id: str, *, now: str) -> list[dict[str, Any]]:
        now_at = instant(now)
        created: list[dict[str, Any]] = []
        for source_key, source in sorted(self.sources.items()):
            if source["worker_id"] != worker_id:
                continue
            range_start = source["coverage_through_at"]
            for range_end in scheduled_window_ends(range_start, now_at):
                created.append(self._create_task(source_key, range_start, range_end, trigger="scheduled"))
                range_start = range_end
        return created

    def manual_refresh(self, source_key: str, *, actor_id: str, now: str) -> dict[str, Any]:
        if actor_id != "admin-1":
            raise PermissionError("forbidden")
        source = self.sources[source_key]
        active = [
            task for task in self.tasks.values()
            if task["source_key"] == source_key and task["status"] in {"queued", "running", "retryable_failed"}
        ]
        if active:
            return {**min(active, key=lambda task: task["start_at"]), "idempotent": True}
        return self._create_task(source_key, source["coverage_through_at"], instant(now), trigger="manual")

    def mark_failed(self, task_id: str) -> None:
        self.tasks[task_id]["status"] = "retryable_failed"

    def complete(self, task_id: str, *, daily_presentation: dict[str, Any] | None = None) -> None:
        task = self.tasks[task_id]
        source = self.sources[task["source_key"]]
        if task["status"] == "succeeded":
            return
        if source["coverage_through_at"] != task["start_at"]:
            raise ValueError("out_of_order_completion")
        task["status"] = "succeeded"
        source["coverage_through_at"] = task["end_at"]
        self._reader_days[task["source_key"]] = self._safe_reader_day(task, daily_presentation)

    def reader_as_user(self, user_id: str) -> list[dict[str, Any]]:
        if user_id != "user-1":
            raise PermissionError("unauthenticated")
        return [self._reader_days[source_key] for source_key in sorted(self._reader_days)]

    def _create_task(self, source_key: str, start_at: datetime, end_at: datetime, *, trigger: str) -> dict[str, Any]:
        if start_at >= end_at:
            raise ValueError("invalid_capture_range")
        key = (source_key, instant_text(start_at), instant_text(end_at))
        existing_id = self._task_by_range.get(key)
        if existing_id is not None:
            return {**self.tasks[existing_id], "idempotent": True}
        self._next_task_number += 1
        task_id = f"v1-1-task-{self._next_task_number}"
        task = {
            "id": task_id,
            "source_key": source_key,
            "status": "queued",
            "trigger": trigger,
            "start_at": start_at,
            "end_at": end_at,
            "collection_scope": {"mode": "window"},
            "idempotent": False,
        }
        self.tasks[task_id] = task
        self._task_by_range[key] = task_id
        return dict(task)

    def _safe_reader_day(self, task: dict[str, Any], presentation: dict[str, Any] | None) -> dict[str, Any]:
        source = self.sources[task["source_key"]]
        if presentation is None:
            profiles = source["author_profiles"]
            presentation = {
                "kind": "v1.1",
                "asOf": instant_text(task["end_at"]),
                "authorCards": [{
                    "authorName": profile["author_display"],
                    "coreLogic": {"marketTrend": "公开 fixture 市场判断", "stockJudgments": ["公开 fixture 个股判断"]},
                    "operationTendency": {"market": "观察", "stocks": "等待"},
                    "strategy": ["分批验证"],
                    "uncertainty": ["公开 fixture 不构成投资建议"],
                } for profile in profiles],
                "topicDiscussions": [{
                    "topic": "公开 fixture 话题",
                    "summary": "不同作者观点并列呈现。",
                    "viewpoints": [{"authorName": profile["author_display"], "viewpoint": "公开 fixture 观点"} for profile in profiles],
                }],
                "warnings": ["存在未解析媒体，以下结论不覆盖媒体内容。"],
            }
        return {
            "source": {"sourceKey": task["source_key"], "displayName": f"{task['source_key']} fixture"},
            "naturalDate": task["end_at"].astimezone(SHANGHAI).date().isoformat(),
            "status": "succeeded",
            "dailySummary": {"version": 1, "presentation": presentation, "history": []},
            "batches": [{"presentation": presentation}],
        }
