from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class LeaseState:
    task_id: str
    attempt: int
    lease_expires_at: str

    def expires_at(self) -> datetime:
        return datetime.fromisoformat(self.lease_expires_at.replace("Z", "+00:00"))

    def is_expired(self, now: datetime) -> bool:
        return self.expires_at() <= now

    def should_renew(self, now: datetime, threshold_seconds: int = 120) -> bool:
        if self.is_expired(now):
            return False
        return (self.expires_at() - now).total_seconds() <= threshold_seconds


class LeaseTracker:
    def __init__(self) -> None:
        self.current: LeaseState | None = None
        self.uncertain = False

    def begin(self, claim: dict[str, object]) -> LeaseState:
        self.current = LeaseState(
            task_id=str(claim["task_id"]),
            attempt=int(claim["attempt"]),
            lease_expires_at=str(claim["lease_expires_at"]),
        )
        self.uncertain = False
        return self.current

    def mark_uncertain(self) -> None:
        self.uncertain = True

    def clear(self) -> None:
        self.current = None
        self.uncertain = False
