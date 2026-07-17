#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "privacy audit must run inside a git worktree" >&2
  exit 2
fi

candidate_files=("${(@f)$(git ls-files --cached --others --exclude-standard)}")

if (( ${#candidate_files[@]} == 0 )); then
  echo "privacy audit skipped: no candidate files" >&2
  exit 0
fi

private_patterns_file="${CODEPILOT_PRIVATE_AUDIT_PATTERNS_FILE:-$ROOT/.private/privacy-audit-patterns.txt}"

if [[ -n "${CODEPILOT_PRIVATE_AUDIT_PATTERNS_FILE:-}" && ! -f "$private_patterns_file" ]]; then
  echo "privacy audit failed: configured private-pattern file is unavailable" >&2
  exit 2
fi

if [[ -f "$private_patterns_file" ]]; then
  if LC_ALL=C grep -nI -F -f "$private_patterns_file" -- "${candidate_files[@]}"; then
    echo "privacy audit failed: repository files contain private identifiers" >&2
    exit 1
  fi
fi

secret_patterns=(
  'ghp_[A-Za-z0-9_]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  '(^|[^A-Za-z0-9])sk-[A-Za-z0-9]{20,}'
  '-----BEGIN (RSA|OPENSSH|PRIVATE) KEY'
  'Bearer [A-Za-z0-9._-]{20,}'
  'client_secret[[:space:]]*[:=]'
  'private_key[[:space:]]*[:=]'
)

secret_pattern="$(IFS='|'; echo "${secret_patterns[*]}")"

if LC_ALL=C grep -nI -E "$secret_pattern" -- "${candidate_files[@]}"; then
  echo "privacy audit failed: repository files contain secret-looking material" >&2
  exit 1
fi

echo "privacy audit passed"
