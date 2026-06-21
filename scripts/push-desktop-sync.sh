#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 user@macbook-air [--host-id HOST_ID]" >&2
  exit 1
fi

destination="$1"
shift

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bundle="$("$script_dir/export-desktop-sync.sh")"
remote_dir=".codex-account-switcher/desktop-sync-import"

ssh "$destination" "mkdir -p ~/$remote_dir"
scp "$bundle" "$destination:~/$remote_dir/codex-desktop-sync.tgz"
scp "$script_dir/import-desktop-sync.py" "$destination:~/$remote_dir/import-desktop-sync.py"
scp "$script_dir/repair-remote-project-hosts.py" "$destination:~/$remote_dir/repair-remote-project-hosts.py"

remote_args=(python3 "$remote_dir/import-desktop-sync.py" "$remote_dir/codex-desktop-sync.tgz" --relaunch "$@")
printf -v remote_cmd ' %q' "${remote_args[@]}"
ssh "$destination" "cd ~ &&${remote_cmd}"
