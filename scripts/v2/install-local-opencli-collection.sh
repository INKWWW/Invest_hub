#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
lock_path="$repo_root/tools/opencli-v2-collection.lock.json"
runtime_dir="$repo_root/.runtime/v2/opencli-collection"
approved=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock) lock_path="$2"; shift 2 ;;
    --runtime-dir) runtime_dir="$2"; shift 2 ;;
    --approve-local-build) approved=true; shift ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ "$approved" != true ]]; then
  printf 'refusing local build without --approve-local-build\n' >&2
  exit 2
fi

lock_path="$(cd -- "$(dirname -- "$lock_path")" && pwd)/$(basename -- "$lock_path")"
runtime_dir="$(mkdir -p -- "$runtime_dir" && cd -- "$runtime_dir" && pwd)"
case "$runtime_dir" in
  "$repo_root"/.runtime/v2/opencli-collection) ;;
  *) printf 'runtime directory must be %s/.runtime/v2/opencli-collection\n' "$repo_root" >&2; exit 2 ;;
esac

node_major="$(node -p 'process.versions.node.split(".")[0]')"
if [[ ! "$node_major" =~ ^[0-9]+$ ]] || (( node_major < 20 )); then
  printf 'Node.js 20 or newer is required\n' >&2
  exit 2
fi

read_lock() {
  node -e 'const fs=require("fs");const lock=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const key=process.argv[2];if(typeof lock[key]!=="string"||!lock[key])process.exit(2);process.stdout.write(lock[key]);' "$lock_path" "$1"
}

source_repository="$(read_lock source_repository)"
base_commit="$(read_lock base_commit)"
collection_commit="$(read_lock collection_commit)"
expected_hash="$(read_lock package_lock_sha256)"

stage_dir="$(mktemp -d "$runtime_dir/.staging.XXXXXX")"
completed=false
cleanup() {
  if [[ "$completed" != true && -d "$stage_dir" ]]; then
    rm -rf -- "$stage_dir"
  fi
}
trap cleanup EXIT

git clone --no-checkout "$source_repository" "$stage_dir/source"
git -C "$stage_dir/source" checkout --detach "$collection_commit"
[[ "$(git -C "$stage_dir/source" rev-parse HEAD)" == "$collection_commit" ]]
git -C "$stage_dir/source" merge-base --is-ancestor "$base_commit" "$collection_commit"
[[ "$(shasum -a 256 "$stage_dir/source/package-lock.json" | awk '{print $1}')" == "$expected_hash" ]]
grep -q 'Apache License' "$stage_dir/source/LICENSE"

(
  cd "$stage_dir/source"
  npm ci
  npm run build
)

mkdir -p "$stage_dir/bin"
cat > "$stage_dir/bin/opencli-v2-collection" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
runtime_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec node "$runtime_root/source/dist/src/main.js" "$@"
EOF
chmod 0755 "$stage_dir/bin/opencli-v2-collection"

node "$repo_root/scripts/v2/test-local-opencli-collection-contract.mjs" \
  --lock "$lock_path" \
  --executable "$stage_dir/bin/opencli-v2-collection"

if [[ -d "$runtime_dir/current" ]]; then
  rollback_dir="$runtime_dir/rollback-$(date -u +%Y%m%dT%H%M%SZ)"
  mv -- "$runtime_dir/current" "$rollback_dir"
fi
mv -- "$stage_dir" "$runtime_dir/current"
completed=true
printf 'local_opencli_collection_install: pass\n'
