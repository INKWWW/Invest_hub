#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
opencli_executable=""
source_config=""
credential=""
opencli_contract=""
prompt_path=""
evidence_dir=""
worker_name="v2-local-collection-real-e2e"
approved=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --opencli-executable) opencli_executable="$2"; shift 2 ;;
    --source-config) source_config="$2"; shift 2 ;;
    --credential) credential="$2"; shift 2 ;;
    --opencli-contract) opencli_contract="$2"; shift 2 ;;
    --prompt-path) prompt_path="$2"; shift 2 ;;
    --evidence-dir) evidence_dir="$2"; shift 2 ;;
    --worker-name) worker_name="$2"; shift 2 ;;
    --approve-real-persistence) approved=true; shift ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ "$approved" != true ]]; then
  printf 'refusing real persistence without --approve-real-persistence\n' >&2
  exit 2
fi

for value in "$opencli_executable" "$source_config" "$credential" "$opencli_contract" "$prompt_path" "$evidence_dir"; do
  if [[ -z "$value" ]]; then
    printf 'real E2E requires all private runtime inputs\n' >&2
    exit 2
  fi
done
if [[ "${V2_REAL_X_ACK:-}" != "authorized" ]]; then
  printf 'real E2E requires V2_REAL_X_ACK=authorized\n' >&2
  exit 2
fi
if [[ -z "${V2_PYTHON_BIN:-}" || ! -x "$V2_PYTHON_BIN" ]]; then
  printf 'real E2E requires an executable V2_PYTHON_BIN\n' >&2
  exit 2
fi

expected_opencli="$repo_root/.runtime/v2/opencli-collection/current/bin/opencli-v2-collection"
if [[ "$(cd -- "$(dirname -- "$opencli_executable")" && pwd)/$(basename -- "$opencli_executable")" != "$expected_opencli" ]]; then
  printf 'real E2E requires the dedicated local Collection executable\n' >&2
  exit 2
fi
bash "$repo_root/scripts/v2/verify-local-opencli-collection.sh"

require_private_ignored_path() {
  local value="$1"
  local absolute
  absolute="$(cd -- "$(dirname -- "$value")" && pwd)/$(basename -- "$value")"
  case "$absolute" in
    "$repo_root"/.runtime/*) ;;
    *) printf 'real E2E private inputs must be under .runtime/\n' >&2; exit 2 ;;
  esac
  if git -C "$repo_root" check-ignore -q -- "$absolute"; then
    return
  fi
  printf 'real E2E private input is not Git-ignored\n' >&2
  exit 2
}

require_private_ignored_path "$source_config"
require_private_ignored_path "$credential"
require_private_ignored_path "$opencli_contract"
require_private_ignored_path "$prompt_path"
require_private_ignored_path "$evidence_dir"

V2_REAL_X_ACK=authorized PYTHONPATH="$repo_root/workers/v0/src" "$V2_PYTHON_BIN" -m invest_hub_worker.cli run-once \
  --config "$source_config" \
  --credential "$credential" \
  --opencli-contract "$opencli_contract" \
  --prompt-path "$prompt_path" \
  --evidence-dir "$evidence_dir" \
  --opencli-executable "$opencli_executable" \
  --worker-name "$worker_name"
