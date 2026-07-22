#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

mode="deterministic"
python_bin="${V1_PYTHON_BIN:-$repo_root/workers/v0/.venv/bin/python}"

while (($# > 0)); do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    *) echo "unknown_argument" >&2; exit 2 ;;
  esac
done

if [[ "$mode" != "deterministic" ]]; then
  echo "v1_1_e2e_supports_deterministic_mode_only" >&2
  exit 2
fi

if ! "$python_bin" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
  echo "python_requires_3_11_or_newer" >&2
  exit 2
fi

PYTHONPATH="workers/v0/src:tests/e2e/v1_1" "$python_bin" -m unittest discover -s tests/e2e/v1_1 -p 'test_*.py' -v
PYTHONPATH="workers/v0/src" "$python_bin" -m unittest discover -s workers/v0/tests -p 'test_windowed_runtime.py' -v
PYTHONPATH="workers/v0/src" "$python_bin" -m unittest discover -s workers/v0/tests -p 'test_scheduler.py' -v

(
  cd apps/control-plane
  npm test -- \
    src/app/api/api.integration.test.ts \
    src/components/admin/source-author-profiles-form.test.tsx \
    src/components/reader/discord-reader.test.tsx \
    src/components/reader/reader-presentation.test.ts \
    src/lib/contracts.test.ts \
    src/lib/db/repositories/author-profiles.test.ts
)
