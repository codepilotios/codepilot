#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time


MAX_ARCHIVE_MEMBERS = 10_000
MAX_ARCHIVE_BYTES = 2 * 1024 * 1024 * 1024


def ordered(values):
    seen = set()
    result = []
    for value in values:
        if not isinstance(value, str) or not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def safe_extract(bundle, destination):
    with tarfile.open(bundle, "r:gz") as archive:
        root = os.path.abspath(destination)
        members = archive.getmembers()
        if len(members) > MAX_ARCHIVE_MEMBERS:
            raise RuntimeError(
                f"Refusing archive with more than {MAX_ARCHIVE_MEMBERS} members"
            )

        total_size = 0
        for member in members:
            target = os.path.abspath(os.path.join(destination, member.name))
            if target != root and not target.startswith(root + os.sep):
                raise RuntimeError(f"Refusing unsafe archive member: {member.name}")
            if not (member.isdir() or member.isreg()):
                raise RuntimeError(f"Refusing non-file archive member: {member.name}")

            if member.isreg():
                total_size += member.size
                if total_size > MAX_ARCHIVE_BYTES:
                    raise RuntimeError(
                        f"Refusing archive larger than {MAX_ARCHIVE_BYTES} bytes"
                    )

            if member.isdir():
                os.makedirs(target, mode=0o700, exist_ok=True)
                os.chmod(target, 0o700)
                continue

            parent = os.path.dirname(target)
            os.makedirs(parent, mode=0o700, exist_ok=True)
            source = archive.extractfile(member)
            if source is None:
                raise RuntimeError(f"Could not read archive member: {member.name}")
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            with source:
                descriptor = os.open(target, flags, 0o600)
                try:
                    with os.fdopen(descriptor, "wb") as output:
                        descriptor = -1
                        shutil.copyfileobj(source, output)
                finally:
                    if descriptor >= 0:
                        os.close(descriptor)


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


def detect_host_ids(state):
    candidates = []

    direct = state.get("selected-remote-host-id")
    if isinstance(direct, str) and direct:
        candidates.append(direct)

    for key in ("remote-connection-auto-connect-by-host-id", "remote-connection-analytics-id-by-host-id"):
        value = state.get(key)
        if isinstance(value, dict):
            if key == "remote-connection-auto-connect-by-host-id":
                candidates.extend(
                    candidate
                    for candidate, enabled in value.items()
                    if isinstance(candidate, str) and candidate and enabled is True
                )
            else:
                candidates.extend(candidate for candidate in value.keys() if isinstance(candidate, str) and candidate)

    for key in ("codex-managed-remote-connections", "remote-control-connections", "remote-connections"):
        value = state.get(key)
        if isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    candidate = item.get("hostId") or item.get("id")
                    if isinstance(candidate, str) and candidate:
                        candidates.append(candidate)

    return ordered(candidates)


def project_id(host_id, remote_path):
    digest = hashlib.sha256(f"{host_id}\0{remote_path}".encode("utf-8")).hexdigest()[:16]
    return f"remote:{host_id}:{digest}"


def merge_remote_projects_for_host(state, roots, host_id):
    remote_projects = state.get("remote-projects")
    if not isinstance(remote_projects, list):
        remote_projects = []

    by_key = {}
    for item in remote_projects:
        if not isinstance(item, dict):
            continue
        item_host = item.get("hostId")
        item_path = item.get("remotePath")
        if isinstance(item_host, str) and isinstance(item_path, str):
            by_key[(item_host, item_path.rstrip("/"))] = item

    added_ids = []
    for root in roots:
        if not isinstance(root, dict):
            continue
        path = root.get("path")
        if not isinstance(path, str) or not path.startswith("/"):
            continue
        normalized_path = path.rstrip("/")
        label = root.get("label")
        if not isinstance(label, str) or not label.strip():
            label = os.path.basename(normalized_path) or normalized_path

        existing = by_key.get((host_id, normalized_path))
        if existing is None:
            existing = {
                "id": project_id(host_id, normalized_path),
                "hostId": host_id,
                "label": label,
                "remotePath": normalized_path,
            }
            remote_projects.append(existing)
            by_key[(host_id, normalized_path)] = existing
        else:
            existing["label"] = existing.get("label") or label
            existing["remotePath"] = normalized_path
            existing["hostId"] = host_id

        added_ids.append(existing["id"])

    state["remote-projects"] = remote_projects
    return added_ids


