#!/usr/bin/env bash
set -euo pipefail

mode="deterministic"
provider="mock"
python_bin="${V1_PYTHON_BIN:-python3}"
worker_config=""
credential_path=""
opencli_contract=""
prompt_path=""
evidence_dir=""
opencli_executable=""

while (($# > 0)); do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --provider) provider="$2"; shift 2 ;;
    --worker-config) worker_config="$2"; shift 2 ;;
    --credential) credential_path="$2"; shift 2 ;;
    --opencli-contract) opencli_contract="$2"; shift 2 ;;
    --prompt-path) prompt_path="$2"; shift 2 ;;
    --evidence-dir) evidence_dir="$2"; shift 2 ;;
    --opencli-executable) opencli_executable="$2"; shift 2 ;;
    *) echo "unknown_argument" >&2; exit 2 ;;
  esac
done

if ! "$python_bin" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
  echo "python_requires_3_11_or_newer" >&2
  exit 2
fi

if [[ "$mode" == "deterministic" ]]; then
  if [[ "$provider" != "mock" ]]; then
    echo "deterministic_mode_requires_mock" >&2
    exit 2
  fi
  PYTHONPATH="workers/v0/src:tests/e2e/v1" "$python_bin" -m unittest discover -s tests/e2e/v1 -p 'test_*.py' -v
  exit 0
fi

if [[ "$mode" != "real-discord" ]]; then
  echo "unsupported_mode" >&2
  exit 2
fi
if [[ "${V1_REAL_DISCORD_ACK:-}" != "authorized" ]]; then
  echo "real_discord_requires_explicit_authorization" >&2
  exit 2
fi
if [[ "$provider" != "codex" ]]; then
  echo "real_discord_requires_codex_provider" >&2
  exit 2
fi
if [[ -z "$worker_config" || -z "$credential_path" || -z "$opencli_contract" || -z "$prompt_path" || -z "$evidence_dir" ]]; then
  echo "real_discord_runtime_arguments_required" >&2
  exit 2
fi

if ! PYTHONPATH="workers/v0/src:scripts/v1" "$python_bin" -c '
from pathlib import Path
from preflight import validate_real_discord_inputs
import sys
ok, _failures = validate_real_discord_inputs(
    config_path=Path(sys.argv[1]), credential_path=Path(sys.argv[2]), prompt_path=Path(sys.argv[3]),
    opencli_contract_path=Path(sys.argv[4]), evidence_dir=Path(sys.argv[5]),
)
raise SystemExit(0 if ok else 1)
' "$worker_config" "$credential_path" "$prompt_path" "$opencli_contract" "$evidence_dir"; then
  echo "real_discord_preflight_failed" >&2
  exit 2
fi

command=("$python_bin" -m invest_hub_worker.cli run-scheduled --once --config "$worker_config" --credential "$credential_path" --opencli-contract "$opencli_contract" --prompt-path "$prompt_path" --evidence-dir "$evidence_dir")
if [[ -n "$opencli_executable" ]]; then
  command+=(--opencli-executable "$opencli_executable")
fi

if ! PYTHONPATH="workers/v0/src" V1_REAL_DISCORD_ACK=authorized "${command[@]}" >> "$evidence_dir/v1-e2e.log" 2>&1; then
  echo "real_discord_run_failed" >&2
  exit 1
fi
echo "real_discord_completed"
