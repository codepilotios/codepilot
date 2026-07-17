#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "privacy audit must run inside a git worktree" >&2
  exit 2
fi

pattern="$(python3 - <<'PY'
entries = [
    "546f6e79",
    "746f6e79",
    "537072656e6b656c696e67",
    "737072656e6b656c696e67",
    "686f6d65736572766572",
    "686f6d655c2e686f6d65",
    "4d6163206d696e69",
    "6d6163206d696e69",
    "444b45",
    "64652d6b6c65696e65",
    "65656b686f6f726e",
    "636f6d5c2e746f6e79",
    "636f5c2e737072656e6b656c696e67",
    "394b3734443657324252",
    "514836354232",
    "515a334d364137324747",
    "70726f7065726c69",
    "676d61696c",
    "69636c6f7564",
    "40737072656e6b656c696e67",
]
print("|".join(bytes.fromhex(entry).decode("utf-8") for entry in entries))
PY
)"

candidate_files=("${(@f)$(git ls-files --cached --others --exclude-standard)}")

if (( ${#candidate_files[@]} == 0 )); then
  echo "privacy audit skipped: no candidate files" >&2
  exit 0
fi

if LC_ALL=C grep -nI -E "$pattern" -- "${candidate_files[@]}"; then
  echo "privacy audit failed: repository files contain private identifiers" >&2
  exit 1
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
