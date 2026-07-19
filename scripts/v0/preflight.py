from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.errors import ConfigError


def run_preflight(
    config_path: Path,
    *,
    opencli_version: str | None = None,
    network_check: bool = True,
    expected_contract: str = "v0",
) -> dict[str, Any]:
    failures: list[str] = []
    checks: dict[str, str] = {}
    source_id: str | None = None
    contract_version: str | None = None
    try:
        config = LocalWorkerConfig.load(config_path)
    except ConfigError:
        checks["config"] = "fail"
        failures.append("config_invalid")
        return _result(None, None, None, checks, failures)

    source_id = config.source_id
    contract_version = config.opencli_contract_version
    checks["config"] = "pass"

    if contract_version != expected_contract:
        checks["opencli_contract"] = "fail"
        failures.append("opencli_contract")
    else:
        checks["opencli_contract"] = "pass"

    if Path(config.profile_ref).exists():
        checks["profile"] = "pass"
    else:
        checks["profile"] = "fail"
        failures.append("profile_missing")

    resolved_version = opencli_version or _detect_opencli_version()
    if resolved_version:
        checks["opencli"] = "pass"
    else:
        checks["opencli"] = "fail"
        failures.append("opencli_missing")

    if network_check:
        checks["control_plane"] = "pass" if _reachable(config.control_plane_url) else "fail"
        if checks["control_plane"] == "fail":
            failures.append("control_plane_unreachable")
    else:
        checks["control_plane"] = "skipped"

    return _result(source_id, contract_version, resolved_version, checks, failures)


def _result(
    source_id: str | None,
    contract_version: str | None,
    opencli_version: str | None,
    checks: dict[str, str],
    failures: list[str],
) -> dict[str, Any]:
    return {
        "status": "pass" if not failures else "fail",
        "source_id": source_id,
        "opencli_contract_version": contract_version,
        "opencli_version": opencli_version,
        "checks": checks,
        "failures": failures,
    }


def _detect_opencli_version() -> str | None:
    executable = shutil.which("opencli")
    if not executable:
        return None
    try:
        completed = subprocess.run(
            [executable, "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0:
        return None
    first_line = (completed.stdout or completed.stderr).splitlines()
    return first_line[0][:128] if first_line and first_line[0].strip() else None


def _reachable(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return False
    try:
        headers: dict[str, str] = {}
        bypass = os.environ.get("V0_VERCEL_PROTECTION_BYPASS", "").strip()
        if bypass:
            headers["x-vercel-protection-bypass"] = bypass
        request = urllib.request.Request(url, headers=headers, method="HEAD")
        with urllib.request.urlopen(request, timeout=5):
            return True
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="V0 local worker preflight")
    parser.add_argument("--config", default=os.environ.get("V0_WORKER_CONFIG"))
    parser.add_argument("--skip-network", action="store_true")
    args = parser.parse_args()
    if not args.config:
        print(json.dumps({"status": "fail", "failures": ["config_missing"]}, sort_keys=True))
        return 1
    result = run_preflight(Path(args.config), network_check=not args.skip_network)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
