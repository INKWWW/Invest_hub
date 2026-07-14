from __future__ import annotations

import hashlib
import json
import os
from dataclasses import asdict
from pathlib import Path

from .model import Checkpoint


class CheckpointError(RuntimeError):
    """Raised when checkpoint persistence fails."""


class JsonCheckpointStore:
    def __init__(self, root: Path) -> None:
        self.root = root
        root.mkdir(parents=True, exist_ok=True)

    def load(self, source_container_id: str) -> Checkpoint | None:
        target = self._path(source_container_id)
        if not target.exists():
            return None
        try:
            payload = json.loads(target.read_text(encoding="utf-8"))
            return Checkpoint(**payload)
        except (OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise CheckpointError(f"checkpoint read failed: {exc}") from exc

    def commit(self, checkpoint: Checkpoint) -> None:
        target = self._path(checkpoint.source_container_id)
        temporary = target.with_suffix(".tmp")
        try:
            with temporary.open("w", encoding="utf-8") as handle:
                json.dump(asdict(checkpoint), handle, ensure_ascii=False, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, target)
        except OSError as exc:
            if temporary.exists():
                temporary.unlink()
            raise CheckpointError(f"checkpoint commit failed: {exc}") from exc

    def _path(self, source_container_id: str) -> Path:
        digest = hashlib.sha256(source_container_id.encode("utf-8")).hexdigest()
        return self.root / f"{digest}.json"
