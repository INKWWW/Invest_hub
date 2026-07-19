from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


_SHANGHAI = ZoneInfo("Asia/Shanghai")


def should_enqueue(now_utc: datetime, last_seen_window: str | None) -> str | None:
    """Return the newest due local schedule window exactly once.

    Returning the latest missed window lets a Worker that was offline at a
    scheduled time request a normal checkpoint-based catch-up task instead of
    claiming that an empty run succeeded.
    """

    if now_utc.tzinfo is None:
        raise ValueError("now_utc must be timezone-aware")
    local_now = now_utc.astimezone(_SHANGHAI)
    morning = local_now.replace(hour=8, minute=0, second=0, microsecond=0)
    evening = local_now.replace(hour=20, minute=50, second=0, microsecond=0)
    if local_now >= evening:
        candidate = evening
    elif local_now >= morning:
        candidate = morning
    else:
        previous = local_now - timedelta(days=1)
        candidate = previous.replace(hour=20, minute=50, second=0, microsecond=0)

    compact = candidate.strftime("%Y-%m-%dT%H:%M%z")
    key = f"{compact[:-2]}:{compact[-2:]}"
    return None if key == last_seen_window else key
