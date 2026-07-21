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
  if LC_ALL=C grep -qI -E -f "$private_patterns_file" -- "${candidate_files[@]}"; then
    echo "privacy audit failed: repository files contain private identifiers" >&2
    exit 1
  fi
fi

users_dir_pattern="/$(printf %s Users)/[^[:space:]\"']+"
generic_private_patterns=(
  "$users_dir_pattern"
  '/home/[^[:space:]"'\'']+'
  'C:[\]Users[\][^[:space:]"'\'']+'
  '[A-Za-z][A-Za-z0-9._%+-]*@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}'
  '(com|io)\.[A-Za-z0-9_-]+\.codexphone'
  "[A-Z][A-Za-z]+'s iPhone"
  'https://ota\.internal\.invalid/'
)

audit_files=()
for file in "${candidate_files[@]}"; do
  [[ "$file" == "scripts/privacy-audit.sh" ]] && continue
  [[ "$file" == "scripts/tests/privacy-audit-test.sh" ]] && continue
  audit_files+=("$file")
done
if [[ -n "${CODEPILOT_PRIVACY_EXTERNAL_FILE:-}" ]]; then
  if [[ ! -f "$CODEPILOT_PRIVACY_EXTERNAL_FILE" ]]; then
    echo "privacy audit failed: configured external file is unavailable" >&2
    exit 2
  fi
  audit_files+=("$CODEPILOT_PRIVACY_EXTERNAL_FILE")
fi

generic_pattern="$(IFS='|'; echo "${generic_private_patterns[*]}")"
if (( ${#audit_files[@]} > 0 )) && LC_ALL=C grep -qI -E "$generic_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: repository files contain private paths or email addresses" >&2
  exit 1
fi

secret_patterns=(
  "g""hp_[A-Za-z0-9_]{20,}"
  "g""ho_[A-Za-z0-9_]{20,}"
  "g""hu_[A-Za-z0-9_]{20,}"
  "g""hs_[A-Za-z0-9_]{20,}"
  "g""hr_[A-Za-z0-9_]{20,}"
  "github_""pat_[A-Za-z0-9_]{20,}"
  "(^|[^A-Za-z0-9])s""k-[A-Za-z0-9]{20,}"
  "(^|[^A-Za-z0-9])s""k-proj-[A-Za-z0-9]{20,}"
  "sbp_[A-Za-z0-9_]{20,}"
  "sb_secret_[A-Za-z0-9_]{20,}"
  "-----BEGIN RSA PRIVATE ""KEY"
  "-----BEGIN OPENSSH PRIVATE ""KEY"
  "-----BEGIN PRIVATE ""KEY"
  "-----BEGIN EC PRIVATE ""KEY-----"
  'Bearer [A-Za-z0-9._-]{20,}'
  'AKIA[A-Z0-9]{16}'
  "AI""za[0-9A-Za-z_-]{35}"
  "xox""[baprs]-[A-Za-z0-9-]{20,}"
  'xapp-[A-Za-z0-9-]{20,}'
  "s""k_live_[A-Za-z0-9]{20,}"
  "s""k_test_[A-Za-z0-9]{20,}"
  "r""k_live_[A-Za-z0-9]{20,}"
  'glpat-[A-Za-z0-9_-]{20,}'
  'npm_[A-Za-z0-9]{20,}'
  "pypi-""[A-Za-z0-9_-]{40,}"
  "hf_""[A-Za-z0-9]{30,}"
  "SG\.""[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}"
  "dop_v1_""[A-Za-z0-9]{40,}"
  "AGE-SECRET-KEY-""1[A-Z0-9]{20,}"
  "-----BEGIN PGP PRIVATE ""KEY BLOCK-----"
  'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{20,}'
  "client_""secret[[:space:]]*[:=]"
  "private_""key[[:space:]]*[:=]"
)

secret_pattern="$(IFS='|'; echo "${secret_patterns[*]}")"

if (( ${#audit_files[@]} > 0 )) && LC_ALL=C grep -qI -E "$secret_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: repository files contain secret-looking material" >&2
  exit 1
fi

noncanonical_public_url_pattern='https://(codepilotios\.github\.io|github\.com/codepilotios)/CodePilot'
if (( ${#audit_files[@]} > 0 )) && LC_ALL=C grep -qI -E "$noncanonical_public_url_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: tracked files contain noncanonical public CodePilot URLs" >&2
  exit 1
fi

echo "privacy audit passed"
