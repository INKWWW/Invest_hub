from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone
from typing import Any, Iterable
from zoneinfo import ZoneInfo


SHANGHAI = ZoneInfo("Asia/Shanghai")
X_CUTOFFS = (time(0, 0), time(8, 0), time(12, 0), time(16, 0), time(20, 0))


def instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def text(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def cutoffs_after(start_at: datetime, now_at: datetime) -> list[datetime]:
    result: list[datetime] = []
    day = start_at.astimezone(SHANGHAI).date()
    while day <= now_at.astimezone(SHANGHAI).date():
        for at in X_CUTOFFS:
            boundary = datetime.combine(day, at, tzinfo=SHANGHAI).astimezone(timezone.utc)
            if start_at < boundary <= now_at:
                result.append(boundary)
        day += timedelta(days=1)
    return result


@dataclass(frozen=True)
class XPost:
    id: str
    occurred_at: datetime
    post_type: str
    has_context: bool = False


def collect_pages(pages: Iterable[tuple[XPost, ...]], *, start_at: datetime, end_at: datetime, persisted: Iterable[str] = ()) -> tuple[bool, tuple[str, ...]]:
    seen, selected, boundary = set(persisted), [], False
    for page in pages:
        if not page:
            boundary = True
        for post in page:
            if post.occurred_at > end_at:
                raise ValueError("post_after_end")
            if start_at < post.occurred_at <= end_at and post.id not in seen:
                seen.add(post.id); selected.append(post.id)
        if page and min(post.occurred_at for post in page) <= start_at - timedelta(minutes=30):
            boundary = True
    return boundary, tuple(selected)


class V2FixtureControl:
    def __init__(self) -> None:
        self.sources: dict[str, datetime] = {}
        self.tasks: dict[str, dict[str, Any]] = {}
        self.segments: dict[tuple[str, str], list[dict[str, Any]]] = {}

    def configure(self, source: str, coverage: str) -> None:
        self.sources[source] = instant(coverage)

    def schedule(self, source: str, now: str) -> list[dict[str, Any]]:
        start, due = self.sources[source], cutoffs_after(self.sources[source], instant(now))
        tasks = []
        for end in due:
            task = {"id": f"{source}-{len(self.tasks)+1}", "source": source, "start": start, "end": end, "status": "queued"}
            self.tasks[task["id"]] = task; tasks.append(task); start = end
        return tasks

    def complete(self, task_id: str, *, post_ids: tuple[str, ...], viewpoints: tuple[str, ...], natural_date: str) -> None:
        task = self.tasks[task_id]
        if self.sources[task["source"]] != task["start"]:
            raise ValueError("waterline_not_contiguous")
        task["status"] = "succeeded"; self.sources[task["source"]] = task["end"]
        if post_ids:
            self.segments.setdefault((task["source"], natural_date), []).append({"task": task_id, "postIds": post_ids, "viewpoints": viewpoints})

    def reader(self, source: str, date: str, user: str) -> dict[str, Any]:
        if user != "reader": raise PermissionError("forbidden")
        segments = self.segments.get((source, date), [])
        return {"displayName": f"{source} fixture", "naturalDate": date, "currentDailyTimeline": {"windowSegments": segments}, "historicalVersions": []}
