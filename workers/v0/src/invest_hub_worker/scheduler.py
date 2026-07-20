from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


_SHANGHAI = ZoneInfo("Asia/Shanghai")
_WINDOW_TIMES = ((8, 0), (20, 50))
_MAX_CATCH_UP_WINDOWS = 4


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
    last_seen_window: str | None,
    *,
    max_windows: int = _MAX_CATCH_UP_WINDOWS,
) -> tuple[tuple[str, ...], bool]:
    """Return chronological due windows and whether the catch-up was bounded.

    The control plane owns final idempotency.  This helper only bounds the
    local request burst after a Worker was offline, so a restart cannot turn
    into an unbounded historical collection request.
    """

    if now_utc.tzinfo is None:
        raise ValueError("now_utc must be timezone-aware")
    if max_windows < 1:
        raise ValueError("max_windows must be positive")
    if last_seen_window is not None and not is_schedule_window_key(last_seen_window):
        raise ValueError("last_seen_window must be a schedule window key")

    local_now = now_utc.astimezone(_SHANGHAI)
    earliest = local_now - timedelta(hours=48)
    candidates: list[str] = []
    date = earliest.date()
    while date <= local_now.date():
        for hour, minute in _WINDOW_TIMES:
            candidate = datetime(date.year, date.month, date.day, hour, minute, tzinfo=_SHANGHAI)
            if earliest <= candidate <= local_now:
                candidates.append(_window_key(candidate))
        date += timedelta(days=1)

    unseen = [window for window in candidates if last_seen_window is None or window > last_seen_window]
    truncated = len(unseen) > max_windows
    return tuple(unseen[-max_windows:]), truncated


def should_enqueue(now_utc: datetime, last_seen_window: str | None) -> str | None:
    """Return the newest due local schedule window exactly once.

    Returning the latest missed window lets a Worker that was offline at a
    scheduled time request a normal checkpoint-based catch-up task instead of
    claiming that an empty run succeeded.
    """

    windows, _truncated = due_windows(now_utc, last_seen_window, max_windows=1)
    return windows[0] if windows else None


def _window_key(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H:%M+08:00")
