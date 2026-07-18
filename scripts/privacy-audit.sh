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
unix_home_pattern="/$(printf %s home)/[^[:space:]\"']+"
windows_users_pattern="[A-Za-z]:[\\\\/]Users[\\\\/][^[:space:]\\\"']+"
generic_private_patterns=(
  "$users_dir_pattern"
  "$unix_home_pattern"
  "$windows_users_pattern"
  '[A-Za-z][A-Za-z0-9._%+-]*@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}'
  "[A-Z][a-z]+'s (iPhone|iPad|Mac)"
  '(Ping|ping) [A-Z][a-z]+( only)? for:'
  '[A-Z][a-z]+ approves (account|pricing|legal|App Store)'
)

audit_files=()
for file in "${candidate_files[@]}"; do
  [[ "$file" == "scripts/privacy-audit.sh" ]] && continue
  [[ "$file" == "scripts/tests/privacy-audit-test.sh" ]] && continue
  audit_files+=("$file")
done

if git grep -q -I -E "$pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: tracked files contain private identifiers" >&2
  exit 1
fi

contains_disallowed_ota_host() {
  local url authority host
  while IFS= read -r url; do
    authority="${url#*://}"
    host="${authority%%/*}"
    host="${host%%:*}"
    [[ "$host" == "ota.example.com" ]] || return 0
  done < <(git grep -h -I -E -o 'https?://ota\.[A-Za-z0-9.-]+' -- "${audit_files[@]}" || true)
  return 1
}

if contains_disallowed_ota_host; then
  echo "privacy audit failed: tracked files contain a non-placeholder OTA host" >&2
  exit 1
fi

contains_disallowed_bundle_namespace() {
  local identifier
  while IFS= read -r identifier; do
    [[ "$identifier" == com.example.* || "$identifier" == com.openai.* ]] || return 0
  done < <(git grep -h -I -E -o 'com\.[A-Za-z0-9_-]+\.(codex|codexphone)([A-Za-z0-9._-]*)' -- "${audit_files[@]}" || true)
  return 1
}

if contains_disallowed_bundle_namespace; then
  echo "privacy audit failed: tracked files contain a private bundle namespace" >&2
  exit 1
fi

secret_patterns=(
  "g""(hp|ho|hu|hs|hr)_[A-Za-z0-9_]{20,}"
  "github_""pat_[A-Za-z0-9_]+"
  "s""k-[A-Za-z0-9]{20,}"
  "s""k-(proj|svcacct)-[A-Za-z0-9_-]{20,}"
  "(sbp|sb_secret)_[A-Za-z0-9._-]{20,}"
  "-----BEGIN ((RSA|OPENSSH|EC|DSA) )?PRIVATE ""KEY-----"
  "-----BEGIN PGP PRIVATE KEY ""BLOCK-----"
  'Bearer [A-Za-z0-9._-]{20,}'
  '(AKIA|ASIA)[A-Z0-9]{16}'
  'AIza[A-Za-z0-9_-]{30,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'xapp-[A-Za-z0-9-]{10,}'
  '(s|r)k_live_[A-Za-z0-9]{16,}'
  'glpat-[A-Za-z0-9_-]{16,}'
  'npm_[A-Za-z0-9]{20,}'
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  "client_""secret"
  "private_""key"
)

secret_pattern="$(IFS='|'; echo "${secret_patterns[*]}")"

if git grep -q -I -E "$secret_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: tracked files contain secret-looking material" >&2
  exit 1
fi

external_file="${CODEPILOT_PRIVACY_EXTERNAL_FILE:-}"
if [[ -n "$external_file" ]]; then
  if [[ -L "$external_file" || ! -f "$external_file" ]]; then
    echo "privacy audit failed: external content must be a regular file" >&2
    exit 2
  fi
  if grep -q -I -E "$pattern" "$external_file"; then
    echo "privacy audit failed: external content contains private identifiers" >&2
    exit 1
  fi
  if grep -q -I -E "$secret_pattern" "$external_file"; then
    echo "privacy audit failed: external content contains secret-looking material" >&2
    exit 1
  fi
fi

echo "privacy audit passed"
