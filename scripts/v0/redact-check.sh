#!/usr/bin/env bash
set -euo pipefail

tracked_files="$(git ls-files)"

if printf '%s\n' "$tracked_files" | grep -E '(^|/)(\.env|.*\.pem|.*\.key|credentials\.json)$' | grep -vE '(^|/)\.env\.example$' >/dev/null; then
  echo "redaction_check: forbidden_credential_file" >&2
  exit 1
fi

# Search only for credential-shaped values. Public fixture words such as
# "prompt" or "token" are not themselves secrets and are intentionally not
# treated as matches.
if git grep -I -l -E 'sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]{24,}|discord\.com/channels/[0-9]{8,}/[0-9]{8,}' -- ':!workers/v0/tests/**' ':!tests/e2e/v0/**' >/dev/null; then
  echo "redaction_check: credential_shaped_value" >&2
  exit 1
fi

echo "redaction_check: pass"

