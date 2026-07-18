from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
import threading
import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .model import LLMRequest, ProviderResponse


class ProviderError(RuntimeError):
    """Raised only for invalid Provider configuration."""


DEFAULT_CODEX_TIMEOUT_SECONDS = 240.0


class LLMProvider(Protocol):
    def complete(self, request: LLMRequest) -> ProviderResponse:
        raise NotImplementedError


@dataclass(frozen=True)
class MockOutcome:
    status: str
    content: str | None
    error_code: str | None
    finish_reason: str | None

    @classmethod
    def success(cls, content: str) -> "MockOutcome":
        return cls("success", content, None, "stop")

    @classmethod
    def failure(cls, status: str, error_code: str | None = None) -> "MockOutcome":
        return cls(status, None, error_code or status, None)

    @classmethod
    def truncated(cls, content: str) -> "MockOutcome":
        return cls("truncated", content, "output_truncated", "length")


class MockProvider:
    def __init__(self, scripts: Mapping[str, Sequence[MockOutcome]]):
        self._scripts = {chunk_id: tuple(outcomes) for chunk_id, outcomes in scripts.items()}
        self._calls: dict[str, int] = {}
        self._lock = threading.Lock()

    @property
    def call_count(self) -> int:
        with self._lock:
            return sum(self._calls.values())

    def calls_for(self, chunk_id: str) -> int:
        with self._lock:
            return self._calls.get(chunk_id, 0)

    def complete(self, request: LLMRequest) -> ProviderResponse:
        chunk_id = request.chunk.chunk_id
        with self._lock:
            call_index = self._calls.get(chunk_id, 0)
            self._calls[chunk_id] = call_index + 1
        script = self._scripts.get(chunk_id, ())
        if call_index >= len(script):
            outcome = MockOutcome.failure("provider_script_exhausted")
        else:
            outcome = script[call_index]
        return ProviderResponse(
            status=outcome.status,
            content=outcome.content,
            latency_ms=1,
            input_tokens=None,
            output_tokens=None,
            finish_reason=outcome.finish_reason,
            error_code=outcome.error_code,
        )


class CodexCLIProvider:
    def __init__(
        self,
        *,
        binary: str = "codex",
        model: str | None = None,
        timeout_seconds: float = DEFAULT_CODEX_TIMEOUT_SECONDS,
        cwd: str | None = None,
        codex_home: str | None = None,
    ):
        if not binary.strip():
            raise ProviderError("binary must be non-empty")
        if model is not None and not model.strip():
            raise ProviderError("model must be non-empty when provided")
        if timeout_seconds <= 0:
            raise ProviderError("timeout_seconds must be positive")
        self.binary = binary
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.cwd = cwd
        self.codex_home = codex_home or os.environ.get(
            "CODEX_HOME",
            str(Path.home() / ".codex"),
        )

    def complete(self, request: LLMRequest) -> ProviderResponse:
        started = time.monotonic_ns()
        with tempfile.TemporaryDirectory(prefix="invest-hub-codex-") as directory:
            output_path = Path(directory) / "last-message.txt"
            diagnostic_path = Path(directory) / "diagnostic.txt"
            command = [
                self.binary,
                "exec",
                "--sandbox",
                "read-only",
                "--add-dir",
                self.codex_home,
                "--ephemeral",
                "--output-last-message",
                str(output_path),
            ]
            if self.model:
                command.extend(["--model", self.model])
            command.append("-")

            with diagnostic_path.open("w+", encoding="utf-8") as diagnostic_file:
                try:
                    process = subprocess.Popen(
                        command,
                        cwd=self.cwd,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.DEVNULL,
                        stderr=diagnostic_file,
                        start_new_session=True,
                        text=True,
                    )
                except OSError as exc:
                    return self._response(
                        "provider_failed",
                        started,
                        "provider_failed",
                        None,
                        str(exc),
                    )

                try:
                    process.communicate(
                        input=request.chunk.prompt_text,
                        timeout=self.timeout_seconds,
                    )
                except subprocess.TimeoutExpired as exc:
                    _terminate_process_group(process)
                    diagnostic = _read_diagnostic(diagnostic_file) or _timeout_diagnostic(exc)
                    return self._response(
                        "timeout",
                        started,
                        "timeout",
                        process.returncode,
                        diagnostic,
                    )

                stderr = _read_diagnostic(diagnostic_file)

            if process.returncode != 0:
                return self._response(
                    "provider_failed",
                    started,
                    "provider_failed",
                    process.returncode,
                    stderr,
                )

            try:
                content = output_path.read_text(encoding="utf-8")
            except FileNotFoundError:
                return self._response(
                    "empty_response",
                    started,
                    "empty_response",
                    process.returncode,
                    stderr,
                )
            except (OSError, UnicodeError) as exc:
                return self._response(
                    "invalid_provider_response",
                    started,
                    "invalid_provider_response",
                    process.returncode,
                    str(exc),
                )

            if not content.strip():
                return self._response(
                    "empty_response",
                    started,
                    "empty_response",
                    process.returncode,
                    stderr,
                )
            return ProviderResponse(
                status="success",
                content=content,
                latency_ms=_elapsed_ms(started),
                input_tokens=None,
                output_tokens=None,
                finish_reason=None,
                error_code=None,
                process_exit_code=process.returncode,
                diagnostic=stderr or None,
            )

    @staticmethod
    def _response(
        status: str,
        started_ns: int,
        error_code: str,
        process_exit_code: int | None,
        diagnostic: str | None,
    ) -> ProviderResponse:
        return ProviderResponse(
            status=status,
            content=None,
            latency_ms=_elapsed_ms(started_ns),
            input_tokens=None,
            output_tokens=None,
            finish_reason=None,
            error_code=error_code,
            process_exit_code=process_exit_code,
            diagnostic=diagnostic,
        )


def _timeout_diagnostic(error: subprocess.TimeoutExpired) -> str:
    return f"process exceeded timeout of {error.timeout} seconds"


def _read_diagnostic(file) -> str:
    file.flush()
    file.seek(0)
    return file.read()


def _terminate_process_group(process: subprocess.Popen) -> None:
    if process.stdin is not None:
        process.stdin.close()
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1.0)


def _elapsed_ms(started_ns: int) -> int:
    return max(0, (time.monotonic_ns() - started_ns) // 1_000_000)
