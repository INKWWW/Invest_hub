from __future__ import annotations

import subprocess
from dataclasses import dataclass


class PreflightError(RuntimeError):
    """Raised when the local OpenCLI prerequisite cannot be verified."""


@dataclass(frozen=True)
class PreflightResult:
    executable: str
    version: str


def check_opencli(executable: str) -> PreflightResult:
    try:
        completed = subprocess.run(
            [executable, "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError as exc:
        raise PreflightError("executable not found") from exc
    except subprocess.TimeoutExpired as exc:
        raise PreflightError("version check timed out") from exc

    if completed.returncode != 0:
        detail = completed.stderr.strip() or "unknown version error"
        raise PreflightError(f"version check failed: {detail}")

    version = completed.stdout.strip()
    if not version:
        raise PreflightError("version output is empty")
    return PreflightResult(executable=executable, version=version)
