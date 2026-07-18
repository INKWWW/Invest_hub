from __future__ import annotations

import json
import os
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any, Iterable

from .canonical import CanonicalMessage
from .connectors.base import RawPage


class EvidenceError(RuntimeError):
    pass


class LocalEvidenceStore:
    def __init__(self, root: Path) -> None:
        self.root = root
        for name in ("raw", "canonical", "validation", "metrics"):
            (root / name).mkdir(parents=True, exist_ok=True)

    def persist_raw(self, page: RawPage) -> None:
        self._write_json(self.root / "raw" / f"{page.page_id}.json", asdict(page))

    def persist_canonical(self, messages: tuple[CanonicalMessage, ...]) -> dict[str, int]:
        target = self.root / "canonical" / "messages.jsonl"
        existing = self._existing_ids(target)
        canonical_count = 0
        duplicate_count = 0
        try:
            with target.open("a", encoding="utf-8") as stream:
                for message in messages:
                    key = f"{message.source_id}:{message.external_message_id}"
                    if key in existing:
                        duplicate_count += 1
                        continue
                    stream.write(json.dumps(asdict(message), ensure_ascii=False, sort_keys=True) + "\n")
                    existing.add(key)
                    canonical_count += 1
                stream.flush()
                os.fsync(stream.fileno())
        except OSError as exc:
            raise EvidenceError("canonical persistence failed") from exc
        return {"canonical_count": canonical_count, "duplicate_count": duplicate_count}

    def persist_validation(self, payload: object) -> None:
        self._append_jsonl(self.root / "validation" / "reports.jsonl", payload)

    @staticmethod
    def _write_json(target: Path, payload: object) -> None:
        try:
            with target.open("w", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
        except OSError as exc:
            raise EvidenceError("raw persistence failed") from exc

    @staticmethod
    def _append_jsonl(target: Path, payload: object) -> None:
        try:
            with target.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(asdict(payload) if is_dataclass(payload) else payload, ensure_ascii=False, sort_keys=True) + "\n")
                stream.flush()
                os.fsync(stream.fileno())
        except OSError as exc:
            raise EvidenceError("validation persistence failed") from exc

    @staticmethod
    def _existing_ids(target: Path) -> set[str]:
        if not target.exists():
            return set()
        ids: set[str] = set()
        for line in target.read_text(encoding="utf-8").splitlines():
            if line:
                payload = json.loads(line)
                ids.add(f"{payload['source_id']}:{payload['external_message_id']}")
        return ids
