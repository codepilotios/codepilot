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

private_patterns_file="${CODEPILOT_PRIVATE_AUDIT_PATTERNS_FILE:-${CODEPILOT_PRIVACY_PATTERNS_FILE:-$ROOT/.private/privacy-audit-patterns.txt}}"

if [[ -n "${CODEPILOT_PRIVATE_AUDIT_PATTERNS_FILE:-}${CODEPILOT_PRIVACY_PATTERNS_FILE:-}" && ! -f "$private_patterns_file" ]]; then
  echo "privacy audit failed: configured private-pattern file is unavailable" >&2
  exit 2
fi

if [[ -f "$private_patterns_file" ]]; then
  if LC_ALL=C grep -nI -F -f "$private_patterns_file" -- "${candidate_files[@]}"; then
    echo "privacy audit failed: repository files contain private identifiers" >&2
    exit 1
  fi
fi

users_dir_pattern="/$(printf %s Users)/[^[:space:]\"']+"
generic_private_patterns=(
  "$users_dir_pattern"
  '[A-Za-z][A-Za-z0-9._%+-]*@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}'
)

audit_files=()
for file in "${candidate_files[@]}"; do
  [[ "$file" == "scripts/privacy-audit.sh" ]] && continue
  audit_files+=("$file")
done

generic_pattern="$(IFS='|'; echo "${generic_private_patterns[*]}")"
if LC_ALL=C grep -nI -E "$generic_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: repository files contain private paths or email addresses" >&2
  exit 1
fi

secret_patterns=(
  "g""hp_[A-Za-z0-9_]{20,}"
  "github_""pat_[A-Za-z0-9_]{20,}"
  "(^|[^A-Za-z0-9])s""k-[A-Za-z0-9]{20,}"
  "-----BEGIN (RSA|OPENSSH|PRIVATE) ""KEY"
  'Bearer [A-Za-z0-9._-]{20,}'
  "client_""secret[[:space:]]*[:=]"
  "private_""key[[:space:]]*[:=]"
)

secret_pattern="$(IFS='|'; echo "${secret_patterns[*]}")"

if LC_ALL=C grep -nI -E "$secret_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: repository files contain secret-looking material" >&2
  exit 1
fi

echo "privacy audit passed"
