#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOKEN_PATH = Path.home() / ".codex-account-switcher" / "phone-gateway-token"
LOG_PATH = Path.home() / "Library" / "Logs" / "codex-phone-gateway-idle-restart.log"
GATEWAY_JOBS_URL = "http://127.0.0.1:18790/api/jobs/active"


def log(message: str):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"{timestamp} {message}\n")


def jobs_state() -> str:
    try:
        token = TOKEN_PATH.read_text(encoding="utf-8").strip()
    except OSError as exc:
        log(f"token read failed: {exc}")
        return "unknown"

    request = urllib.request.Request(
        GATEWAY_JOBS_URL,
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        log(f"active job poll failed: {exc}")
        return "unknown"

    jobs = payload.get("jobs")
    if not isinstance(jobs, list):
        return "unknown"

    return "active" if any(
        isinstance(job, dict) and job.get("status") == "running"
        for job in jobs
    ) else "idle"


def main() -> int:
    max_seconds = int(os.environ.get("CODEX_PHONE_GATEWAY_IDLE_RESTART_MAX_SECONDS", "3600"))
    interval_seconds = int(os.environ.get("CODEX_PHONE_GATEWAY_IDLE_RESTART_INTERVAL_SECONDS", "5"))
    deadline = time.monotonic() + max_seconds

    log("waiting for idle gateway restart")
    while time.monotonic() < deadline:
        if jobs_state() == "idle":
            time.sleep(interval_seconds)
            if jobs_state() == "idle":
                log("restarting idle gateway")
                completed = subprocess.run(
                    [str(ROOT / "scripts" / "install-phone-gateway-agent.sh")],
                    cwd=str(ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=False,
                )
                output = " | ".join(completed.stdout.strip().splitlines())
                log(f"installer exit {completed.returncode}: {output}")
                return completed.returncode
        time.sleep(interval_seconds)

    log("timed out waiting for idle gateway")
    return 1


if __name__ == "__main__":
    sys.exit(main())
