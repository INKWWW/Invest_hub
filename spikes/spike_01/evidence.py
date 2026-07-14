from __future__ import annotations

import json
import os
from dataclasses import asdict
from pathlib import Path

from .model import (
    CanonicalMessage,
    RawPage,
    ValidationReport,
)


class EvidenceError(RuntimeError):
    """Raised when local evidence cannot be persisted."""


class LocalEvidenceStore:
    def __init__(self, root: Path) -> None:
        self.root = root
        for name in ("raw", "canonical", "validation", "metrics"):
            (root / name).mkdir(parents=True, exist_ok=True)

    def persist_raw(self, page: RawPage) -> None:
        target = self.root / "raw" / f"{page.page_id}.json"
        self._write_json(target, asdict(page))

    def persist_canonical(
        self,
        messages: tuple[CanonicalMessage, ...],
    ) -> None:
        target = self.root / "canonical" / "messages.jsonl"
        try:
            existing_ids = self._read_ids(target)
            with target.open("a", encoding="utf-8") as handle:
                for message in messages:
                    if message.external_item_id in existing_ids:
                        continue
                    handle.write(
                        json.dumps(
                            asdict(message),
                            ensure_ascii=False,
                            sort_keys=True,
                        )
                        + "\n"
                    )
                    existing_ids.add(message.external_item_id)
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as exc:
            raise EvidenceError(f"canonical persistence failed: {exc}") from exc

    def persist_validation(self, report: ValidationReport) -> None:
        self._append_jsonl(
            self.root / "validation" / "reports.jsonl",
            asdict(report),
        )

    def has_message(self, external_item_id: str) -> bool:
        return external_item_id in self._read_ids(
            self.root / "canonical" / "messages.jsonl"
        )

    def message_count(self) -> int:
        target = self.root / "canonical" / "messages.jsonl"
        if not target.exists():
            return 0
        return sum(1 for line in target.read_text(encoding="utf-8").splitlines() if line)

    @staticmethod
    def _write_json(target: Path, payload: object) -> None:
        try:
            with target.open("w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as exc:
            raise EvidenceError(f"JSON persistence failed: {exc}") from exc

    @staticmethod
    def _append_jsonl(target: Path, payload: object) -> None:
        try:
            with target.open("a", encoding="utf-8") as handle:
                handle.write(
                    json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n"
                )
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as exc:
            raise EvidenceError(f"JSONL persistence failed: {exc}") from exc

    @staticmethod
    def _read_ids(target: Path) -> set[str]:
        if not target.exists():
            return set()
        ids: set[str] = set()
        for line in target.read_text(encoding="utf-8").splitlines():
            if line:
                payload = json.loads(line)
                ids.add(str(payload["external_item_id"]))
        return ids
