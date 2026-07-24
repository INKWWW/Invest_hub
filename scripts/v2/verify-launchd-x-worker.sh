#!/usr/bin/env bash
set -euo pipefail

readonly label="com.investhub.x-worker"
readonly script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly template_path="$script_root/workers/v0/launchd/$label.plist.template"

check_only=false
launch_agents_dir=""

usage() {
  echo "usage: $0 --check-only [--launch-agents-dir ABSOLUTE]" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --check-only) check_only=true; shift ;;
    --launch-agents-dir)
      (($# >= 2)) || usage
      launch_agents_dir="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ "$check_only" == true ]] || usage
[[ -f "$template_path" ]] || { echo "launchd_template_missing" >&2; exit 2; }
grep -Fq "<string>$label</string>" "$template_path" || { echo "launchd_template_label_invalid" >&2; exit 2; }
grep -Fq "<key>V2_REAL_X_ACK</key>" "$template_path" || { echo "launchd_template_x_ack_missing" >&2; exit 2; }
grep -Fq "<key>RunAtLoad</key>" "$template_path" || { echo "launchd_template_run_at_load_missing" >&2; exit 2; }
grep -Fq "<key>KeepAlive</key>" "$template_path" || { echo "launchd_template_keep_alive_missing" >&2; exit 2; }

if [[ -z "$launch_agents_dir" ]]; then
  echo "launchd_check_only_template_valid:$label"
  exit 0
fi

[[ "$launch_agents_dir" == /* && "$launch_agents_dir" != "/" && -d "$launch_agents_dir" ]] || { echo "launch_agents_directory_invalid" >&2; exit 2; }
plist_path="$launch_agents_dir/$label.plist"
if [[ ! -f "$plist_path" ]]; then
  echo "launchd_check_only_plist_absent:$label"
  exit 0
fi

plutil -lint "$plist_path" >/dev/null
if [[ "$(uname)" == "Darwin" ]] && launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
  echo "launchd_check_only_loaded:$label"
else
  echo "launchd_check_only_not_loaded:$label"
fi
