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
  'ghp_[A-Za-z0-9_]+'
  'github_pat_[A-Za-z0-9_]+'
  'sk-[A-Za-z0-9]{20,}'
  '-----BEGIN (RSA|OPENSSH|PRIVATE) KEY'
  'Bearer [A-Za-z0-9._-]{20,}'
  'client_secret'
  'private_key'
)

secret_pattern="$(IFS='|'; echo "${secret_patterns[*]}")"

if git grep -n -I -E "$secret_pattern" -- "${audit_files[@]}"; then
  echo "privacy audit failed: tracked files contain secret-looking material" >&2
  exit 1
fi

echo "privacy audit passed"
