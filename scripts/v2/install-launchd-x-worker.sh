#!/usr/bin/env bash
set -euo pipefail

readonly label="com.investhub.x-worker"
readonly script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly template_path="$script_root/workers/v0/launchd/$label.plist.template"

action="check"
project_root=""
worker_config=""
credential=""
opencli_contract=""
prompt_path=""
evidence_dir=""
opencli_executable=""
launch_agents_dir=""
log_dir=""

usage() {
  echo "usage: $0 --check-only|--install --project-root ABSOLUTE --worker-config ABSOLUTE --credential ABSOLUTE --opencli-contract ABSOLUTE --prompt-path ABSOLUTE --evidence-dir ABSOLUTE --opencli-executable ABSOLUTE --launch-agents-dir ABSOLUTE --log-dir ABSOLUTE" >&2
  exit 2
}

fail() {
  echo "$1" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --check-only) action="check"; shift ;;
    --install) action="install"; shift ;;
    --project-root|--worker-config|--credential|--opencli-contract|--prompt-path|--evidence-dir|--opencli-executable|--launch-agents-dir|--log-dir)
      (($# >= 2)) || usage
      case "$1" in
        --project-root) project_root="$2" ;;
        --worker-config) worker_config="$2" ;;
        --credential) credential="$2" ;;
        --opencli-contract) opencli_contract="$2" ;;
        --prompt-path) prompt_path="$2" ;;
        --evidence-dir) evidence_dir="$2" ;;
        --opencli-executable) opencli_executable="$2" ;;
        --launch-agents-dir) launch_agents_dir="$2" ;;
        --log-dir) log_dir="$2" ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

require_absolute() {
  local value="$1"
  [[ "$value" == /* && "$value" != "/" ]] || fail "absolute_path_required"
}

mode_for() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

owner_for() {
  stat -f '%u' "$1" 2>/dev/null || stat -c '%u' "$1" 2>/dev/null
}

require_owner_only_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "owner_only_file_missing"
  [[ "$(owner_for "$path")" == "$(id -u)" ]] || fail "owner_only_file_not_owned"
  local mode
  mode="$(mode_for "$path")"
  (( (8#$mode & 8#077) == 0 )) || fail "owner_only_file_permissions_required"
}

require_owner_only_dir() {
  local path="$1"
  [[ -d "$path" ]] || fail "owner_only_directory_missing"
  [[ "$(owner_for "$path")" == "$(id -u)" ]] || fail "owner_only_directory_not_owned"
  local mode
  mode="$(mode_for "$path")"
  (( (8#$mode & 8#077) == 0 )) || fail "owner_only_directory_permissions_required"
}

require_render_safe_path() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *'&'* && "$value" != *'<'* && "$value" != *'>'* && "$value" != *'|'* && "$value" != *'\\'* ]] || fail "unsupported_path_character"
}

for value in "$project_root" "$worker_config" "$credential" "$opencli_contract" "$prompt_path" "$evidence_dir" "$opencli_executable" "$launch_agents_dir" "$log_dir"; do
  [[ -n "$value" ]] || usage
  require_absolute "$value"
  require_render_safe_path "$value"
done

[[ -d "$project_root" ]] || fail "project_root_missing"
python_bin="$project_root/workers/v0/.venv/bin/python"
[[ -x "$python_bin" ]] || fail "worker_python_missing"
[[ -f "$template_path" ]] || fail "launchd_template_missing"
grep -Fq "<string>$label</string>" "$template_path" || fail "launchd_template_label_invalid"
grep -Fq "<key>V2_REAL_X_ACK</key>" "$template_path" || fail "launchd_template_x_ack_missing"
require_owner_only_file "$worker_config"
require_owner_only_file "$credential"
require_owner_only_file "$prompt_path"
[[ -f "$opencli_contract" ]] || fail "opencli_contract_missing"
require_owner_only_dir "$evidence_dir"
[[ -d "$launch_agents_dir" ]] || fail "launch_agents_directory_missing"

if [[ -d "$log_dir" ]]; then
  require_owner_only_dir "$log_dir"
else
  require_owner_only_dir "$(dirname "$log_dir")"
fi

readonly expected_opencli="$project_root/.runtime/v2/opencli-collection/current/bin/opencli-v2-collection"
[[ "$opencli_executable" == "$expected_opencli" && -x "$opencli_executable" ]] || fail "controlled_x_opencli_required"

PYTHONPATH="$project_root/workers/v0/src" "$python_bin" - "$worker_config" <<'PY'
import sys
from pathlib import Path
from invest_hub_worker.config import ConfigError, LocalWorkerConfigSet

try:
    config = LocalWorkerConfigSet.load(Path(sys.argv[1]))
except ConfigError:
    raise SystemExit("x_worker_config_invalid")
if any(source.source_type != "x" for source in config.sources):
    raise SystemExit("x_worker_config_must_be_x_only")
PY

if [[ "$action" == "check" ]]; then
  echo "launchd_check_ready:$label"
  exit 0
fi

[[ "$(uname)" == "Darwin" ]] || fail "launchd_requires_macos"
plist_path="$launch_agents_dir/$label.plist"
[[ ! -e "$plist_path" ]] || fail "launchd_plist_already_exists"

if [[ ! -d "$log_dir" ]]; then
  (umask 077 && mkdir "$log_dir")
fi

(umask 077 && sed \
  -e "s|__PROJECT_ROOT__|$project_root|g" \
  -e "s|__PYTHON_BIN__|$python_bin|g" \
  -e "s|__WORKER_CONFIG__|$worker_config|g" \
  -e "s|__CREDENTIAL__|$credential|g" \
  -e "s|__OPENCLI_CONTRACT__|$opencli_contract|g" \
  -e "s|__PROMPT_PATH__|$prompt_path|g" \
  -e "s|__EVIDENCE_DIR__|$evidence_dir|g" \
  -e "s|__OPENCLI_EXECUTABLE__|$opencli_executable|g" \
  -e "s|__LOG_DIR__|$log_dir|g" \
  "$template_path" > "$plist_path")
chmod 600 "$plist_path"
plutil -lint "$plist_path" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$plist_path"
echo "launchd_installed:$label"
