#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time


def ordered(values):
    seen = set()
    result = []
    for value in values:
        if not isinstance(value, str) or not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json_atomic(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".codex-global-state.", suffix=".tmp", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def project_id(host_id, remote_path):
    digest = hashlib.sha256(f"{host_id}\0{remote_path}".encode("utf-8")).hexdigest()[:16]
    return f"remote:{host_id}:{digest}"


def selected_host_id(state):
    value = state.get("selected-remote-host-id")
    return value if isinstance(value, str) and value else None


def active_project_host(state):
    active_id = state.get("active-remote-project-id")
    projects = state.get("remote-projects")
    if not isinstance(active_id, str) or not isinstance(projects, list):
        return None
    for project in projects:
        if isinstance(project, dict) and project.get("id") == active_id:
            host_id = project.get("hostId")
            return host_id if isinstance(host_id, str) else None
    return None


def quit_codex():
    subprocess.run(
        ["osascript", "-e", 'if application "Codex" is running then tell application "Codex" to quit'],
        check=False,
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        result = subprocess.run(["pgrep", "-x", "Codex"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if result.returncode != 0:
            return
        time.sleep(0.5)


def open_codex():
    subprocess.run(["open", "-a", "Codex"], check=False)


def repair_state(state, target_host_id, source_host_id=None):
    projects = state.get("remote-projects")
    if not isinstance(projects, list):
        return []

    by_key = {}
    source_projects = []
    for project in projects:
        if not isinstance(project, dict):
            continue
        host_id = project.get("hostId")
        remote_path = project.get("remotePath")
        if not isinstance(host_id, str) or not isinstance(remote_path, str) or not remote_path.startswith("/"):
            continue
        normalized_path = remote_path.rstrip("/")
        by_key[(host_id, normalized_path)] = project
        if host_id == target_host_id:
            continue
        if source_host_id and host_id != source_host_id:
            continue
        source_projects.append((project, normalized_path))

    added_ids = []
    for source, remote_path in source_projects:
        if (target_host_id, remote_path) in by_key:
            continue
        label = source.get("label")
        if not isinstance(label, str) or not label.strip():
            label = os.path.basename(remote_path) or remote_path
        new_project = {
            "id": project_id(target_host_id, remote_path),
            "hostId": target_host_id,
            "label": label,
            "remotePath": remote_path,
        }
        projects.append(new_project)
        by_key[(target_host_id, remote_path)] = new_project
        added_ids.append(new_project["id"])

    if added_ids:
        state["remote-projects"] = projects
        state["project-order"] = ordered((state.get("project-order") if isinstance(state.get("project-order"), list) else []) + added_ids)
        if not state.get("active-remote-project-id") or active_project_host(state) != target_host_id:
            state["active-remote-project-id"] = added_ids[0]
        state["remote-project-connection-backfill-completed"] = True

    return added_ids


def main():
    parser = argparse.ArgumentParser(
        description="Mirror Codex remote project entries onto the currently selected remote host id."
    )
    parser.add_argument("--codex-home", default=os.path.expanduser("~/.codex"), help="Codex home on this Mac")
    parser.add_argument("--host-id", help="Target host id. Defaults to selected-remote-host-id.")
    parser.add_argument("--source-host-id", help="Only mirror projects from this source host id")
    parser.add_argument("--relaunch", action="store_true", help="Quit and reopen Codex after updating global state")
    args = parser.parse_args()

    codex_home = os.path.expanduser(args.codex_home)
    global_path = os.path.join(codex_home, ".codex-global-state.json")
    if args.relaunch:
        quit_codex()

    state = load_json(global_path)
    target_host_id = args.host_id or selected_host_id(state)
    if not target_host_id:
        raise SystemExit("No target host id found. Run again with --host-id <id>.")

    if os.path.exists(global_path):
        stamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        backup_path = f"{global_path}.remote-project-host-bak.{stamp}"
        shutil.copy2(global_path, backup_path)
    else:
        backup_path = None

    added_ids = repair_state(state, target_host_id, args.source_host_id)
    write_json_atomic(global_path, state)

    print(f"Mirrored {len(added_ids)} remote projects to host {target_host_id}")
    if backup_path:
        print(f"Backed up previous global state to {backup_path}")
    if args.relaunch:
        open_codex()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"repair failed: {error}", file=sys.stderr)
        sys.exit(1)
