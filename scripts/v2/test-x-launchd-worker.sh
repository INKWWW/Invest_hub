#!/usr/bin/env bash
set -euo pipefail

readonly project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly installer="$project_root/scripts/v2/install-launchd-x-worker.sh"
readonly controlled_opencli="$project_root/.runtime/v2/opencli-collection/current/bin/opencli-v2-collection"
temp_root="$(mktemp -d /private/tmp/invest-hub-x-launchd-test.XXXXXX)"
trap 'rm -rf -- "$temp_root"' EXIT

mkdir -p "$temp_root/LaunchAgents" "$temp_root/log-parent" "$temp_root/evidence"
chmod 700 "$temp_root" "$temp_root/LaunchAgents" "$temp_root/log-parent" "$temp_root/evidence"

config="$temp_root/x-worker.json"
credential="$temp_root/credential.json"
prompt="$temp_root/prompt.md"
contract="$temp_root/contract.json"

printf '%s\n' '{"control_plane_url":"https://example.invalid","sources":[{"source_id":"fixture-x-source","source_type":"x","source_url":"https://x.com/fixture","profile_ref":"fixture","opencli_contract_version":"v2","parameter_version":"fixture-v1"}]}' > "$config"
printf '%s\n' '{}' > "$credential"
printf '%s\n' 'fixture prompt' > "$prompt"
printf '%s\n' '{}' > "$contract"
chmod 600 "$config" "$credential" "$prompt" "$contract"

ready_output="$(bash "$installer" --check-only \
  --project-root "$project_root" \
  --worker-config "$config" \
  --credential "$credential" \
  --opencli-contract "$contract" \
  --prompt-path "$prompt" \
  --evidence-dir "$temp_root/evidence" \
  --opencli-executable "$controlled_opencli" \
  --launch-agents-dir "$temp_root/LaunchAgents" \
  --log-dir "$temp_root/log-parent/x-worker")"
[[ "$ready_output" == "launchd_check_ready:com.investhub.x-worker" ]]

mixed_config="$temp_root/mixed-worker.json"
printf '%s\n' '{"control_plane_url":"https://example.invalid","sources":[{"source_id":"fixture-x-source","source_type":"x","source_url":"https://x.com/fixture","profile_ref":"fixture","opencli_contract_version":"v2","parameter_version":"fixture-v1"},{"source_id":"fixture-discord-source","source_type":"discord","source_url":"https://discord.com/channels/1/2","profile_ref":"fixture","opencli_contract_version":"v1","parameter_version":"fixture-v1"}]}' > "$mixed_config"
chmod 600 "$mixed_config"

set +e
mixed_output="$(bash "$installer" --check-only \
  --project-root "$project_root" \
  --worker-config "$mixed_config" \
  --credential "$credential" \
  --opencli-contract "$contract" \
  --prompt-path "$prompt" \
  --evidence-dir "$temp_root/evidence" \
  --opencli-executable "$controlled_opencli" \
  --launch-agents-dir "$temp_root/LaunchAgents" \
  --log-dir "$temp_root/log-parent/x-worker" 2>&1)"
mixed_status=$?
set -e
[[ "$mixed_status" -ne 0 ]]
[[ "$mixed_output" == *"x_worker_config_must_be_x_only"* ]]

echo "x_launchd_worker_tests: pass"
