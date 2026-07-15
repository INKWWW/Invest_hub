from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path


MATCH_STATES = frozenset(
    {
        "matched_new",
        "matched_stale",
        "missing",
        "wrong_container",
        "cursor_not_advanced",
        "command_failed",
        "timeout",
    }
)


@dataclass(frozen=True)
class PageTiming:
    page_index: int
    elapsed_ms: int
    open_ms: int
    wait_ms: int
    network_observation_ms: int
    detail_ms: int
    mapping_ms: int
    validation_ms: int
    persist_ms: int
    network_attempts: int
    match_state: str
    error_code: str | None


class TelemetryRecorder:
    def __init__(self, target: Path) -> None:
        self.target = target
        target.parent.mkdir(parents=True, exist_ok=True)

    def record(self, timing: PageTiming) -> None:
        if timing.match_state not in MATCH_STATES:
            raise ValueError(f"match_state is not allowed: {timing.match_state}")
        payload = asdict(timing)
        try:
            with self.target.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(payload, sort_keys=True) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as exc:
            raise RuntimeError(f"telemetry persistence failed: {exc}") from exc
