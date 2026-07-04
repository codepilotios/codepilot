#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "privacy audit must run inside a git worktree" >&2
  exit 2
fi

private_patterns_file="${CODEPILOT_PRIVACY_PATTERNS_FILE:-$HOME/.codepilot-privacy-patterns}"
users_dir_pattern="/$(printf %s Users)/[^[:space:]\"']+"
generic_private_patterns=(
  "$users_dir_pattern"
  '[A-Za-z][A-Za-z0-9._%+-]*@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}'
)

pattern="$(IFS='|'; echo "${generic_private_patterns[*]}")"

if [[ -f "$private_patterns_file" ]]; then
  while IFS= read -r private_pattern; do
    [[ -n "$private_pattern" && "${private_pattern:0:1}" != "#" ]] || continue
    pattern="$pattern|$private_pattern"
  done < "$private_patterns_file"
fi

tracked_files=("${(@f)$(git ls-files)}")
audit_files=()
for file in "${tracked_files[@]}"; do
  [[ "$file" == "scripts/privacy-audit.sh" ]] && continue
  audit_files+=("$file")
done

if git grep -n -I -E "$pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: tracked files contain private identifiers" >&2
  exit 1
fi

secret_patterns=(
  "g""hp_[A-Za-z0-9_]+"
  "github_""pat_[A-Za-z0-9_]+"
  "s""k-[A-Za-z0-9]{20,}"
  "-----BEGIN (RSA|OPENSSH|PRIVATE) ""KEY"
  'Bearer [A-Za-z0-9._-]{20,}'
  "client_""secret"
  "private_""key"
)

secret_pattern="$(IFS='|'; echo "${secret_patterns[*]}")"

if git grep -n -I -E "$secret_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: tracked files contain secret-looking material" >&2
  exit 1
fi

echo "privacy audit passed"
