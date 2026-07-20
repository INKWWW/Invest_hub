from __future__ import annotations

import os
import stat
from pathlib import Path

from invest_hub_worker.config import ConfigError, LocalWorkerConfigSet
from invest_hub_worker.protocol import CredentialStore, ProtocolError


def validate_real_discord_inputs(
    *,
    config_path: Path,
    credential_path: Path,
    prompt_path: Path,
    opencli_contract_path: Path,
    evidence_dir: Path,
) -> tuple[bool, tuple[str, ...]]:
    failures: list[str] = []
    try:
        config = LocalWorkerConfigSet.load(config_path)
        if len(config.sources) < 2:
            failures.append("multi_source_config_required")
        if any(source.opencli_contract_version != "v0" for source in config.sources):
            failures.append("opencli_contract_version_mismatch")
    except ConfigError:
        failures.append("worker_config_invalid")

    for path, label in ((prompt_path, "prompt"), (evidence_dir, "evidence_dir")):
        if not _owner_only(path):
            failures.append(f"{label}_not_owner_only")
    if not opencli_contract_path.is_file():
        failures.append("opencli_contract_missing")
    try:
        if CredentialStore(credential_path).load() is None:
            failures.append("worker_credential_missing")
    except ProtocolError:
        failures.append("worker_credential_invalid")
    return not failures, tuple(sorted(set(failures)))


def _owner_only(path: Path) -> bool:
    try:
        return path.exists() and not (stat.S_IMODE(path.stat().st_mode) & 0o077)
    except OSError:
        return False
