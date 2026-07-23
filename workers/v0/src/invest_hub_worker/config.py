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


_LEGACY_FIELDS = {
    "control_plane_url",
    "source_id",
    "channel_url",
    "profile_ref",
    "opencli_contract_version",
    "parameter_version",
}
_FIELDS = {
    "control_plane_url",
    "source_id",
    "source_type",
    "source_url",
    "profile_ref",
    "opencli_contract_version",
    "parameter_version",
}
_CONFIG_SET_FIELDS = {"control_plane_url", "sources"}


@dataclass(frozen=True)
class LocalWorkerConfig:
    control_plane_url: str
    source_id: str
    source_type: str
    source_url: str
    profile_ref: str
    opencli_contract_version: str
    parameter_version: str
    config_hash: str

    @property
    def channel_url(self) -> str:
        """Compatibility accessor for the Discord-only Active Adapter."""
        if self.source_type != "discord":
            raise ConfigError("channel_url is only defined for a Discord source")
        return self.source_url

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
        if set(value) == _LEGACY_FIELDS:
            value = {**value, "source_type": "discord", "source_url": value["channel_url"]}
            value.pop("channel_url")
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
        source_type = value["source_type"]
        if source_type not in {"discord", "x"}:
            raise ConfigError("source_type must be discord or x")
        source_url = urlparse(value["source_url"])
        if source_url.scheme != "https" or not source_url.netloc:
            raise ConfigError("source_url must be an absolute HTTPS URL")
        host = (source_url.hostname or "").lower()
        if source_type == "discord" and host != "discord.com":
            raise ConfigError("Discord source_url must use discord.com")
        if source_type == "x" and host not in {"x.com", "www.x.com", "twitter.com", "www.twitter.com"}:
            raise ConfigError("X source_url must use x.com or twitter.com")

        canonical = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return cls(config_hash=hashlib.sha256(canonical).hexdigest(), **value)

    def redacted(self) -> dict[str, str]:
        return {
            "config_hash": self.config_hash,
            "source_id": self.source_id,
            "source_type": self.source_type,
            "opencli_contract_version": self.opencli_contract_version,
            "parameter_version": self.parameter_version,
        }


@dataclass(frozen=True)
class LocalWorkerConfigSet:
    control_plane_url: str
    sources: tuple[LocalWorkerConfig, ...]
    config_hash: str

    @classmethod
    def load(cls, path: Path) -> "LocalWorkerConfigSet":
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
    def from_mapping(cls, value: dict[str, Any]) -> "LocalWorkerConfigSet":
        unknown = set(value) - _CONFIG_SET_FIELDS
        missing = _CONFIG_SET_FIELDS - set(value)
        if unknown:
            raise ConfigError(f"unknown worker config fields: {sorted(unknown)}")
        if missing:
            raise ConfigError(f"missing worker config fields: {sorted(missing)}")
        control_plane_url = value["control_plane_url"]
        sources_value = value["sources"]
        if not isinstance(control_plane_url, str) or not control_plane_url.strip():
            raise ConfigError("worker config field must be a non-empty string: control_plane_url")
        if not isinstance(sources_value, list) or not sources_value:
            raise ConfigError("worker config sources must be a non-empty list")

        sources: list[LocalWorkerConfig] = []
        seen_source_ids: set[str] = set()
        for source in sources_value:
            if not isinstance(source, dict):
                raise ConfigError("worker config source must be an object")
            source_config = LocalWorkerConfig.from_mapping({"control_plane_url": control_plane_url, **source})
            if source_config.source_id in seen_source_ids:
                raise ConfigError("worker config source_id values must be unique")
            seen_source_ids.add(source_config.source_id)
            sources.append(source_config)

        canonical = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return cls(
            control_plane_url=control_plane_url,
            sources=tuple(sources),
            config_hash=hashlib.sha256(canonical).hexdigest(),
        )

    def source_for(self, source_id: str) -> LocalWorkerConfig:
        for source in self.sources:
            if source.source_id == source_id:
                return source
        raise ConfigError("task source is not configured for this local Worker")

    def redacted(self) -> dict[str, object]:
        return {
            "config_hash": self.config_hash,
            "sources": [source.redacted() for source in self.sources],
        }
