#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
python_bin="${V2_PYTHON_BIN:-$repo_root/workers/v0/.venv/bin/python}"
PYTHONPATH="workers/v0/src:tests/e2e/v2" "$python_bin" -m unittest discover -s tests/e2e/v2 -p 'test_*.py' -v
bash scripts/v1/run-v1-1-e2e.sh
(
  cd apps/control-plane
  npm test -- --run src/app/api/api.integration.test.ts src/lib/contracts.test.ts
)
