from __future__ import annotations

import hashlib
import json
import os
import stat
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from .errors import ConfigError


_FIELDS = {
    "control_plane_url",
    "source_id",
    "channel_url",
    "profile_ref",
    "opencli_contract_version",
    "parameter_version",
}


@dataclass(frozen=True)
class LocalWorkerConfig:
    control_plane_url: str
    source_id: str
    channel_url: str
    profile_ref: str
    opencli_contract_version: str
    parameter_version: str
    config_hash: str

    @classmethod
    def load(cls, path: Path) -> "LocalWorkerConfig":
        try:
            mode = stat.S_IMODE(path.stat().st_mode)
        except OSError as exc:
            raise ConfigError(f"cannot stat worker config: {path}") from exc
        if mode & 0o077:
            raise ConfigError("worker config must be owner-only (0600 or stricter)")

        try:
            if path.suffix.lower() == ".toml":
                value = tomllib.loads(path.read_text(encoding="utf-8"))
            else:
                value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError, tomllib.TOMLDecodeError) as exc:
            raise ConfigError("worker config is not valid JSON/TOML") from exc
        if not isinstance(value, dict):
            raise ConfigError("worker config must be an object")
        return cls.from_mapping(value)

    @classmethod
    def from_mapping(cls, value: dict[str, Any]) -> "LocalWorkerConfig":
        unknown = set(value) - _FIELDS
        missing = _FIELDS - set(value)
        if unknown:
            raise ConfigError(f"unknown worker config fields: {sorted(unknown)}")
        if missing:
            raise ConfigError(f"missing worker config fields: {sorted(missing)}")
        for field in _FIELDS:
            if not isinstance(value[field], str) or not value[field].strip():
                raise ConfigError(f"worker config field must be a non-empty string: {field}")

        control = urlparse(value["control_plane_url"])
        if control.scheme not in {"https", "http"} or not control.netloc:
            raise ConfigError("control_plane_url must be an absolute HTTP(S) URL")
        if control.scheme == "http" and control.hostname not in {"127.0.0.1", "localhost", "::1"}:
            raise ConfigError("control_plane_url must use HTTPS outside localhost")
        channel = urlparse(value["channel_url"])
        if channel.scheme != "https" or not channel.netloc:
            raise ConfigError("channel_url must be an absolute HTTPS URL")

        canonical = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return cls(config_hash=hashlib.sha256(canonical).hexdigest(), **value)

    def redacted(self) -> dict[str, str]:
        return {
            "config_hash": self.config_hash,
            "source_id": self.source_id,
            "opencli_contract_version": self.opencli_contract_version,
            "parameter_version": self.parameter_version,
        }
