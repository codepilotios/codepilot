#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
OUT_DIR="$HOME/.codex-account-switcher/desktop-sync-export"
INCLUDE_HISTORY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)
      INCLUDE_HISTORY=1
      shift
      ;;
    --out-dir)
      if [[ $# -lt 2 ]]; then
        echo "--out-dir requires a directory" >&2
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 1
      ;;
    *)
      OUT_DIR="$1"
      shift
      ;;
  esac
done

if [[ ! -d "$CODEX_HOME" ]]; then
  echo "Codex home not found: $CODEX_HOME" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to build the sync manifest" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

payload="$tmp_dir/payload"
mkdir -p "$payload" "$OUT_DIR"

python3 - "$CODEX_HOME" "$payload/manifest.json" <<'PY'
import datetime
import json
import os
import sqlite3
import sys

codex_home, manifest_path = sys.argv[1:3]
global_path = os.path.join(codex_home, ".codex-global-state.json")
state_db = os.path.join(codex_home, "state_5.sqlite")

def ordered(values):
    seen = set()
    result = []
    for value in values:
        if not isinstance(value, str) or not value.startswith("/") or value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result

global_state = {}
if os.path.exists(global_path):
    with open(global_path, "r", encoding="utf-8") as handle:
        global_state = json.load(handle)

labels = global_state.get("electron-workspace-root-labels")
if not isinstance(labels, dict):
    labels = {}

roots = []
for key in ("active-workspace-roots", "electron-saved-workspace-roots", "project-order"):
    value = global_state.get(key)
    if isinstance(value, list):
        roots.extend(value)

thread_count = 0
if os.path.exists(state_db):
    connection = sqlite3.connect(f"file:{state_db}?mode=ro", uri=True)
    try:
        rows = connection.execute(
            """
            select cwd, count(*) as thread_count
            from threads
            where archived = 0 and trim(cwd) != '' and cwd like '/%'
            group by cwd
            order by max(coalesce(updated_at_ms, updated_at * 1000, 0)) desc
            limit 200
            """
        ).fetchall()
        roots.extend(row[0] for row in rows)
        thread_count = sum(row[1] for row in rows)
    finally:
        connection.close()

root_entries = []
for root in ordered(roots):
    label = str(labels.get(root) or os.path.basename(root.rstrip("/")) or root)
    root_entries.append({"path": root, "label": label})

manifest = {
    "version": 1,
    "kind": "codex-desktop-project-sync",
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sourceCodexHome": codex_home,
    "roots": root_entries,
    "threadCount": thread_count,
}

with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

if [[ "$INCLUDE_HISTORY" -eq 1 ]]; then
  if [[ -f "$CODEX_HOME/.codex-global-state.json" ]]; then
    cp "$CODEX_HOME/.codex-global-state.json" "$payload/.codex-global-state.json"
  fi

  if [[ -f "$CODEX_HOME/session_index.jsonl" ]]; then
    cp "$CODEX_HOME/session_index.jsonl" "$payload/session_index.jsonl"
  fi

  if [[ -f "$CODEX_HOME/state_5.sqlite" ]]; then
    sqlite3 "$CODEX_HOME/state_5.sqlite" ".backup '$payload/state_5.sqlite'"
  fi

  if [[ -d "$CODEX_HOME/sessions" ]]; then
    rsync -a "$CODEX_HOME/sessions/" "$payload/sessions/"
  fi
fi

bundle="$OUT_DIR/codex-desktop-sync.tgz"
tar -C "$payload" -czf "$bundle" .
echo "$bundle"
