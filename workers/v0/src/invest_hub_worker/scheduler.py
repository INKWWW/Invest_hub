from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


_SHANGHAI = ZoneInfo("Asia/Shanghai")
_WINDOW_TIMES = ((0, 0), (8, 0), (16, 0), (20, 50))
_X_WINDOW_TIMES = ((0, 0), (8, 0), (12, 0), (16, 0), (20, 0))


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

    return _due_windows(now_utc, coverage_through_at, _WINDOW_TIMES)


def is_x_schedule_window_key(value: object) -> bool:
    if not isinstance(value, str) or len(value) != 22 or not value.endswith("+08:00"):
        return False
    try:
        local = datetime.strptime(value, "%Y-%m-%dT%H:%M+08:00")
    except ValueError:
        return False
    return (local.hour, local.minute) in _X_WINDOW_TIMES


def due_x_windows(now_utc: datetime, coverage_through_at: datetime) -> tuple[str, ...]:
    """Return every fixed X cutoff in ``(coverage_through_at, now_utc]``.

    This intentionally remains separate from the Discord cadence: X has a
    noon cutoff and a 20:00 cutoff, while the V1.1 Discord cadence remains
    unchanged at 20:50.
    """

    return _due_windows(now_utc, coverage_through_at, _X_WINDOW_TIMES)


def fixed_x_window(cutoff: str | datetime) -> dict[str, str]:
    """Return the exact independent range immediately before one X cutoff."""

    cutoff_at = _parse_x_cutoff(cutoff)
    local_cutoff = cutoff_at.astimezone(_SHANGHAI)
    if (local_cutoff.hour, local_cutoff.minute) not in _X_WINDOW_TIMES:
        raise ValueError("cutoff must be an approved Shanghai X boundary")

    previous_hour = {0: 20, 8: 0, 12: 8, 16: 12, 20: 16}[local_cutoff.hour]
    previous_day = local_cutoff.date() - timedelta(days=1) if local_cutoff.hour == 0 else local_cutoff.date()
    start_local = datetime(
        previous_day.year, previous_day.month, previous_day.day, previous_hour, tzinfo=_SHANGHAI,
    )
    return {
        "start_at": start_local.astimezone(ZoneInfo("UTC")).isoformat(),
        "end_at": cutoff_at.astimezone(ZoneInfo("UTC")).isoformat(),
        "scheduled_window_key": local_cutoff.strftime("%Y-%m-%dT%H:%M+08:00"),
        "natural_date": (local_cutoff.date() - timedelta(days=1) if local_cutoff.hour == 0 else local_cutoff.date()).isoformat(),
    }


def _parse_x_cutoff(value: str | datetime) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("cutoff must be an ISO timestamp") from exc
    else:
        raise ValueError("cutoff must be an ISO timestamp")
    if parsed.tzinfo is None:
        raise ValueError("cutoff must be timezone-aware")
    local = parsed.astimezone(_SHANGHAI)
    if local.utcoffset() != _SHANGHAI.utcoffset(local) or parsed.isoformat().endswith("+08:00") is False:
        raise ValueError("cutoff must use the Shanghai offset")
    return parsed


def _due_windows(
    now_utc: datetime,
    coverage_through_at: datetime,
    boundaries: tuple[tuple[int, int], ...],
) -> tuple[str, ...]:
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
        for hour, minute in boundaries:
            candidate = datetime(date.year, date.month, date.day, hour, minute, tzinfo=_SHANGHAI)
            if local_coverage < candidate <= local_now:
                candidates.append(_window_key(candidate))
        date += timedelta(days=1)
    return tuple(candidates)


def _window_key(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H:%M+08:00")
