#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "privacy audit must run inside a git worktree" >&2
  exit 2
fi

candidate_files=("${(@f)$(git ls-files --cached --others --exclude-standard)}")

if git grep -n -I -E "$pattern" -- .; then
  echo "privacy audit failed: tracked files contain private identifiers" >&2
  exit 1
fi

secret_patterns=(
  'ghp_[A-Za-z0-9_]+'
  'github_pat_[A-Za-z0-9_]+'
  'sk-[A-Za-z0-9]{20,}'
  '-----BEGIN (RSA|OPENSSH|PRIVATE) KEY'
  'Bearer [A-Za-z0-9._-]{20,}'
  'client[_-]?secret[[:space:]]*[:=]'
  'private[_-]?key[[:space:]]*[:=]'
)

secret_pattern="$(IFS='|'; echo "${secret_patterns[*]}")"

if git grep -n -I -E "$secret_pattern" -- .; then
  echo "privacy audit failed: tracked files contain secret-looking material" >&2
  exit 1
fi

noncanonical_public_url_pattern='https://(codepilotios\.github\.io|github\.com/codepilotios)/CodePilot'
if (( ${#audit_files[@]} > 0 )) && LC_ALL=C grep -qI -E "$noncanonical_public_url_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: tracked files contain noncanonical public CodePilot URLs" >&2
  exit 1
fi

echo "privacy audit passed"
