#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
opencli_executable=""
source_config=""
credential=""
source_id=""
evidence_dir=""
worker_name="v2-x-identity-worker"
approved=false

fail() {
  printf '%s\n' "$1" >&2
  exit 2
}

require_option_value() {
  (($# >= 2)) || fail "identity_resolution_argument_required"
}

while (($# > 0)); do
  case "$1" in
    --opencli-executable)
      require_option_value "$@"
      opencli_executable="$2"
      shift 2
      ;;
    --source-config)
      require_option_value "$@"
      source_config="$2"
      shift 2
      ;;
    --credential)
      require_option_value "$@"
      credential="$2"
      shift 2
      ;;
    --source-id)
      require_option_value "$@"
      source_id="$2"
      shift 2
      ;;
    --evidence-dir)
      require_option_value "$@"
      evidence_dir="$2"
      shift 2
      ;;
    --worker-name)
      require_option_value "$@"
      worker_name="$2"
      shift 2
      ;;
    --approve-identity-resolution)
      approved=true
      shift
      ;;
    *)
      fail "identity_resolution_unknown_argument"
      ;;
  esac
done

if [[ "$approved" != true ]]; then
  fail "identity_resolution_approval_required: --approve-identity-resolution"
fi
for value in "$opencli_executable" "$source_config" "$credential" "$source_id" "$evidence_dir"; do
  [[ -n "$value" ]] || fail "identity_resolution_private_runtime_inputs_required"
done
if [[ "${V2_REAL_X_ACK:-}" != "authorized" ]]; then
  fail "identity_resolution_ack_required: V2_REAL_X_ACK=authorized"
fi
if [[ -z "${V2_PYTHON_BIN:-}" || ! -x "$V2_PYTHON_BIN" ]]; then
  fail "identity_resolution_python_required: executable V2_PYTHON_BIN"
fi

expected_opencli="$repo_root/.runtime/v2/opencli-collection/current/bin/opencli-v2-collection"
if [[ "$opencli_executable" != "$expected_opencli" ]]; then
  fail "identity_resolution_controlled_opencli_required: dedicated local Collection executable"
fi
if [[ -L "$opencli_executable" ]]; then
  fail "identity_resolution_controlled_opencli_required: dedicated local Collection executable"
fi

mode_for() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

owner_for() {
  stat -f '%u' "$1" 2>/dev/null || stat -c '%u' "$1" 2>/dev/null
}

require_secure_path_component() {
  local component="$1"
  local leaf="$2"
  [[ -L "$component" ]] && fail "identity_resolution_owner_only_path_required"
  [[ -e "$component" ]] || fail "identity_resolution_private_path_required"
  [[ "$(owner_for "$component")" == "$(id -u)" ]] || fail "identity_resolution_owner_only_path_required"
  local mode
  mode="$(mode_for "$component")"
  if [[ "$leaf" == true ]]; then
    (( (8#$mode & 8#077) == 0 )) || fail "identity_resolution_owner_only_path_required"
  else
    (( (8#$mode & 8#022) == 0 )) || fail "identity_resolution_owner_only_path_required"
  fi
}

require_private_ignored_path() {
  local value="$1"
  local kind="$2"
  [[ "$value" == /* ]] || fail "identity_resolution_private_path_required"
  case "$value" in
    "$repo_root"/*) ;;
    *) fail "identity_resolution_private_path_required" ;;
  esac
  local component="$value"
  local leaf=true
  while true; do
    require_secure_path_component "$component" "$leaf"
    [[ "$component" == "$repo_root" ]] && break
    component="$(dirname -- "$component")"
    leaf=false
  done
  local absolute
  absolute="$(cd -P -- "$(dirname -- "$value")" && pwd -P)/$(basename -- "$value")"
  [[ "$absolute" == "$value" ]] || fail "identity_resolution_private_path_required"
  git -C "$repo_root" check-ignore -q -- "$absolute" || fail "identity_resolution_private_path_not_ignored"
  if [[ "$kind" == "file" ]]; then
    [[ -f "$absolute" ]] || fail "identity_resolution_private_file_required"
  else
    [[ -d "$absolute" ]] || fail "identity_resolution_private_directory_required"
  fi
}

require_private_ignored_path "$source_config" file
require_private_ignored_path "$credential" file
require_private_ignored_path "$evidence_dir" directory

bash "$repo_root/scripts/v2/verify-local-opencli-collection.sh"

V2_REAL_X_ACK=authorized PYTHONPATH="$repo_root/workers/v0/src" "$V2_PYTHON_BIN" \
  -m invest_hub_worker.cli resolve-x-identity \
  --config "$source_config" \
  --credential "$credential" \
  --source-id "$source_id" \
  --evidence-dir "$evidence_dir" \
  --opencli-executable "$opencli_executable" \
  --worker-name "$worker_name"
