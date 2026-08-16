from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal

from .contracts import load_contract


WorkerStatus = Literal["idle", "claimed", "executing", "reporting", "recovering", "stopped"]


def build_heartbeat(
    worker_id: str,
    status: WorkerStatus,
    capabilities: list[Literal["discord_sync", "x_sync", "agent_demo"]] | None = None,
    sent_at: str | None = None,
) -> dict[str, object]:
    payload = {
        "contract_version": "v0",
        "worker_id": worker_id,
        "sent_at": sent_at or datetime.now(timezone.utc).isoformat(),
        "status": status,
        "capabilities": capabilities or ["discord_sync"],
    }
    return load_contract("heartbeat", payload)
