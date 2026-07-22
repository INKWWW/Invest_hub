from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


_SHANGHAI = ZoneInfo("Asia/Shanghai")
_WINDOW_TIMES = ((0, 0), (8, 0), (16, 0), (20, 50))


def is_schedule_window_key(value: object) -> bool:
    if not isinstance(value, str):
        return False
    if len(value) != 22 or not value.endswith("+08:00"):
        return False
    try:
        local = datetime.strptime(value, "%Y-%m-%dT%H:%M+08:00")
    except ValueError:
        return False
    return (local.hour, local.minute) in _WINDOW_TIMES


def due_windows(
    now_utc: datetime,
    coverage_through_at: datetime,
) -> tuple[str, ...]:
    """Return every Shanghai boundary in ``(coverage_through_at, now_utc]``.

    This is pure, deterministic schedule arithmetic.  The control plane
    remains the authority that uses its own server time, persists each task,
    and serializes source coverage; this helper deliberately has no page or
    catch-up count limit.
    """

    if now_utc.tzinfo is None:
        raise ValueError("now_utc must be timezone-aware")
    if coverage_through_at.tzinfo is None:
        raise ValueError("coverage_through_at must be timezone-aware")
    if coverage_through_at > now_utc:
        raise ValueError("coverage_through_at cannot be after now_utc")

    local_now = now_utc.astimezone(_SHANGHAI)
    local_coverage = coverage_through_at.astimezone(_SHANGHAI)
    candidates: list[str] = []
    date = local_coverage.date()
    while date <= local_now.date():
        for hour, minute in _WINDOW_TIMES:
            candidate = datetime(date.year, date.month, date.day, hour, minute, tzinfo=_SHANGHAI)
            if local_coverage < candidate <= local_now:
                candidates.append(_window_key(candidate))
        date += timedelta(days=1)
    return tuple(candidates)


def _window_key(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H:%M+08:00")
