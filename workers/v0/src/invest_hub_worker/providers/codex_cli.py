from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from ..structured import (
    SchemaError,
    parse_structured_output,
    parse_v1_1_chunk_output,
    parse_v1_1_daily_output,
    parse_v2_x_chunk_output,
    parse_v2_x_window_output,
    validate_structured_output,
    validate_v1_1_chunk_output,
    validate_v1_1_daily_output,
)
from .base import ProviderContext, ProviderResponse


DEFAULT_CODEX_TIMEOUT_SECONDS = 240.0
_SAFE_PART = re.compile(r"[^A-Za-z0-9_.-]+")


class CodexCLIProvider:
    """Local-only Codex CLI boundary with bounded process-group cleanup."""

    def __init__(
        self,
        *,
        evidence_dir: Path,
        binary: str = "codex",
        model: str | None = None,
        timeout_seconds: float = DEFAULT_CODEX_TIMEOUT_SECONDS,
        cwd: str | None = None,
        codex_home: str | None = None,
    ) -> None:
        if not binary.strip():
            raise ValueError("binary must be non-empty")
        if model is not None and not model.strip():
            raise ValueError("model must be non-empty when provided")
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        self.evidence_dir = Path(evidence_dir)
        self.binary = binary
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.cwd = cwd
        self.codex_home = codex_home or os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
        self._raw_dir = self.evidence_dir / "raw_responses"
        self._structured_dir = self.evidence_dir / "structured"
        self._diagnostic_dir = self.evidence_dir / "diagnostics"
        for directory in (self.evidence_dir, self._raw_dir, self._structured_dir, self._diagnostic_dir):
            directory.mkdir(parents=True, exist_ok=True)
            try:
                os.chmod(directory, 0o700)
            except OSError:
                pass

    def complete(
        self,
        input_chunk: tuple[Any, ...],
        context: ProviderContext,
    ) -> ProviderResponse:
        started = time.monotonic_ns()
        stem = f"{_safe_part(context.chunk_id)}-attempt-{context.attempt}"
        raw_ref = self._raw_dir / f"{stem}.json"
        parsed_ref = self._structured_dir / f"{stem}.json"
        diagnostic_ref = self._diagnostic_dir / f"{stem}.log"
        stdout_ref = self._diagnostic_dir / f"{stem}.stdout.log"
        timeout_seconds = min(self.timeout_seconds, context.timeout_seconds)

        try:
            with tempfile.TemporaryDirectory(prefix="codex-", dir=str(self.evidence_dir)) as staging:
                output_path = Path(staging) / "last-message.json"
                command = self._command(output_path)
                with (
                    diagnostic_ref.open("w+", encoding="utf-8") as diagnostic_file,
                    stdout_ref.open("w+", encoding="utf-8") as stdout_file,
                ):
                    _restrict_file(diagnostic_ref)
                    _restrict_file(stdout_ref)
                    try:
                        process = subprocess.Popen(
                            command,
                            cwd=self.cwd,
                            stdin=subprocess.PIPE,
                            stdout=stdout_file,
                            stderr=diagnostic_file,
                            start_new_session=True,
                            text=True,
                        )
                    except OSError as exc:
                        _write_text(diagnostic_ref, str(exc))
                        return self._response(
                            status="provider_failure",
                            context=context,
                            started=started,
                            raw_ref=None,
                            parsed_ref=None,
                            failure_class="provider_failure",
                            error_code="provider_failure",
                        )

                    try:
                        process.communicate(input=context.prompt_text, timeout=timeout_seconds)
                    except subprocess.TimeoutExpired as exc:
                        _terminate_process_group(process)
                        diagnostic_file.flush()
                        diagnostic_file.seek(0)
                        diagnostic = diagnostic_file.read().strip()
                        if not diagnostic:
                            diagnostic = f"process exceeded timeout of {exc.timeout} seconds"
                        _write_text(diagnostic_ref, diagnostic)
                        return self._response(
                            status="timeout",
                            context=context,
                            started=started,
                            raw_ref=str(diagnostic_ref),
                            parsed_ref=None,
                            failure_class="timeout",
                            error_code="timeout",
                        )

                    diagnostic_file.flush()
                    diagnostic_file.seek(0)
                    diagnostic = diagnostic_file.read().strip()

                if process.returncode != 0:
                    _write_text(diagnostic_ref, diagnostic)
                    return self._response(
                        status="provider_failure",
                        context=context,
                        started=started,
                        raw_ref=str(diagnostic_ref),
                        parsed_ref=None,
                        failure_class="provider_failure",
                        error_code="provider_failure",
                    )
                try:
                    raw_text = output_path.read_text(encoding="utf-8")
                except FileNotFoundError:
                    return self._response(
                        status="empty_response",
                        context=context,
                        started=started,
                        raw_ref=str(diagnostic_ref),
                        parsed_ref=None,
                        failure_class="empty_response",
                        error_code="empty_response",
                    )
                except (OSError, UnicodeError) as exc:
                    _write_text(diagnostic_ref, str(exc))
                    return self._response(
                        status="invalid_json",
                        context=context,
                        started=started,
                        raw_ref=str(diagnostic_ref),
                        parsed_ref=None,
                        failure_class="invalid_json",
                        error_code="invalid_json",
                    )

                # Raw model output is permitted only in the local protected
                # evidence directory, never in the response or cloud payload.
                _write_text(raw_ref, raw_text)
                try:
                    parsed = self._parse_for_context(raw_text, input_chunk, context)
                except SchemaError as exc:
                    _write_text(diagnostic_ref, str(exc))
                    return self._response(
                        status=exc.code if exc.code in {"invalid_json", "schema_error"} else "schema_error",
                        context=context,
                        started=started,
                        raw_ref=str(raw_ref),
                        parsed_ref=None,
                        failure_class="invalid_json" if exc.code == "invalid_json" else "schema_error",
                        error_code=exc.code,
                    )
                _write_json(parsed_ref, parsed)
                return self._response(
                    status="success",
                    context=context,
                    started=started,
                    raw_ref=str(raw_ref),
                    parsed_ref=str(parsed_ref),
                    parsed_output=parsed,
                )
        except OSError as exc:
            _write_text(diagnostic_ref, str(exc))
            return self._response(
                status="provider_failure",
                context=context,
                started=started,
                raw_ref=None,
                parsed_ref=None,
                failure_class="provider_failure",
                error_code="provider_failure",
            )

    def _command(self, output_path: Path) -> list[str]:
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
        return command

    @staticmethod
    def _parse_for_context(
        raw_text: str,
        input_chunk: tuple[Any, ...],
        context: ProviderContext,
    ) -> dict[str, Any]:
        if context.operation == "legacy_topics":
            parsed = parse_structured_output(raw_text)
            return validate_structured_output(
                parsed,
                set(context.input_message_ids) or _input_ids(input_chunk),
                set(context.unparsed_media_message_ids) or _media_ids(input_chunk),
                set(context.target_author_ids) or None,
            )

        catalog = {
            message_id: (author_id, author_display)
            for message_id, author_id, author_display in context.input_message_authors
        }
        if context.operation == "v1_1_chunk":
            parsed = parse_v1_1_chunk_output(raw_text)
            return validate_v1_1_chunk_output(
                parsed,
                catalog,
                set(context.unparsed_media_message_ids),
            )

        if context.operation == "v2_x_chunk":
            return parse_v2_x_chunk_output(raw_text, set(context.input_message_ids), set(context.visible_context_post_ids))
        if context.operation == "v2_x_window":
            return parse_v2_x_window_output(raw_text, set(context.input_message_ids))

        parsed = parse_v1_1_daily_output(raw_text)
        return validate_v1_1_daily_output(
            parsed,
            catalog,
            dict(context.configured_author_profiles),
            fact_units=tuple(item for item in input_chunk if isinstance(item, dict)),
            expected_natural_date=str(context.expected_natural_date),
            expected_as_of=str(context.expected_as_of),
            unparsed_media_ids=set(context.unparsed_media_message_ids),
        )

    def _response(
        self,
        *,
        status: str,
        context: ProviderContext,
        started: int,
        raw_ref: str | None,
        parsed_ref: str | None,
        parsed_output: dict[str, Any] | None = None,
        failure_class: str | None = None,
        error_code: str | None = None,
    ) -> ProviderResponse:
        return ProviderResponse(
            status=status,
            provider="codex_cli",
            model_reported=self.model,
            prompt_version=context.prompt_version,
            elapsed_ms=max(0, (time.monotonic_ns() - started) // 1_000_000),
            attempt=context.attempt,
            raw_ref=raw_ref,
            parsed_output_ref=parsed_ref,
            parsed_output=parsed_output,
            failure_class=failure_class,
            error_code=error_code,
        )


def _safe_part(value: str) -> str:
    cleaned = _SAFE_PART.sub("_", value).strip("._")
    return cleaned[:96] or "chunk"


def _write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def _write_json(path: Path, value: object) -> None:
    _write_text(path, json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n")


def _restrict_file(path: Path) -> None:
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def _input_ids(input_chunk: tuple[Any, ...]) -> set[str]:
    ids: set[str] = set()
    for item in input_chunk:
        if isinstance(item, str):
            ids.add(item)
        elif isinstance(item, dict) and item.get("external_message_id"):
            ids.add(str(item["external_message_id"]))
        elif getattr(item, "external_message_id", None):
            ids.add(str(item.external_message_id))
    return ids


def _media_ids(input_chunk: tuple[Any, ...]) -> set[str]:
    media: set[str] = set()
    for item in input_chunk:
        if isinstance(item, dict):
            attachments = item.get("attachments")
            external_id = item.get("external_message_id")
        else:
            attachments = getattr(item, "attachments", None)
            external_id = getattr(item, "external_message_id", None)
        if external_id and attachments:
            media.add(str(external_id))
    return media


def _terminate_process_group(process: Any) -> None:
    """Terminate a process group with bounded cleanup after timeout."""

    stdin = getattr(process, "stdin", None)
    if stdin is not None:
        try:
            stdin.close()
        except (OSError, ValueError):
            pass
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
        try:
            process.kill()
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            pass
