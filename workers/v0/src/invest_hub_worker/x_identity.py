from __future__ import annotations

import json
import re
import subprocess
from collections.abc import Callable, Mapping
from typing import Any, Protocol
from urllib.parse import urlsplit

from .config import LocalWorkerConfig
from .errors import WorkerError


_HANDLE = re.compile(r"^[a-z0-9_]{1,15}$")


class IdentityResolutionError(WorkerError):
    """A safe, machine-readable local X identity-resolution failure."""


class IdentityProtocol(Protocol):
    def resolve_x_source_identity(self, source_id: str, parameter_version: str, account_id: str) -> dict[str, object]: ...


Runner = Callable[..., subprocess.CompletedProcess[str]]


def normalize_x_handle(value: str) -> str:
    if not isinstance(value, str):
        raise IdentityResolutionError("invalid_x_identity")
    normalized = value.strip()
    if normalized.startswith("@"):
        normalized = normalized[1:]
    normalized = normalized.lower()
    if not _HANDLE.fullmatch(normalized):
        raise IdentityResolutionError("invalid_x_identity")
    return normalized


class OpenCLIProfileInvoker:
    """The deliberately narrow local boundary for profile identity verification."""

    def __init__(self, executable: str, *, runner: Runner = subprocess.run) -> None:
        self.executable = executable
        self.runner = runner

    def resolve(self, requested_handle: str) -> str:
        requested = normalize_x_handle(requested_handle)
        command = [
            self.executable,
            "twitter",
            "profile",
            requested,
            "--site-session",
            "persistent",
            "-f",
            "json",
        ]
        try:
            result = self.runner(command, capture_output=True, text=True, timeout=60, check=False)
        except subprocess.TimeoutExpired as exc:
            raise IdentityResolutionError("profile_timeout") from exc
        except (OSError, ValueError) as exc:
            raise IdentityResolutionError("profile_invocation_failed") from exc
        if result.returncode != 0:
            raise IdentityResolutionError("profile_invocation_failed")
        row = _single_profile_row(result.stdout)
        try:
            observed = normalize_x_handle(row.get("screen_name", ""))
        except IdentityResolutionError as exc:
            raise IdentityResolutionError("invalid_profile_response") from exc
        if observed != requested:
            raise IdentityResolutionError("identity_mismatch")
        return observed


def resolve_configured_x_identity(
    config: LocalWorkerConfig,
    protocol: IdentityProtocol,
    executable: str,
    *,
    invoker: OpenCLIProfileInvoker | None = None,
) -> dict[str, object]:
    if config.source_type != "x":
        raise IdentityResolutionError("source_not_x")
    requested = _requested_handle_from_source_url(config.source_url)
    verified = (invoker or OpenCLIProfileInvoker(executable)).resolve(requested)
    response = protocol.resolve_x_source_identity(config.source_id, config.parameter_version, verified)
    return _safe_resolution_response(response, config.parameter_version)


def _requested_handle_from_source_url(source_url: str) -> str:
    parsed = urlsplit(source_url)
    path_parts = [part for part in parsed.path.split("/") if part]
    if len(path_parts) != 1:
        raise IdentityResolutionError("invalid_x_identity")
    return normalize_x_handle(path_parts[0])


def _single_profile_row(value: object) -> Mapping[str, object]:
    if not isinstance(value, str):
        raise IdentityResolutionError("invalid_profile_response")
    try:
        parsed = json.loads(value)
    except (TypeError, ValueError) as exc:
        raise IdentityResolutionError("invalid_profile_response") from exc
    if not isinstance(parsed, list) or len(parsed) != 1 or not isinstance(parsed[0], dict):
        raise IdentityResolutionError("invalid_profile_response")
    return parsed[0]


def _safe_resolution_response(value: object, parameter_version: str) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != {"resolution_status", "parameter_version", "idempotent"}:
        raise IdentityResolutionError("invalid_identity_resolution_response")
    if value.get("resolution_status") != "resolved" or value.get("parameter_version") != parameter_version or not isinstance(value.get("idempotent"), bool):
        raise IdentityResolutionError("invalid_identity_resolution_response")
    return {
        "resolution_status": "resolved",
        "parameter_version": parameter_version,
        "idempotent": value["idempotent"],
    }
