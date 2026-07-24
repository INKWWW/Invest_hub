from __future__ import annotations

import fcntl
import json
import os
import stat
import tempfile
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
        self._ensure_private_directory(root)
        for name in ("raw", "canonical", "validation", "metrics"):
            self._ensure_private_directory(root / name)

    def persist_raw(self, page: RawPage) -> None:
        self._write_json(self.root / "raw" / f"{page.page_id}.json", asdict(page))

    def persist_canonical(self, messages: tuple[CanonicalMessage, ...]) -> dict[str, int]:
        target = self.root / "canonical" / "messages.jsonl"
        canonical_count = 0
        duplicate_count = 0
        try:
            lock_path = target.with_suffix(".lock")
            with lock_path.open("a", encoding="utf-8") as lock:
                self._restrict_file(lock_path)
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
                try:
                    existing_lines = self._existing_lines(target)
                    existing = self._existing_ids(target)
                    for message in messages:
                        key = f"{message.source_id}:{message.external_message_id}"
                        if key in existing:
                            duplicate_count += 1
                            continue
                        existing_lines.append(self._jsonl_line(asdict(message)))
                        existing.add(key)
                        canonical_count += 1
                    self._replace_jsonl(target, existing_lines)
                finally:
                    fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        except OSError as exc:
            raise EvidenceError("canonical persistence failed") from exc
        return {"canonical_count": canonical_count, "duplicate_count": duplicate_count}

    def persist_validation(self, payload: object) -> None:
        self._append_jsonl(self.root / "validation" / "reports.jsonl", payload)

    @staticmethod
    def _write_json(target: Path, payload: object) -> None:
        try:
            with target.open("w", encoding="utf-8") as stream:
                LocalEvidenceStore._restrict_file(target)
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
                LocalEvidenceStore._restrict_file(target)
                stream.write(json.dumps(asdict(payload) if is_dataclass(payload) else payload, ensure_ascii=False, sort_keys=True) + "\n")
                stream.flush()
                os.fsync(stream.fileno())
        except OSError as exc:
            raise EvidenceError("validation persistence failed") from exc

    @staticmethod
    def _ensure_private_directory(path: Path) -> None:
        try:
            path.mkdir(parents=True, exist_ok=True)
            os.chmod(path, 0o700)
            if stat.S_IMODE(path.stat().st_mode) & 0o077:
                raise OSError("evidence directory permissions are too broad")
        except OSError as exc:
            raise EvidenceError("evidence directory must be owner-only") from exc

    @staticmethod
    def _restrict_file(path: Path) -> None:
        try:
            os.chmod(path, 0o600)
            if stat.S_IMODE(path.stat().st_mode) & 0o077:
                raise OSError("evidence file permissions are too broad")
        except OSError as exc:
            raise EvidenceError("evidence file must be owner-only") from exc

    @staticmethod
    def _replace_jsonl(target: Path, lines: list[str]) -> None:
        temporary_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=target.parent,
                prefix=f".{target.name}.",
                delete=False,
            ) as stream:
                temporary_path = Path(stream.name)
                LocalEvidenceStore._restrict_file(temporary_path)
                for line in lines:
                    stream.write(line + "\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary_path, target)
            LocalEvidenceStore._restrict_file(target)
        except OSError:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)
            raise

    @staticmethod
    def _existing_lines(target: Path) -> list[str]:
        if not target.exists():
            return []
        lines: list[str] = []
        for line in target.read_text(encoding="utf-8").split("\n"):
            if line:
                lines.append(LocalEvidenceStore._jsonl_line(json.loads(line)))
        return lines

    @staticmethod
    def _jsonl_line(payload: object) -> str:
        encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        return encoded.replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")

    @staticmethod
    def _existing_ids(target: Path) -> set[str]:
        if not target.exists():
            return set()
        ids: set[str] = set()
        for line in target.read_text(encoding="utf-8").split("\n"):
            if line:
                payload = json.loads(line)
                ids.add(f"{payload['source_id']}:{payload['external_message_id']}")
        return ids