def parse_host_ids(values):
    parsed = []
    for value in values or []:
        if not isinstance(value, str):
            continue
        parsed.extend(part.strip() for part in value.split(",") if part.strip())
    return ordered(parsed)


def active_project_host(state):
    active_id = state.get("active-remote-project-id")
    remote_projects = state.get("remote-projects")
    if not isinstance(active_id, str) or not isinstance(remote_projects, list):
        return None
    for project in remote_projects:
        if isinstance(project, dict) and project.get("id") == active_id:
            host_id = project.get("hostId")
            return host_id if isinstance(host_id, str) else None
    return None


def merge_remote_projects(state, manifest, host_ids):
    roots = manifest.get("roots")
    if not isinstance(roots, list):
        raise RuntimeError("Sync manifest does not contain a roots list")

    added_ids = []
    for host_id in host_ids:
        added_ids.extend(merge_remote_projects_for_host(state, roots, host_id))

    state["project-order"] = ordered((state.get("project-order") if isinstance(state.get("project-order"), list) else []) + added_ids)
    preferred_host = host_ids[0] if host_ids else None
    if added_ids and (not state.get("active-remote-project-id") or active_project_host(state) != preferred_host):
        state["active-remote-project-id"] = added_ids[0]
    state["remote-project-connection-backfill-completed"] = True
    return added_ids


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


def main():
    parser = argparse.ArgumentParser(description="Import a Mac Codex project sync bundle into this Mac's remote-project sidebar state.")
    parser.add_argument("bundle", help="Path to codex-desktop-sync.tgz created on the Mac")
    parser.add_argument("--codex-home", default=os.path.expanduser("~/.codex"), help="Codex home on this MacBook")
    parser.add_argument("--host-id", action="append", help="Codex remote host id for the Mac connection. Can be passed more than once or as a comma-separated list.")
    parser.add_argument("--all-detected-hosts", action="store_true", help="Import projects for every detected active remote host id instead of only the selected one.")
    parser.add_argument("--relaunch", action="store_true", help="Quit and reopen Codex after updating global state")
    args = parser.parse_args()

    codex_home = os.path.expanduser(args.codex_home)
    global_path = os.path.join(codex_home, ".codex-global-state.json")
    if args.relaunch:
        quit_codex()

    state = load_json(global_path)
    detected_host_ids = detect_host_ids(state)
    if args.host_id:
        host_ids = parse_host_ids(args.host_id)
    elif args.all_detected_hosts:
        host_ids = detected_host_ids
    else:
        host_ids = detected_host_ids[:1]

    if not host_ids:
        raise SystemExit(
            "Could not auto-detect the Mac remote host id. "
            "Run again with --host-id <id> from this MacBook's Codex remote connection state."
        )

    temp_dir = tempfile.mkdtemp(prefix="codex-desktop-sync-import.")
    try:
        safe_extract(os.path.expanduser(args.bundle), temp_dir)
        manifest = load_json(os.path.join(temp_dir, "manifest.json"))
        if manifest.get("kind") != "codex-desktop-project-sync":
            raise RuntimeError("Bundle manifest is not a Codex desktop project sync bundle")

        if os.path.exists(global_path):
            stamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
            backup_path = f"{global_path}.desktop-sync-bak.{stamp}"
            shutil.copy2(global_path, backup_path)
        else:
            backup_path = None

        added_ids = merge_remote_projects(state, manifest, host_ids)
        write_json_atomic(global_path, state)

        print(f"Imported {len(added_ids)} remote project entries for host ids: {', '.join(host_ids)}")
        if backup_path:
            print(f"Backed up previous global state to {backup_path}")
        if args.relaunch:
            open_codex()
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"import failed: {error}", file=sys.stderr)
        sys.exit(1)
