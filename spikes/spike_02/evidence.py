from __future__ import annotations

import json
import os
import threading
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any

from .model import ChunkResult, LLMRequest, ProviderResponse, RunReport


class EvidenceError(RuntimeError):
    """Raised when local Spike evidence cannot be persisted."""


class EvidenceStore:
    def __init__(self, root: Path):
        self.root = root
        self._lock = threading.Lock()
        (root / "raw_responses").mkdir(parents=True, exist_ok=True)

    def persist_request(self, request: LLMRequest, response: ProviderResponse) -> None:
        with self._lock:
            self._append_jsonl(
                self.root / "requests.jsonl",
                {
                    "run_id": request.run_id,
                    "prompt_version": request.prompt_version,
                    "case_id": request.chunk.case_id,
                    "chunk_id": request.chunk.chunk_id,
                    "attempt": request.attempt,
                    "provider_response_status": response.status,
                    "latency_ms": response.latency_ms,
                    "input_tokens": response.input_tokens,
                    "output_tokens": response.output_tokens,
                    "error_code": response.error_code,
                    "process_exit_code": response.process_exit_code,
                    "stderr_present": bool(response.diagnostic),
                },
            )

    def persist_result(self, result: ChunkResult) -> None:
        with self._lock:
            self._append_jsonl(self.root / "results.jsonl", asdict(result))

    def persist_raw_response(self, request_id: str, payload: object) -> None:
        with self._lock:
            self._write_json(self.root / "raw_responses" / f"{request_id}.json", payload)

    def persist_metrics(self, report: RunReport) -> None:
        with self._lock:
            self._write_json(self.root / "metrics.json", asdict(report))

    @staticmethod
    def _write_json(target: Path, payload: object) -> None:
        try:
            with target.open("w", encoding="utf-8") as handle:
                json.dump(_jsonable(payload), handle, ensure_ascii=False, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as exc:
            raise EvidenceError(f"evidence write failed: {exc}") from exc

    @staticmethod
    def _append_jsonl(target: Path, payload: object) -> None:
        try:
            with target.open("a", encoding="utf-8") as handle:
                handle.write(
                    json.dumps(_jsonable(payload), ensure_ascii=False, sort_keys=True)
                    + "\n"
                )
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as exc:
            raise EvidenceError(f"evidence append failed: {exc}") from exc


def _jsonable(payload: object) -> object:
    if is_dataclass(payload):
        return asdict(payload)
    return payload
