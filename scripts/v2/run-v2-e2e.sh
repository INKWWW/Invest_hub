#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
node scripts/v2/test-local-opencli-collection-contract.mjs --lock tools/opencli-v2-collection.lock.json --fixture-help workers/v0/tests/fixtures/opencli_twitter_collection_help.txt
node scripts/v2/test-local-x-identity-resolution-gate.mjs
if [[ "${1:-}" == "--opencli-executable" ]]; then
  [[ $# -eq 2 ]] || { printf 'usage: %s [--opencli-executable <dedicated-local-path>]\n' "$0" >&2; exit 2; }
  executable="$2"
  runtime_dir="$(cd -- "$(dirname -- "$executable")/../.." && pwd)"
  bash scripts/v2/verify-local-opencli-collection.sh --runtime-dir "$runtime_dir"
elif [[ $# -ne 0 ]]; then
  printf 'usage: %s [--opencli-executable <dedicated-local-path>]\n' "$0" >&2
  exit 2
fi
python_bin="${V2_PYTHON_BIN:-$repo_root/workers/v0/.venv/bin/python}"
PYTHONPATH="workers/v0/src" "$python_bin" -m unittest tests/e2e/v2/test_x_cross_blogger_daily_judgements.py -v
PYTHONPATH="workers/v0/src:tests/e2e/v2" "$python_bin" -m unittest discover -s tests/e2e/v2 -p 'test_*.py' -v
V1_PYTHON_BIN="${V1_PYTHON_BIN:-$python_bin}" bash scripts/v1/run-v1-1-e2e.sh
(
  cd apps/control-plane
  npm test -- --run \
    src/app/api/api.integration.test.ts \
    src/app/api/reader/x/route.test.ts \
    'src/app/api/admin/x/daily-judgements/[batchId]/regenerate/route.test.ts' \
    src/app/x/page.test.tsx \
    src/components/reader/x-reader-client.test.tsx \
    src/components/reader/x-reader.test.tsx \
    src/lib/db/repositories/reader-source-navigation.test.ts \
    src/lib/db/repositories/tasks.test.ts \
    src/lib/db/repositories/x-daily-judgements.test.ts
)
