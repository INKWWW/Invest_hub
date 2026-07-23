#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
lock_path="$repo_root/tools/opencli-v2-collection.lock.json"
runtime_dir="$repo_root/.runtime/v2/opencli-collection"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock) lock_path="$2"; shift 2 ;;
    --runtime-dir) runtime_dir="$2"; shift 2 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

lock_path="$(cd -- "$(dirname -- "$lock_path")" && pwd)/$(basename -- "$lock_path")"
runtime_dir="$(cd -- "$runtime_dir" && pwd)"
case "$runtime_dir" in
  "$repo_root"/.runtime/v2/opencli-collection) ;;
  *) printf 'runtime directory must be %s/.runtime/v2/opencli-collection\n' "$repo_root" >&2; exit 2 ;;
esac

read_lock() {
  node -e 'const fs=require("fs");const lock=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const key=process.argv[2];if(typeof lock[key]!=="string"||!lock[key])process.exit(2);process.stdout.write(lock[key]);' "$lock_path" "$1"
}

collection_commit="$(read_lock collection_commit)"
expected_hash="$(read_lock package_lock_sha256)"
current="$runtime_dir/current"
source_dir="$current/source"
executable="$current/bin/opencli-v2-collection"
[[ -x "$executable" && -f "$source_dir/dist/src/main.js" ]]
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$collection_commit" ]]
[[ "$(shasum -a 256 "$source_dir/package-lock.json" | awk '{print $1}')" == "$expected_hash" ]]
grep -q 'Apache License' "$source_dir/LICENSE"
node_major="$(node -p 'process.versions.node.split(".")[0]')"
[[ "$node_major" =~ ^[0-9]+$ ]] && (( node_major >= 20 ))
node "$repo_root/scripts/v2/test-local-opencli-collection-contract.mjs" --lock "$lock_path" --executable "$executable"
printf 'local_opencli_collection_verify: pass commit=%s node=%s\n' "$collection_commit" "$node_major"
