#!/usr/bin/env bash
set -euo pipefail

mode="deterministic"
provider="mock"
chunk_size="100"
max_concurrency="5"
timeout_seconds="240"
max_attempts="3"
python_bin="${V0_PYTHON_BIN:-python3}"
worker_config=""
credential_path=""
opencli_contract=""
prompt_path=""
evidence_dir=""
enrolment_code_file=""
opencli_executable=""

if ! "$python_bin" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
  echo "python_requires_3_11_or_newer" >&2
  exit 2
fi

while (($# > 0)); do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --provider) provider="$2"; shift 2 ;;
    --chunk-size) chunk_size="$2"; shift 2 ;;
    --max-concurrency) max_concurrency="$2"; shift 2 ;;
    --timeout-seconds) timeout_seconds="$2"; shift 2 ;;
    --max-attempts) max_attempts="$2"; shift 2 ;;
    --worker-config) worker_config="$2"; shift 2 ;;
    --credential) credential_path="$2"; shift 2 ;;
    --opencli-contract) opencli_contract="$2"; shift 2 ;;
    --prompt-path) prompt_path="$2"; shift 2 ;;
    --evidence-dir) evidence_dir="$2"; shift 2 ;;
    --enrolment-code-file) enrolment_code_file="$2"; shift 2 ;;
    --opencli-executable) opencli_executable="$2"; shift 2 ;;
    *) echo "unknown_argument" >&2; exit 2 ;;
  esac
done

if [[ "$mode" == "deterministic" ]]; then
  if [[ "$provider" != "mock" ]]; then
    echo "deterministic_mode_requires_mock" >&2
    exit 2
  fi
  if [[ "$chunk_size" != "100" || "$max_concurrency" != "5" || "$timeout_seconds" != "240" || "$max_attempts" != "3" ]]; then
    echo "v0_parameters_must_be_100_5_240_3" >&2
    exit 2
  fi
  PYTHONPATH="workers/v0/src:tests/e2e/v0" "$python_bin" -m unittest discover -s tests/e2e/v0 -p 'test_*.py' -v
  exit 0
fi

if [[ "$mode" == "real-discord" ]]; then
  if [[ "${V0_REAL_DISCORD_ACK:-}" != "authorized" ]]; then
    echo "real_discord_requires_explicit_authorization" >&2
    exit 2
  fi
  if [[ "$provider" != "codex" ]]; then
    echo "real_discord_requires_codex_provider" >&2
    exit 2
  fi
  if [[ "$chunk_size" != "100" || "$max_concurrency" != "5" || "$timeout_seconds" != "240" || "$max_attempts" != "3" ]]; then
    echo "v0_parameters_must_be_100_5_240_3" >&2
    exit 2
  fi
  if [[ -z "$worker_config" || -z "$credential_path" || -z "$opencli_contract" || -z "$prompt_path" || -z "$evidence_dir" ]]; then
    echo "real_discord_runtime_arguments_required" >&2
    exit 2
  fi
  PYTHONPATH="workers/v0/src:scripts/v0" "$python_bin" scripts/v0/preflight.py --config "$worker_config"
  command=("$python_bin" -m invest_hub_worker.cli run-once --config "$worker_config" --credential "$credential_path" --opencli-contract "$opencli_contract" --prompt-path "$prompt_path" --evidence-dir "$evidence_dir")
  if [[ -n "$enrolment_code_file" ]]; then
    command+=(--enrolment-code-file "$enrolment_code_file")
  fi
  if [[ -n "$opencli_executable" ]]; then
    command+=(--opencli-executable "$opencli_executable")
  fi
  PYTHONPATH="workers/v0/src" "${command[@]}"
  exit $?
fi

echo "unsupported_mode" >&2
exit 2
