#!/usr/bin/env bash
set -euo pipefail

readonly label="com.investhub.discord-worker"

action="check"
launch_agents_dir=""

usage() {
  echo "usage: $0 --check-only|--uninstall --launch-agents-dir ABSOLUTE" >&2
  exit 2
}

fail() {
  echo "$1" >&2
  exit 2
}

mode_for() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

owner_for() {
  stat -f '%u' "$1" 2>/dev/null || stat -c '%u' "$1" 2>/dev/null
}

require_own_plist() {
  [[ "$(owner_for "$plist_path")" == "$(id -u)" ]] || fail "launchd_plist_not_owned"
  local mode
  mode="$(mode_for "$plist_path")"
  (( (8#$mode & 8#077) == 0 )) || fail "launchd_plist_owner_only_required"
}

while (($# > 0)); do
  case "$1" in
    --check-only) action="check"; shift ;;
    --uninstall) action="uninstall"; shift ;;
    --launch-agents-dir)
      (($# >= 2)) || usage
      launch_agents_dir="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ -n "$launch_agents_dir" && "$launch_agents_dir" == /* && "$launch_agents_dir" != "/" ]] || usage
[[ -d "$launch_agents_dir" ]] || fail "launch_agents_directory_missing"
plist_path="$launch_agents_dir/$label.plist"

if [[ "$action" == "check" ]]; then
  if [[ -f "$plist_path" ]]; then
    require_own_plist
    plutil -lint "$plist_path" >/dev/null
    echo "launchd_plist_present:$label"
  else
    echo "launchd_plist_absent:$label"
  fi
  exit 0
fi

[[ "$(uname)" == "Darwin" ]] || fail "launchd_requires_macos"
if [[ -f "$plist_path" ]]; then
  require_own_plist
  launchctl bootout "gui/$(id -u)" "$plist_path" >/dev/null 2>&1 || true
  rm -f -- "$plist_path"
fi
echo "launchd_uninstalled:$label"
