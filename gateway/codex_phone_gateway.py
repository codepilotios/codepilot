#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import contextlib
from datetime import datetime, timezone
import fcntl
import hashlib
import ipaddress
import json
import mimetypes
import os
import queue
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

try:
    from .remote_desktop_gateway import RemoteDesktopGateway
except ImportError:
    from remote_desktop_gateway import RemoteDesktopGateway


HOME = Path.home()
DEFAULT_CODEX_HOME = HOME / ".codex"
DEFAULT_SWITCHER_HOME = HOME / ".codex-account-switcher"
DEFAULT_TOKEN_FILE = DEFAULT_SWITCHER_HOME / "phone-gateway-token"
DEFAULT_UPLOADS_DIR = DEFAULT_SWITCHER_HOME / "phone-uploads"
MIN_GATEWAY_TOKEN_LENGTH = 32
DEFAULT_THREAD_MESSAGE_CACHE_DIR = DEFAULT_SWITCHER_HOME / "phone-thread-message-cache"
DEFAULT_NOTIFICATION_DEVICES_FILE = DEFAULT_SWITCHER_HOME / "phone-notification-devices.json"
DEFAULT_LIVE_ACTIVITIES_FILE = DEFAULT_SWITCHER_HOME / "phone-live-activities.json"
DEFAULT_CODEX = Path("/Applications/ChatGPT.app/Contents/Resources/codex")
CODEX_CHILD_PATH_PREFIXES = (
    str(HOME / ".local/bin"),
    str(HOME / ".npm-global/bin"),
    str(HOME / ".bun/bin"),
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
)
GATEWAY_ONLY_CHILD_ENV_KEYS = {
    "CODEPILOT_FILE_DOWNLOAD_ROOTS",
    "CODEPILOT_TURN_API_TOKEN",
    "CODEPILOT_TURN_KEY_ID",
    "CODEX_PHONE_APNS_CERT_KEY_PATH",
    "CODEX_PHONE_APNS_CERT_PATH",
    "CODEX_PHONE_APNS_KEY_ID",
    "CODEX_PHONE_APNS_KEY_PATH",
    "CODEX_PHONE_APNS_TEAM_ID",
    "CODEX_PHONE_APNS_TOPIC",
    "SUPABASE_ACCESS_TOKEN",
}
MAX_ATTACHMENTS = 8
MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024
MAX_TOTAL_ATTACHMENT_BYTES = 50 * 1024 * 1024
MAX_JSON_BODY_BYTES = 1 * 1024 * 1024
MAX_ATTACHMENT_REQUEST_BYTES = 72 * 1024 * 1024
UPLOAD_RETENTION_SECONDS = 7 * 24 * 60 * 60
VALID_REASONING_EFFORTS = {"none", "minimal", "low", "medium", "high", "xhigh"}
PUBLIC_JOB_TEXT_LIMIT = 4_000
PUBLIC_EVENT_BODY_LIMIT = 12_000
STALE_AUTH_MARKERS = (
    "token_invalidated",
    "token_revoked",
    "token_expired",
    "invalidated oauth token",
    "authentication token is expired",
    "refresh_token_reused",
    "refresh token has already been used",
    "refresh token was already used",
    "access token could not be refreshed",
    "please try signing in again",
    "please log out and sign in again",
)
DEFAULT_APNS_TOPIC = "io.codepilot.iOS"
REMOTE_LOGIN_AUTH_URL_RE = re.compile(r"https://auth\.openai\.com/oauth/authorize\?\S+")
REMOTE_LOGIN_URL_RE = re.compile(r"https?://\S+")
REMOTE_LOGIN_URL_TIMEOUT_SECONDS = 15
REMOTE_LOGIN_CALLBACK_TIMEOUT_SECONDS = 30
REMOTE_LOGIN_SESSION_TIMEOUT_SECONDS = 10 * 60
REMOTE_LOGIN_MAX_ACTIVE_SESSIONS = 4
LOCAL_WEB_SESSION_TIMEOUT_SECONDS = 10 * 60
LOCAL_WEB_MAX_ACTIVE_SESSIONS = 8
LOCAL_WEB_MAX_REQUESTS_PER_SESSION = 256
LOCAL_WEB_MAX_BYTES = 25 * 1024 * 1024
GATEWAY_MAX_CONCURRENT_REQUESTS = 64
GATEWAY_REQUEST_TIMEOUT_SECONDS = 30.0

JOBS = {}
JOB_PROCESSES = {}
JOBS_LOCK = threading.Lock()
RUN_LOCK = threading.Lock()


def codex_child_env(codex_home: Path) -> dict:
    env = os.environ.copy()
    for key in GATEWAY_ONLY_CHILD_ENV_KEYS:
        env.pop(key, None)
    env["CODEX_HOME"] = str(codex_home)
    existing_path = env.get("PATH") or os.defpath
    path_parts = [part for part in existing_path.split(os.pathsep) if part]
    for prefix in reversed(CODEX_CHILD_PATH_PREFIXES):
        if prefix not in path_parts:
            path_parts.insert(0, prefix)
    env["PATH"] = os.pathsep.join(path_parts)
    return env


def toml_string(value: str) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def toml_scalar(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_scalar(item) for item in value) + "]"
    return toml_string(str(value))


def toml_table_header(parts: list[str]) -> str:
    return "[" + ".".join(toml_string(part) for part in parts) + "]"


class SimpleTOMLDecodeError(ValueError):
    pass


def strip_toml_comment(line: str) -> str:
    in_string = False
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and in_string:
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if char == "#" and not in_string:
            return line[:index]
    return line


def parse_toml_table_path(raw: str) -> list[str]:
    parts = []
    current = []
    in_string = False
    escaped = False
    quoted = False
    for char in raw.strip():
        if escaped:
            current.append("\\" + char)
            escaped = False
            continue
        if char == "\\" and in_string:
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            quoted = True
            current.append(char)
            continue
        if char == "." and not in_string:
            parts.append(parse_toml_path_part("".join(current), quoted))
            current = []
            quoted = False
            continue
        current.append(char)
    if in_string:
        raise SimpleTOMLDecodeError("unterminated quoted table path")
    parts.append(parse_toml_path_part("".join(current), quoted))
    return parts


def parse_toml_path_part(raw: str, quoted: bool) -> str:
    value = raw.strip()
    if not value:
        raise SimpleTOMLDecodeError("empty table path segment")
    if quoted:
        return str(json.loads(value))
    return value


def parse_toml_scalar(raw: str):
    value = raw.strip()
    if value.startswith('"') and value.endswith('"'):
        return json.loads(value)
    if value == "true":
        return True
    if value == "false":
        return False
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [parse_toml_scalar(item) for item in body.split(",")]
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError as exc:
        raise SimpleTOMLDecodeError(f"unsupported TOML value: {value}") from exc


def parse_toml_config_text(text: str) -> dict:
    root: dict = {}
    current = root
    for raw_line in text.splitlines():
        line = strip_toml_comment(raw_line).strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            current = root
            for part in parse_toml_table_path(line[1:-1]):
                child = current.setdefault(part, {})
                if not isinstance(child, dict):
                    raise SimpleTOMLDecodeError(f"table conflicts with scalar: {part}")
                current = child
            continue
        if "=" not in line:
            raise SimpleTOMLDecodeError(f"unsupported TOML line: {line}")
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            raise SimpleTOMLDecodeError("empty TOML key")
        current[key] = parse_toml_scalar(value)
    return root


def append_toml_table(lines: list[str], parts: list[str], values: dict):
    scalar_items = []
    nested_items = []
    for key, value in values.items():
        if isinstance(value, dict):
            nested_items.append((str(key), value))
        else:
            scalar_items.append((str(key), value))

    lines.append("")
    lines.append(toml_table_header(parts))
    for key, value in scalar_items:
        lines.append(f"{key} = {toml_scalar(value)}")
    for key, nested in nested_items:
        append_toml_table(lines, [*parts, key], nested)


class CodexAppServerClient:
    def __init__(
        self,
        codex_path: Path,
        cwd: Path,
        process_factory=subprocess.Popen,
        id_factory=None,
        notification_handler=None,
        env: dict | None = None,
        allow_dangerous: bool = False,
    ):
        self.codex_path = codex_path
        self.cwd = cwd
        self.process_factory = process_factory
        self.id_factory = id_factory or (lambda: str(uuid.uuid4()))
        self.notification_handler = notification_handler
        self.env = env
        self.allow_dangerous = allow_dangerous
        self.process = None
        self.lock = threading.Lock()
        self.write_lock = threading.Lock()
        self.pending_lock = threading.Lock()
        self.pending_responses = {}
        self.unmatched_responses = {}
        self.reader_thread = None
        self.initialized = False
        self.initialize_response = None

    def start(self) -> dict:
        with self.lock:
            if self.process is None or self.process.poll() is not None:
                self.process = self.process_factory(
                    [str(self.codex_path), "app-server", "--listen", "stdio://"],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1,
                    cwd=str(self.cwd),
                    env=self.env,
                )
                self.initialized = False
                self.initialize_response = None
                self.pending_responses = {}
                self.unmatched_responses = {}
                self.reader_thread = None
            if self.initialized and self.initialize_response is not None:
                self._start_reader_locked()
                return self.initialize_response
            response = self._request_sync_locked("initialize", {
                "clientInfo": {
                    "name": "codex-phone-gateway",
                    "title": "Codex Phone Gateway",
                    "version": "0.1",
                },
                "capabilities": {
                    "experimentalApi": True,
                    "optOutNotificationMethods": [],
                },
            })
            self._send_locked({"method": "initialized"})
            self.initialized = True
            self.initialize_response = response
            self._start_reader_locked()
            return response

    def close(self):
        with self.lock:
            if self.process is not None and self.process.poll() is None:
                self.process.terminate()
            self.initialized = False
            self.initialize_response = None
            self.reader_thread = None

    def thread_start(self, cwd: str | None = None, reasoning_effort: str | None = None) -> dict:
        reasoning_effort = codex_app_server_reasoning_effort(reasoning_effort)
        params = {
            "cwd": cwd,
            "approvalPolicy": "never" if self.allow_dangerous else "on-request",
            "sandbox": "danger-full-access" if self.allow_dangerous else "workspace-write",
            "threadSource": "user",
        }
        if reasoning_effort:
            params["config"] = {"model_reasoning_effort": reasoning_effort}
        return self.request("thread/start", params)

    def thread_resume(self, thread_id: str) -> dict:
        return self.request("thread/resume", {
            "threadId": thread_id,
        })

    def thread_set_name(self, thread_id: str, name: str) -> dict:
        return self.request("thread/name/set", {
            "threadId": thread_id,
            "name": name,
        })

    def thread_archive(self, thread_id: str) -> dict:
        return self.request("thread/archive", {
            "threadId": thread_id,
        })

    def thread_list(self, limit: int = 200) -> dict:
        return self.request("thread/list", {
            "limit": limit,
            "sortKey": "updated_at",
            "sortDirection": "desc",
            "archived": False,
            "useStateDbOnly": False,
        })

    def thread_read(self, thread_id: str, include_turns: bool = True) -> dict:
        return self.request("thread/read", {
            "threadId": thread_id,
            "includeTurns": include_turns,
        })

    def turn_start(self, thread_id: str, text: str, reasoning_effort: str | None = None) -> dict:
        reasoning_effort = codex_app_server_reasoning_effort(reasoning_effort)
        params = {
            "threadId": thread_id,
            "input": [self.text_input(text)],
            "approvalPolicy": "never" if self.allow_dangerous else "on-request",
            "sandboxPolicy": {
                "type": "dangerFullAccess" if self.allow_dangerous else "workspaceWrite",
            },
        }
        if reasoning_effort:
            params["effort"] = reasoning_effort
        return self.request("turn/start", params)

    def turn_steer(self, thread_id: str, expected_turn_id: str, text: str) -> dict:
        return self.request("turn/steer", {
            "threadId": thread_id,
            "expectedTurnId": expected_turn_id,
            "input": [self.text_input(text)],
        })

    def turn_interrupt(self, thread_id: str, turn_id: str) -> dict:
        return self.request("turn/interrupt", {
            "threadId": thread_id,
            "turnId": turn_id,
        })

    def request(self, method: str, params: dict | None = None) -> dict:
        if self.process is None or self.process.poll() is not None or not self.initialized:
            raise RuntimeError("Codex app-server is not running")
        request_id = self.id_factory()
        response_queue = queue.Queue(maxsize=1)
        with self.pending_lock:
            self.pending_responses[request_id] = response_queue
        try:
            self._send_locked({
                "id": request_id,
                "method": method,
                "params": params or {},
            })
            with self.pending_lock:
                unmatched = self.unmatched_responses.pop(request_id, None)
            if unmatched is not None:
                response_queue.put(unmatched)
            message = response_queue.get(timeout=3600)
        finally:
            with self.pending_lock:
                self.pending_responses.pop(request_id, None)

        if "error" in message:
            error = message["error"]
            if isinstance(error, dict):
                raise RuntimeError(error.get("message") or compact_json(error))
            raise RuntimeError(str(error))
        return message.get("result") or {}

    @staticmethod
    def text_input(text: str) -> dict:
        return {
            "type": "text",
            "text": text,
            "text_elements": [],
        }

    def _request_sync_locked(self, method: str, params: dict | None = None) -> dict:
        request_id = self.id_factory()
        self._send_locked({
            "id": request_id,
            "method": method,
            "params": params or {},
        })
        while True:
            message = self._read_locked()
            if message.get("id") == request_id:
                if "error" in message:
                    error = message["error"]
                    if isinstance(error, dict):
                        raise RuntimeError(error.get("message") or compact_json(error))
                    raise RuntimeError(str(error))
                return message.get("result") or {}
            if "method" in message and self.notification_handler:
                self.notification_handler(message)

    def _send_locked(self, message: dict):
        if self.process is None or self.process.stdin is None:
            raise RuntimeError("Codex app-server stdin is not available")
        with self.write_lock:
            self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
            self.process.stdin.flush()

    def _read_locked(self) -> dict:
        if self.process is None or self.process.stdout is None:
            raise RuntimeError("Codex app-server stdout is not available")
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError("Codex app-server closed the connection")
        return json.loads(line)

    def _start_reader_locked(self):
        if self.reader_thread is not None and self.reader_thread.is_alive():
            return
        self.reader_thread = threading.Thread(target=self._reader_loop, daemon=True)
        self.reader_thread.start()

    def _reader_loop(self):
        while True:
            try:
                message = self._read_locked()
            except Exception as exc:
                with self.pending_lock:
                    pending = list(self.pending_responses.values())
                    self.pending_responses.clear()
                for response_queue in pending:
                    response_queue.put({"error": str(exc)})
                return

            request_id = message.get("id")
            delivered = False
            if request_id is not None:
                with self.pending_lock:
                    response_queue = self.pending_responses.get(request_id)
                if response_queue is not None:
                    response_queue.put(message)
                    delivered = True
                else:
                    with self.pending_lock:
                        self.unmatched_responses[request_id] = message
                    delivered = True

            if not delivered and "method" in message and self.notification_handler:
                self.notification_handler(message)


def read_or_create_token(path: Path) -> str:
    if path.exists():
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise RuntimeError("Gateway token path must be a regular file")
        os.chmod(path, 0o600)
        token = path.read_text(encoding="utf-8").strip()
        if not token:
            raise RuntimeError("Gateway token file is empty")
        if len(token) < MIN_GATEWAY_TOKEN_LENGTH or re.fullmatch(r"[A-Za-z0-9_-]+", token) is None:
            raise RuntimeError(
                f"Gateway token must contain at least {MIN_GATEWAY_TOKEN_LENGTH} URL-safe characters; rotate it before restarting"
            )
        return token
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    token = secrets.token_urlsafe(32)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(token + "\n")
    return token


def is_loopback_host(host: str) -> bool:
    value = str(host or "").strip().strip("[]")
    if value.casefold() == "localhost":
        return True
    try:
        return ipaddress.ip_address(value).is_loopback
    except ValueError:
        return False


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_ecdsa_signature_to_raw(der: bytes, component_size: int = 32) -> bytes:
    if len(der) < 8 or der[0] != 0x30:
        raise ValueError("Invalid ECDSA signature")
    index = 2
    if der[1] & 0x80:
        length_bytes = der[1] & 0x7F
        index = 2 + length_bytes
    values = []
    for _ in range(2):
        if index >= len(der) or der[index] != 0x02:
            raise ValueError("Invalid ECDSA signature")
        index += 1
        length = der[index]
        index += 1
        value = der[index:index + length]
        index += length
        value = value.lstrip(b"\x00")
        values.append(value.rjust(component_size, b"\x00"))
    return b"".join(values)


class DisabledPushNotifier:
    def send_turn_completion(self, devices, notification):
        return

    def send_live_activity(self, registrations, content_state):
        return []


class APNsCertificatePushNotifier:
    def __init__(self, cert_path: Path, key_path: Path, default_topic: str = DEFAULT_APNS_TOPIC):
        self.cert_path = cert_path
        self.key_path = key_path
        self.default_topic = default_topic

    def send_turn_completion(self, devices, notification):
        for device in devices:
            self.send_to_device(device, notification)

    def send_live_activity(self, registrations, content_state):
        invalid = []
        for registration in registrations:
            status = self.send_live_activity_to_device(registration, content_state)
            if status in {400, 410}:
                invalid.append(str(registration.get("activityId") or ""))
        return [activity_id for activity_id in invalid if activity_id]

    def send_live_activity_to_device(self, registration: dict, content_state: dict) -> int:
        token = str(registration.get("pushToken") or "").strip()
        if not token:
            return 0
        environment = str(registration.get("environment") or "production").strip().lower()
        host = "api.sandbox.push.apple.com" if environment == "development" else "api.push.apple.com"
        bundle_id = str(registration.get("bundleId") or self.default_topic).strip() or self.default_topic
        payload = live_activity_payload(content_state)
        process = run_apns_curl(
            f"https://{host}/3/device/{token}",
            [
                f"apns-topic: {bundle_id}.push-type.liveactivity",
                "apns-push-type: liveactivity",
                "apns-priority: 10",
            ],
            payload,
            cert_path=self.cert_path,
            key_path=self.key_path,
            include_status=True,
        )
        return apns_http_status(process.stdout)

    def send_to_device(self, device: dict, notification: dict):
        token = str(device.get("token") or "").strip()
        if not token:
            return
        environment = str(device.get("environment") or "production").strip().lower()
        host = "api.sandbox.push.apple.com" if environment == "development" else "api.push.apple.com"
        topic = str(device.get("bundleId") or self.default_topic).strip() or self.default_topic
        payload = json.dumps({
            "aps": {
                "alert": {
                    "title": notification["title"],
                    "body": notification["body"],
                },
                "sound": "default",
            },
            "threadId": notification.get("threadId", ""),
            "jobId": notification.get("jobId", ""),
        }, separators=(",", ":")).encode("utf-8")
        run_apns_curl(
            f"https://{host}/3/device/{token}",
            [
                f"apns-topic: {topic}",
                "apns-push-type: alert",
                "apns-priority: 10",
            ],
            payload,
            cert_path=self.cert_path,
            key_path=self.key_path,
            fail_on_http_error=True,
        )


class APNsPushNotifier:
    def __init__(self, team_id: str, key_id: str, key_path: Path, default_topic: str = DEFAULT_APNS_TOPIC):
        self.team_id = team_id
        self.key_id = key_id
        self.key_path = key_path
        self.default_topic = default_topic
        self._cached_jwt = ""
        self._cached_jwt_iat = 0

    @classmethod
    def from_environment(cls):
        cert_path = os.environ.get("CODEX_PHONE_APNS_CERT_PATH", "").strip()
        cert_key_path = os.environ.get("CODEX_PHONE_APNS_CERT_KEY_PATH", "").strip()
        team_id = os.environ.get("CODEX_PHONE_APNS_TEAM_ID", "").strip()
        key_id = os.environ.get("CODEX_PHONE_APNS_KEY_ID", "").strip()
        key_path = os.environ.get("CODEX_PHONE_APNS_KEY_PATH", "").strip()
        topic = os.environ.get("CODEX_PHONE_APNS_TOPIC", DEFAULT_APNS_TOPIC).strip() or DEFAULT_APNS_TOPIC
        if cert_path and cert_key_path:
            cert = Path(cert_path).expanduser()
            key = Path(cert_key_path).expanduser()
            if cert.is_file() and key.is_file():
                return APNsCertificatePushNotifier(cert_path=cert, key_path=key, default_topic=topic)
        if not team_id or not key_id or not key_path:
            return DisabledPushNotifier()
        path = Path(key_path).expanduser()
        if not path.is_file():
            return DisabledPushNotifier()
        return cls(team_id=team_id, key_id=key_id, key_path=path, default_topic=topic)

    def jwt(self) -> str:
        now = int(time.time())
        if self._cached_jwt and now - self._cached_jwt_iat < 45 * 60:
            return self._cached_jwt
        header = base64url(json.dumps({"alg": "ES256", "kid": self.key_id}, separators=(",", ":")).encode("utf-8"))
        payload = base64url(json.dumps({"iss": self.team_id, "iat": now}, separators=(",", ":")).encode("utf-8"))
        signing_input = f"{header}.{payload}".encode("ascii")
        process = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(self.key_path)],
            input=signing_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        signature = base64url(der_ecdsa_signature_to_raw(process.stdout))
        self._cached_jwt = f"{header}.{payload}.{signature}"
        self._cached_jwt_iat = now
        return self._cached_jwt

    def send_turn_completion(self, devices, notification):
        for device in devices:
            self.send_to_device(device, notification)

    def send_live_activity(self, registrations, content_state):
        invalid = []
        for registration in registrations:
            status = self.send_live_activity_to_device(registration, content_state)
            if status in {400, 410}:
                invalid.append(str(registration.get("activityId") or ""))
        return [activity_id for activity_id in invalid if activity_id]

    def send_live_activity_to_device(self, registration: dict, content_state: dict) -> int:
        token = str(registration.get("pushToken") or "").strip()
        if not token:
            return 0
        environment = str(registration.get("environment") or "production").strip().lower()
        host = "api.sandbox.push.apple.com" if environment == "development" else "api.push.apple.com"
        bundle_id = str(registration.get("bundleId") or self.default_topic).strip() or self.default_topic
        process = run_apns_curl(
            f"https://{host}/3/device/{token}",
            [
                f"authorization: bearer {self.jwt()}",
                f"apns-topic: {bundle_id}.push-type.liveactivity",
                "apns-push-type: liveactivity",
                "apns-priority: 10",
            ],
            live_activity_payload(content_state),
            include_status=True,
        )
        return apns_http_status(process.stdout)

    def send_to_device(self, device: dict, notification: dict):
        token = str(device.get("token") or "").strip()
        if not token:
            return
        environment = str(device.get("environment") or "production").strip().lower()
        host = "api.sandbox.push.apple.com" if environment == "development" else "api.push.apple.com"
        topic = str(device.get("bundleId") or self.default_topic).strip() or self.default_topic
        payload = json.dumps({
            "aps": {
                "alert": {
                    "title": notification["title"],
                    "body": notification["body"],
                },
                "sound": "default",
            },
            "threadId": notification.get("threadId", ""),
            "jobId": notification.get("jobId", ""),
        }, separators=(",", ":")).encode("utf-8")
        run_apns_curl(
            f"https://{host}/3/device/{token}",
            [
                f"authorization: bearer {self.jwt()}",
                f"apns-topic: {topic}",
                "apns-push-type: alert",
                "apns-priority: 10",
            ],
            payload,
            fail_on_http_error=True,
        )


def live_activity_payload(content_state: dict) -> bytes:
    return json.dumps({
        "aps": {
            "timestamp": int(time.time()),
            "event": "update",
            "content-state": content_state,
        }
    }, separators=(",", ":")).encode("utf-8")


def run_apns_curl(
    url: str,
    headers: list[str],
    payload: bytes,
    *,
    cert_path: Path | None = None,
    key_path: Path | None = None,
    include_status: bool = False,
    fail_on_http_error: bool = False,
):
    config_lines = [
        f'url = "{curl_config_value(url)}"',
        'request = "POST"',
    ]
    if cert_path is not None:
        config_lines.append(f'cert = "{curl_config_value(str(cert_path))}"')
    if key_path is not None:
        config_lines.append(f'key = "{curl_config_value(str(key_path))}"')
    config_lines.extend(f'header = "{curl_config_value(header)}"' for header in headers)
    if include_status:
        config_lines.append('write-out = "\\n%{http_code}"')
    config_lines.append(f'data-binary = "{curl_config_value(payload.decode("utf-8"))}"')
    config = "\n".join([*config_lines, ""])
    command = ["curl", "--http2", "-sS"]
    if fail_on_http_error:
        command.append("--fail")
    command.extend(["--config", "-"])
    return subprocess.run(
        command,
        input=config.encode("utf-8"),
        stdout=subprocess.PIPE if include_status else subprocess.DEVNULL,
        stderr=subprocess.PIPE if include_status else subprocess.DEVNULL,
        check=False,
    )


def apns_http_status(output: bytes) -> int:
    try:
        return int((output or b"").rsplit(b"\n", 1)[-1])
    except (TypeError, ValueError):
        return 0


def read_marker(path: Path, fallback: str = "") -> str:
    try:
        value = path.read_text(encoding="utf-8").strip()
        return value or fallback
    except FileNotFoundError:
        return fallback


def json_response(handler, status: int, payload: dict):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Referrer-Policy", "no-referrer")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def error_payload(code: str, message: str, recovery: str, details: dict | None = None) -> dict:
    payload = {
        "error": {
            "code": str(code or "gateway_unavailable"),
            "message": str(message or "CodePilot Gateway request failed."),
            "recovery": str(recovery or "Try again, then restart CodePilot Gateway if the problem continues."),
        }
    }
    if details:
        payload["error"]["details"] = details
    return payload


def json_error(handler, status: int, code: str, message: str, recovery: str, details: dict | None = None):
    json_response(handler, status, error_payload(code, message, recovery, details))


class RequestBodyTooLarge(ValueError):
    pass


def decode_body(handler, max_length: int | None = None) -> dict:
    raw_length = handler.headers.get("content-length", "0")
    try:
        length = int(raw_length)
    except (TypeError, ValueError) as exc:
        raise ValueError("invalid_content_length") from exc
    if length < 0:
        raise ValueError("invalid_content_length")
    if length <= 0:
        return {}
    effective_max_length = MAX_JSON_BODY_BYTES if max_length is None else max_length
    if length > effective_max_length:
        raise RequestBodyTooLarge("request_too_large")
    body = handler.rfile.read(length)
    decoded = json.loads(body.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError("request_body_must_be_an_object")
    return decoded


def safe_filename(name: str, fallback: str) -> str:
    base = Path(name or fallback).name.strip()
    if not base:
        base = fallback
    base = re.sub(r"[^A-Za-z0-9._ -]+", "_", base)
    base = base.strip(" .")
    return base[:160] or fallback


def is_image_attachment(path: Path, mime_type: str) -> bool:
    if mime_type.startswith("image/"):
        return True
    return path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp"}


def cleanup_expired_uploads(
    root: Path | None = None,
    *,
    now: float | None = None,
    retention_seconds: int = UPLOAD_RETENTION_SECONDS,
) -> int:
    """Remove expired upload batches without following links outside the upload root."""
    if retention_seconds <= 0:
        raise ValueError("Upload retention must be positive")
    root = DEFAULT_UPLOADS_DIR if root is None else root

    try:
        root_stat = root.lstat()
    except FileNotFoundError:
        return 0
    if stat.S_ISLNK(root_stat.st_mode) or not stat.S_ISDIR(root_stat.st_mode):
        return 0

    cutoff = (time.time() if now is None else now) - retention_seconds
    removed = 0
    for thread_dir in root.iterdir():
        try:
            thread_stat = thread_dir.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(thread_stat.st_mode) or not stat.S_ISDIR(thread_stat.st_mode):
            continue

        for upload_dir in thread_dir.iterdir():
            try:
                upload_stat = upload_dir.lstat()
            except FileNotFoundError:
                continue
            if (
                stat.S_ISLNK(upload_stat.st_mode)
                or not stat.S_ISDIR(upload_stat.st_mode)
                or upload_stat.st_mtime > cutoff
            ):
                continue
            shutil.rmtree(upload_dir)
            removed += 1

        try:
            thread_dir.rmdir()
        except OSError:
            pass
    return removed


def ensure_private_upload_directory(path: Path, *, parents: bool = False) -> None:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        path.mkdir(mode=0o700, parents=parents)
        path_stat = path.lstat()
    if stat.S_ISLNK(path_stat.st_mode) or not stat.S_ISDIR(path_stat.st_mode):
        raise RuntimeError("Upload path must be a real directory")
    os.chmod(path, 0o700)


def configured_download_roots() -> list[Path]:
    roots = [DEFAULT_UPLOADS_DIR]
    configured = os.environ.get("CODEPILOT_FILE_DOWNLOAD_ROOTS", "")
    roots.extend(Path(value).expanduser() for value in configured.split(os.pathsep) if value.strip())
    return [root.resolve(strict=False) for root in roots]


def resolve_requested_file_path(raw_path: str, allowed_roots: list[Path] | None = None) -> Path:
    value = str(raw_path or "").strip()
    if not value:
        raise ValueError("Missing file path")

    if value.startswith("file://"):
        parsed = urllib.parse.urlparse(value)
        value = urllib.request.url2pathname(parsed.path)

    expanded = os.path.expanduser(value)
    candidate = Path(expanded)
    if not candidate.exists():
        without_line_suffix = re.sub(r":\d+(?::\d+)?$", "", expanded)
        if without_line_suffix != expanded:
            candidate = Path(without_line_suffix)

    if not candidate.is_absolute():
        raise ValueError("Only absolute file paths can be opened")

    try:
        resolved = candidate.resolve(strict=True)
    except FileNotFoundError as exc:
        raise LookupError(f"File not found: {candidate}") from exc

    if not resolved.is_file():
        raise LookupError(f"Not a file: {resolved}")

    roots = configured_download_roots() if allowed_roots is None else allowed_roots
    normalized_roots = [root.expanduser().resolve(strict=False) for root in roots]
    if not any(resolved == root or root in resolved.parents for root in normalized_roots):
        raise PermissionError("File is outside the configured CodePilot download roots")

    return resolved


def file_metadata(path: Path) -> dict:
    stat = path.stat()
    mime_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    return {
        "path": str(path),
        "filename": path.name,
        "mimeType": mime_type,
        "size": stat.st_size,
        "modifiedAt": int(stat.st_mtime),
    }


def file_response(handler: BaseHTTPRequestHandler, path: Path):
    metadata = file_metadata(path)
    download_name = path.name.replace('"', "_")
    handler.send_response(200)
    handler.send_header("Content-Type", metadata["mimeType"])
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Referrer-Policy", "no-referrer")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.send_header("Content-Length", str(metadata["size"]))
    handler.send_header("Content-Disposition", f'attachment; filename="{download_name}"')
    handler.end_headers()
    with path.open("rb") as handle:
        shutil.copyfileobj(handle, handler.wfile)


def local_web_response(handler: BaseHTTPRequestHandler, payload: dict):
    body = payload.get("body") or b""
    if isinstance(body, str):
        body = body.encode("utf-8")
    status = int(payload.get("status") or 502)
    handler.send_response(status)
    handler.send_header("Content-Type", str(payload.get("contentType") or "application/octet-stream"))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Referrer-Policy", "no-referrer")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def truncate_text(text: str, limit: int = 900) -> str:
    compacted = re.sub(r"\s+", " ", text).strip()
    if len(compacted) <= limit:
        return compacted
    return compacted[: limit - 1].rstrip() + "…"


def truncate_payload_text(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def compact_json(value, limit: int = 900) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return truncate_text(value, limit)
    try:
        return truncate_text(json.dumps(value, ensure_ascii=False, sort_keys=True), limit)
    except TypeError:
        return truncate_text(str(value), limit)


class LoopbackOnlyRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        source = urllib.parse.urlparse(req.full_url)
        target = urllib.parse.urlparse(urllib.parse.urljoin(req.full_url, newurl))
        source_port = source.port or (443 if source.scheme == "https" else 80)
        target_port = target.port or (443 if target.scheme == "https" else 80)
        if (
            target.scheme != source.scheme
            or (target.hostname or "").casefold() not in {"localhost", "127.0.0.1", "::1"}
            or target_port != source_port
        ):
            raise RuntimeError("Local web redirect left the selected loopback origin")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_local_web_url(url: str) -> tuple[int, dict, bytes]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "CodePilot/0.1 local-web-proxy",
            "Accept": "*/*",
        },
    )
    opener = urllib.request.build_opener(LoopbackOnlyRedirectHandler())
    try:
        with opener.open(request, timeout=30) as response:
            body = response.read(LOCAL_WEB_MAX_BYTES + 1)
            if len(body) > LOCAL_WEB_MAX_BYTES:
                raise RuntimeError("Local web response is too large")
            return int(response.status), dict(response.headers.items()), body
    except urllib.error.HTTPError as exc:
        body = exc.read(LOCAL_WEB_MAX_BYTES + 1)
        if len(body) > LOCAL_WEB_MAX_BYTES:
            raise RuntimeError("Local web response is too large")
        return int(exc.code), dict(exc.headers.items()), body


def is_stale_auth_message(message: str) -> bool:
    lower = str(message or "").lower()
    return any(marker in lower for marker in STALE_AUTH_MARKERS)


def app_server_turn_error(params: dict) -> str:
    candidates = []
    error = params.get("error")
    if isinstance(error, dict):
        candidates.append(error)
    turn = params.get("turn")
    if isinstance(turn, dict):
        turn_error = turn.get("error")
        if isinstance(turn_error, dict):
            candidates.append(turn_error)

    for candidate in candidates:
        message = candidate.get("message")
        if isinstance(message, str) and message.strip():
            return message.strip()
        info = candidate.get("codexErrorInfo")
        if isinstance(info, str) and info.strip():
            return info.strip()
    return ""


def optional_int(value) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        try:
            return int(float(value))
        except ValueError:
            return None
    return None


def epoch_seconds(value) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return None
        if stripped.endswith("Z"):
            stripped = stripped[:-1] + "+00:00"
        try:
            parsed = datetime.fromisoformat(stripped)
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return int(parsed.timestamp())
    return None


def parse_iso_datetime(value: str) -> datetime | None:
    stripped = str(value or "").strip()
    if not stripped:
        return None
    if stripped.endswith("Z"):
        stripped = stripped[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(stripped)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def event_status(raw_status: str | None, stream_type: str) -> str:
    if raw_status in {"in_progress", "running"} or stream_type.endswith(".started"):
        return "running"
    if raw_status in {"failed", "error"}:
        return "failed"
    return "completed"


def display_name(raw: str | None, fallback: str) -> str:
    if not raw:
        return fallback
    return raw.replace("_", " ").strip().title()


def make_stream_event(
    event_id: str,
    kind: str,
    status: str,
    title: str,
    body: str = "",
    subtitle: str = "",
    raw_type: str = "",
    diff_stats: dict | None = None,
    connector_name: str = "",
    connector_auth_warning: bool = False,
) -> dict:
    event = {
        "id": event_id,
        "kind": kind,
        "status": status,
        "title": title,
        "subtitle": subtitle,
        "body": body,
        "timestamp": int(time.time()),
        "rawType": raw_type,
    }
    if diff_stats:
        event["diffStats"] = diff_stats
    if connector_name:
        event["connectorName"] = connector_name
    if connector_auth_warning:
        event["connectorAuthWarning"] = True
    return event


def is_connector_auth_warning(text: str) -> bool:
    lower = str(text or "").lower()
    return any(marker in lower for marker in (
        "authrequired",
        "invalid_token",
        "rmcp::transport::worker",
        "not logged in",
    ))


def connector_name_from_text(text: str, fallback: str = "Connector") -> str:
    lower = str(text or "").lower()
    if "mcp.cloudflare.com" in lower or "cloudflare" in lower:
        return "cloudflare-api"
    return str(fallback or "Connector").strip() or "Connector"


def connector_display_name(name: str) -> str:
    raw = str(name or "").strip()
    if raw == "cloudflare-api":
        return "Cloudflare"
    return raw.replace("_", " ").replace("-", " ").strip().title() or "Connector"


def connector_auth_warning_event(event_id: str, connector_name: str, raw_text: str, raw_type: str) -> dict:
    display = connector_display_name(connector_name)
    return make_stream_event(
        event_id,
        "warning",
        "completed",
        f"{display} auth warning",
        f"{display} reported stale auth while Codex was working. The turn can continue, but that connector may need a fresh login.",
        raw_type=raw_type,
        connector_name=connector_name,
        connector_auth_warning=True,
    )


def diff_stats_from_unified_diff(diff: str) -> dict:
    added = 0
    removed = 0
    for line in str(diff or "").splitlines():
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            added += 1
        elif line.startswith("-"):
            removed += 1
    return {"added": added, "removed": removed}


def file_change_diff_stats(item: dict) -> dict | None:
    changes = item.get("changes")
    if not isinstance(changes, list):
        return None

    added = 0
    removed = 0
    saw_diff = False
    for change in changes:
        if not isinstance(change, dict):
            continue
        diff = change.get("diff")
        if not isinstance(diff, str):
            continue
        saw_diff = True
        stats = diff_stats_from_unified_diff(diff)
        added += stats["added"]
        removed += stats["removed"]

    if not saw_diff:
        return None
    return {"added": added, "removed": removed}


def summarize_file_change_paths(item: dict) -> str:
    changes = item.get("changes")
    if not isinstance(changes, list):
        return ""

    paths = []
    for change in changes:
        if not isinstance(change, dict):
            continue
        path = str(change.get("path") or "").strip()
        if path:
            paths.append(path)
    return "\n".join(paths[:8])


def summarize_tool_result(result) -> str:
    if not isinstance(result, dict):
        return compact_json(result)

    content = result.get("content")
    if isinstance(content, list):
        parts = []
        for item in content[:3]:
            if isinstance(item, dict):
                text = item.get("text") or item.get("value")
                if isinstance(text, str) and text.strip():
                    parts.append(text.strip())
        if parts:
            return truncate_text("\n".join(parts))
    return compact_json(result)


def format_item_event(stream_type: str, item: dict, sequence: int) -> dict:
    item_type = item.get("type")
    item_id = str(item.get("id") or f"{stream_type}-{sequence}")
    status = event_status(item.get("status"), stream_type)

    if item_type == "agent_message":
        text = str(item.get("text") or "")
        return make_stream_event(
            item_id,
            "message",
            status,
            "Codex",
            truncate_text(text, 1400) if text else "Composing response",
            raw_type=stream_type,
        )

    if item_type == "mcp_tool_call":
        tool = str(item.get("tool") or "Tool call")
        server = str(item.get("server") or "")
        body = compact_json(item.get("arguments"))
        if status != "running":
            error = item.get("error")
            if error:
                error_body = compact_json(error)
                if is_connector_auth_warning(error_body):
                    return connector_auth_warning_event(
                        item_id,
                        connector_name_from_text(error_body, server or tool),
                        error_body,
                        stream_type,
                    )
                status = "failed"
                body = error_body
            else:
                result = summarize_tool_result(item.get("result"))
                if result:
                    body = result
        return make_stream_event(item_id, "tool", status, tool, body, server, stream_type)

    if item_type in {"function_call", "custom_tool_call", "tool_search_call"}:
        name = str(item.get("name") or item.get("tool") or display_name(item_type, "Tool call"))
        body = compact_json(item.get("arguments") or item.get("input") or item.get("query"))
        return make_stream_event(item_id, "tool", status, name, body, raw_type=stream_type)

    if item_type in {"function_call_output", "custom_tool_call_output", "tool_search_output"}:
        body = compact_json(item.get("output") or item.get("result"))
        return make_stream_event(item_id, "tool", status, "Tool result", body, raw_type=stream_type)

    if item_type == "command_execution":
        command = item.get("command")
        if isinstance(command, list):
            title = " ".join(str(part) for part in command[:4])
        else:
            title = str(command or "Command")
        body = compact_json(item.get("aggregated_output") or item.get("output") or item.get("arguments"))
        return make_stream_event(item_id, "command", status, title, body, raw_type=stream_type)

    if item_type in {"file_change", "fileChange"}:
        return make_stream_event(
            item_id,
            "fileChange",
            status,
            "File changes",
            summarize_file_change_paths(item),
            raw_type=stream_type,
            diff_stats=file_change_diff_stats(item),
        )

    if item_type == "reasoning":
        if not item.get("content") and not item.get("summary"):
            return None
        return make_stream_event(item_id, "context", status, "Reasoning", compact_json(item), raw_type=stream_type)

    return make_stream_event(
        item_id,
        "context",
        status,
        display_name(item_type, "Codex event"),
        compact_json(item),
        raw_type=stream_type,
    )


def format_non_json_stream_line(line: str, sequence: int) -> dict | None:
    stripped = line.strip()
    if not stripped:
        return None
    if is_connector_auth_warning(stripped):
        return connector_auth_warning_event(
            f"log-{sequence}",
            connector_name_from_text(stripped),
            stripped,
            "stderr",
        )
    return make_stream_event(
        f"log-{sequence}",
        "log",
        "completed",
        "Runtime output",
        truncate_text(stripped),
        raw_type="stderr",
    )


def format_stream_event(line: str, sequence: int) -> dict | None:
    stripped = line.strip()
    if not stripped:
        return None

    try:
        event = json.loads(stripped)
    except json.JSONDecodeError:
        return format_non_json_stream_line(stripped, sequence)

    if not isinstance(event, dict):
        return make_stream_event(f"event-{sequence}", "log", "completed", "Runtime output", compact_json(event))

    stream_type = str(event.get("type") or "event")
    if stream_type == "thread.started":
        thread_id = str(event.get("thread_id") or "")
        return make_stream_event(
            "thread.started",
            "context",
            "completed",
            "Thread resumed",
            thread_id,
            raw_type=stream_type,
        )

    if stream_type == "turn.started":
        return make_stream_event(
            "turn.started",
            "context",
            "completed",
            "Context loaded",
            "Codex has loaded the thread context and started the turn.",
            raw_type=stream_type,
        )

    if stream_type == "turn.completed":
        usage = event.get("usage")
        body = ""
        if isinstance(usage, dict):
            output_tokens = usage.get("output_tokens")
            reasoning_tokens = usage.get("reasoning_output_tokens")
            if output_tokens is not None:
                body = f"Output tokens: {output_tokens}"
                if reasoning_tokens is not None:
                    body += f" · reasoning: {reasoning_tokens}"
        return make_stream_event(
            "turn.completed",
            "status",
            "completed",
            "Turn finished",
            body,
            raw_type=stream_type,
        )

    item = event.get("item")
    if stream_type.startswith("item.") and isinstance(item, dict):
        return format_item_event(stream_type, item, sequence)

    return make_stream_event(
        f"event-{sequence}",
        "context",
        event_status(None, stream_type),
        display_name(stream_type.split(".")[-1], "Codex event"),
        compact_json(event),
        raw_type=stream_type,
    )


def append_job_event(job: dict, event: dict | None):
    if not event:
        return
    event = dict(event)
    next_sequence = optional_int(job.get("_eventSeq")) or 0
    next_sequence += 1
    job["_eventSeq"] = next_sequence
    event["eventSeq"] = next_sequence
    events = job.setdefault("events", [])
    event_id = event.get("id")
    if event_id:
        for index, existing in enumerate(events):
            if existing.get("id") == event_id:
                events[index] = event
                break
        else:
            events.append(event)
    else:
        events.append(event)
    if len(events) > 80:
        del events[: len(events) - 80]


def public_job_event(event: dict) -> dict:
    public = {
        key: value
        for key, value in event.items()
        if not str(key).startswith("_")
    }
    body = public.get("body")
    if isinstance(body, str):
        public["body"] = truncate_payload_text(body, PUBLIC_EVENT_BODY_LIMIT)
    return public


def public_job(job: dict, after_event_seq: int | None = None) -> dict:
    public = {
        key: value
        for key, value in job.items()
        if not str(key).startswith("_")
    }
    public["output"] = truncate_payload_text(str(public.get("output") or ""), PUBLIC_JOB_TEXT_LIMIT)
    public["lastMessage"] = truncate_payload_text(str(public.get("lastMessage") or ""), PUBLIC_JOB_TEXT_LIMIT)

    raw_events = public.get("events")
    if isinstance(raw_events, list):
        events = []
        for event in raw_events:
            if not isinstance(event, dict):
                continue
            event_sequence = optional_int(event.get("eventSeq")) or 0
            if after_event_seq is not None and event_sequence <= after_event_seq:
                continue
            events.append(public_job_event(event))
        public["events"] = events
    public["eventCursor"] = optional_int(job.get("_eventSeq")) or max(
        [optional_int(event.get("eventSeq")) or 0 for event in raw_events if isinstance(event, dict)],
        default=0,
    ) if isinstance(raw_events, list) else optional_int(job.get("_eventSeq")) or 0
    push_notification_sent_at = optional_int(job.get("_pushNotificationSentAt"))
    if push_notification_sent_at is not None:
        public["completionNotificationSentAt"] = push_notification_sent_at
    return public


def is_app_server_thread_not_found_error(error: Exception) -> bool:
    message = str(error).strip().lower()
    return "thread not found" in message


def update_job_thread_id(job: dict, event: dict | None):
    if not event:
        return
    if event.get("rawType") != "thread.started":
        return
    thread_id = str(event.get("body") or "").strip()
    if thread_id:
        job["threadId"] = thread_id


def extract_app_server_thread_id(message: dict) -> str:
    params = message.get("params")
    if not isinstance(params, dict):
        return ""
    for key in ("threadId", "thread_id"):
        value = params.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    thread = params.get("thread")
    if isinstance(thread, dict):
        value = thread.get("id")
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def extract_app_server_turn_id(message: dict) -> str:
    params = message.get("params")
    if not isinstance(params, dict):
        return ""
    for key in ("turnId", "turn_id"):
        value = params.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    turn = params.get("turn")
    if isinstance(turn, dict):
        value = turn.get("id")
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def app_server_notification_event(message: dict) -> dict | None:
    method = str(message.get("method") or "app-server")
    params = message.get("params") or {}
    if not isinstance(params, dict):
        params = {}

    if method == "item/agentMessage/delta" or method.endswith("/outputDelta"):
        return None

    if method in {"thread/tokenUsage/updated", "thread/status/changed"}:
        return None

    if method == "turn/diff/updated":
        diff = params.get("diff")
        if not isinstance(diff, str):
            return None
        return make_stream_event(
            "turn.diff",
            "context",
            "completed",
            "Updated",
            "",
            raw_type=method,
            diff_stats=diff_stats_from_unified_diff(diff),
        )

    if method in {"item/started", "item/completed", "item/updated"}:
        item = params.get("item")
        if isinstance(item, dict):
            item_type = str(item.get("type") or "")
            if item_type == "agentMessage":
                text = str(item.get("text") or "")
                if text.strip():
                    return make_stream_event(
                        str(item.get("id") or f"agent-message.{uuid.uuid4()}"),
                        "message",
                        "completed",
                        "Codex",
                        text.strip(),
                        raw_type=method,
                    )
                return None
            if item_type == "userMessage":
                return None
            normalized = normalize_app_server_item(item, method)
            if normalized:
                return format_item_event(method, normalized, 0)
        return None

    body = compact_json(params)
    if method == "turn/started":
        return make_stream_event("turn.started", "context", "completed", "Context loaded", "Codex has started the turn.", raw_type=method)
    if method == "turn/completed":
        error_message = app_server_turn_error(params)
        if error_message:
            return make_stream_event("turn.failed", "error", "failed", "Codex failed", error_message, raw_type=method)
        return make_stream_event("turn.completed", "status", "completed", "Turn finished", body, raw_type=method)
    if method in {"turn/failed", "turn/error"}:
        return make_stream_event("turn.failed", "error", "failed", "Codex failed", body, raw_type=method)
    return make_stream_event(f"app-server.{uuid.uuid4()}", "context", "completed", display_name(method.split("/")[-1], "Codex event"), body, raw_type=method)


def app_server_agent_delta_event(job: dict, params: dict) -> dict | None:
    item_id = str(params.get("itemId") or params.get("item_id") or "").strip()
    delta = str(params.get("delta") or "")
    if not item_id or not delta:
        return None

    message_bodies = job.setdefault("_messageBodies", {})
    body = str(message_bodies.get(item_id) or "") + delta
    message_bodies[item_id] = body
    return make_stream_event(
        item_id,
        "message",
        "running",
        "Codex",
        body.strip(),
        raw_type="item/agentMessage/delta",
    )


def normalize_app_server_item(item: dict, method: str) -> dict | None:
    item_type = str(item.get("type") or "")
    type_map = {
        "commandExecution": "command_execution",
        "mcpToolCall": "mcp_tool_call",
        "functionCall": "function_call",
        "customToolCall": "custom_tool_call",
        "toolSearchCall": "tool_search_call",
        "functionCallOutput": "function_call_output",
        "customToolCallOutput": "custom_tool_call_output",
        "toolSearchOutput": "tool_search_output",
        "agentMessage": "agent_message",
        "fileChange": "file_change",
    }
    normalized_type = type_map.get(item_type, item_type)
    if not normalized_type:
        return None

    normalized = dict(item)
    normalized["type"] = normalized_type
    if "aggregatedOutput" in normalized and "aggregated_output" not in normalized:
        normalized["aggregated_output"] = normalized.get("aggregatedOutput")
    if method == "item/started":
        normalized["status"] = "running"
    elif method == "item/completed":
        normalized["status"] = "completed"
    return normalized


def text_from_content(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") in {"input_text", "output_text", "text"} and isinstance(item.get("text"), str):
                    parts.append(item["text"])
                elif isinstance(item.get("value"), str):
                    parts.append(item["value"])
        return "\n".join(parts).strip()
    return ""


def text_from_user_inputs(content) -> str:
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts = []
    for item in content:
        if not isinstance(item, dict):
            continue
        if item.get("type") == "text" and isinstance(item.get("text"), str):
            parts.append(item["text"])
        elif item.get("type") in {"input_text", "output_text"} and isinstance(item.get("text"), str):
            parts.append(item["text"])
    return "\n".join(part.strip() for part in parts if part and part.strip()).strip()


def is_visible_message(text: str) -> bool:
    stripped = text.strip()
    if not stripped:
        return False
    hidden_prefixes = (
        "<environment_context>",
        "<developer_context>",
        "<permissions instructions>",
        "<app-context>",
        "<collaboration_mode>",
        "<apps_instructions>",
        "<skills_instructions>",
        "<plugins_instructions>",
    )
    return not any(stripped.startswith(prefix) for prefix in hidden_prefixes)


def parse_messages(rollout_path: Path, limit: int = 80) -> list[dict]:
    if not rollout_path.exists():
        return []

    messages = []
    with rollout_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, 1):
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            payload = event.get("payload")
            timestamp = event.get("timestamp")
            if not isinstance(payload, dict):
                continue

            if event.get("type") == "event_msg" and payload.get("type") == "user_message":
                text = payload.get("message")
                if isinstance(text, str) and is_visible_message(text):
                    messages.append({
                        "id": f"{line_number}",
                        "role": "user",
                        "text": text.strip(),
                        "timestamp": timestamp,
                    })
                continue

            if event.get("type") == "event_msg" and payload.get("type") == "agent_message":
                text = payload.get("message")
                if isinstance(text, str) and is_visible_message(text):
                    messages.append({
                        "id": f"{line_number}",
                        "role": "assistant",
                        "text": text.strip(),
                        "timestamp": timestamp,
                    })
                continue

            if event.get("type") == "event_msg" and payload.get("type") == "task_complete":
                text = payload.get("last_agent_message")
                if isinstance(text, str) and is_visible_message(text):
                    messages.append({
                        "id": f"{line_number}",
                        "role": "assistant",
                        "text": text.strip(),
                        "timestamp": payload.get("completed_at") or timestamp,
                    })
                continue

            if event.get("type") == "response_item" and payload.get("type") == "message":
                role = payload.get("role")
                if role not in {"user", "assistant"}:
                    continue
                if payload.get("phase") not in {None, "final", "commentary"}:
                    continue
                text = text_from_content(payload.get("content"))
                if is_visible_message(text):
                    messages.append({
                        "id": f"{line_number}",
                        "role": role,
                        "text": text,
                        "timestamp": timestamp,
                    })

    deduped = []
    seen = set()
    for message in messages:
        key = (message["role"], message["text"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(message)
    return deduped[-limit:]


def app_server_thread_title(thread: dict) -> str:
    name = str(thread.get("name") or "").strip()
    if name:
        return name
    preview = str(thread.get("preview") or "").strip()
    if preview:
        return preview.splitlines()[0][:120]
    return "Untitled"


def app_server_thread_to_phone_thread(thread: dict, include_messages: bool = False) -> dict:
    phone_thread = {
        "id": str(thread.get("id") or ""),
        "title": app_server_thread_title(thread),
        "cwd": str(thread.get("cwd") or ""),
        "rolloutPath": str(thread.get("path") or ""),
        "updatedAt": optional_int(thread.get("updatedAt")) or 0,
        "createdAt": optional_int(thread.get("createdAt")) or 0,
        "source": thread.get("source"),
        "threadSource": thread.get("threadSource"),
        "reasoningEffort": thread.get("reasoningEffort") or thread.get("reasoning_effort"),
    }
    if include_messages:
        phone_thread["messages"] = messages_from_app_server_thread(thread)
    return phone_thread


def phone_message_timestamp(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(int(value), timezone.utc).isoformat()
        except (OverflowError, OSError, ValueError):
            return str(value)
    return str(value)


def scoped_thread_message_id(thread_id: str, message_id: str) -> str:
    thread_id = str(thread_id or "").strip()
    message_id = str(message_id or "").strip()
    if not thread_id or not message_id or message_id.startswith(f"{thread_id}:"):
        return message_id
    return f"{thread_id}:{message_id}"


def scope_thread_message_ids(thread_id: str, messages: list[dict]) -> list[dict]:
    scoped = []
    for message in messages:
        if not isinstance(message, dict):
            continue
        copied = dict(message)
        copied["id"] = scoped_thread_message_id(thread_id, copied.get("id") or "")
        scoped.append(copied)
    return scoped


def messages_from_app_server_thread(thread: dict, limit: int = 120) -> list[dict]:
    messages = []
    thread_id = str(thread.get("id") or "").strip()
    turns = thread.get("turns")
    if not isinstance(turns, list):
        return []

    for turn_index, turn in enumerate(turns):
        if not isinstance(turn, dict):
            continue
        timestamp = turn.get("startedAt") or turn.get("completedAt")
        items = turn.get("items")
        if not isinstance(items, list):
            continue
        for item_index, item in enumerate(items):
            if not isinstance(item, dict):
                continue
            item_type = item.get("type")
            message = None
            if item_type == "userMessage":
                text = text_from_user_inputs(item.get("content"))
                if is_visible_message(text):
                    message = {
                        "id": scoped_thread_message_id(
                            thread_id,
                            item.get("id") or f"turn-{turn_index}-item-{item_index}",
                        ),
                        "role": "user",
                        "text": text,
                        "timestamp": phone_message_timestamp(timestamp),
                    }
            elif item_type == "agentMessage":
                phase = item.get("phase")
                if phase not in {None, "final", "commentary"}:
                    continue
                text = str(item.get("text") or "").strip()
                if is_visible_message(text):
                    message = {
                        "id": scoped_thread_message_id(
                            thread_id,
                            item.get("id") or f"turn-{turn_index}-item-{item_index}",
                        ),
                        "role": "assistant",
                        "text": text,
                        "timestamp": phone_message_timestamp(timestamp),
                    }
            if message:
                messages.append(message)

    deduped = []
    seen = set()
    for message in messages:
        key = (message["role"], message["text"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(message)
    return deduped[-limit:]


def message_cache_path(thread_id: str) -> Path:
    safe_thread_id = re.sub(r"[^A-Za-z0-9_.-]", "_", str(thread_id or "").strip())
    return DEFAULT_THREAD_MESSAGE_CACHE_DIR / f"{safe_thread_id}.json"


def read_cached_thread_messages(thread_id: str) -> list[dict]:
    path = message_cache_path(thread_id)
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    raw_messages = payload.get("messages") if isinstance(payload, dict) else None
    if not isinstance(raw_messages, dict):
        return []

    messages = []
    for message_id, message in raw_messages.items():
        if not isinstance(message, dict):
            continue
        text = str(message.get("text") or "").strip()
        if not is_visible_message(text):
            continue
        messages.append({
            "id": f"cached-{message_id}",
            "role": "assistant",
            "text": text,
            "timestamp": str(message.get("timestamp") or ""),
        })
    return messages


def cache_thread_message(thread_id: str, message_id: str, text: str, timestamp: int | None = None):
    thread_id = str(thread_id or "").strip()
    message_id = str(message_id or "").strip()
    text = str(text or "").strip()
    if not thread_id or not message_id or not is_visible_message(text):
        return

    path = message_cache_path(thread_id)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    try:
        payload = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except (OSError, json.JSONDecodeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    messages = payload.setdefault("messages", {})
    if not isinstance(messages, dict):
        messages = {}
        payload["messages"] = messages
    event_time = int(timestamp or time.time())
    messages[message_id] = {
        "text": text,
        "timestamp": datetime.fromtimestamp(event_time, timezone.utc).isoformat(),
        "updatedAt": event_time,
    }
    write_json_object_atomic(path, payload)
    os.chmod(path, 0o600)


def message_sort_timestamp(message: dict) -> float | None:
    raw_timestamp = str(message.get("timestamp") or "").strip()
    if not raw_timestamp:
        return None
    try:
        if raw_timestamp.endswith("Z"):
            raw_timestamp = f"{raw_timestamp[:-1]}+00:00"
        parsed = datetime.fromisoformat(raw_timestamp)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.timestamp()
    except ValueError:
        return None


def merge_thread_messages(primary: list[dict], cached: list[dict], limit: int = 80) -> list[dict]:
    merged = []
    seen = set()
    for message in [*primary, *cached]:
        role = message.get("role")
        text = str(message.get("text") or "")
        key = (role, text)
        if not role or not text.strip() or key in seen:
            continue
        seen.add(key)
        merged.append(message)

    indexed_messages = list(enumerate(merged))

    def sort_key(indexed_message):
        index, message = indexed_message
        timestamp = message_sort_timestamp(message)
        if timestamp is None:
            return (0, index)
        return (1, timestamp, index)

    indexed_messages.sort(key=sort_key)
    return [message for _, message in indexed_messages][-limit:]


def read_json_object(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{path} is not valid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError(f"{path} must contain a JSON object")
    return payload


def write_json_object_atomic(path: Path, payload: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".codex-global-state.", suffix=".tmp", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        tmp_path.replace(path)
    except Exception:
        try:
            tmp_path.unlink()
        except OSError:
            pass
        raise


def ordered_thread_ids(values) -> list[str]:
    if not isinstance(values, list):
        return []
    seen = set()
    ordered = []
    for value in values:
        thread_id = str(value or "").strip()
        if not thread_id or thread_id in seen:
            continue
        seen.add(thread_id)
        ordered.append(thread_id)
    return ordered


def normalized_reasoning_effort(value) -> str | None:
    effort = str(value or "").strip().lower()
    if not effort:
        return None
    if effort not in VALID_REASONING_EFFORTS:
        raise ValueError("Reasoning effort must be one of: none, minimal, low, medium, high, xhigh")
    return effort


def codex_app_server_reasoning_effort(value: str | None) -> str | None:
    if value is not None:
        normalized_reasoning_effort(value)
    return "medium"


def read_pinned_thread_ids(global_state_path: Path) -> list[str]:
    try:
        payload = read_json_object(global_state_path)
    except RuntimeError:
        return []
    return ordered_thread_ids(payload.get("pinned-thread-ids"))


def pinned_thread_rank_by_id(global_state_path: Path) -> dict[str, int]:
    return {thread_id: index for index, thread_id in enumerate(read_pinned_thread_ids(global_state_path))}


def apply_pinned_state(thread: dict, pinned_rank_by_id: dict[str, int]) -> dict:
    copied = dict(thread)
    thread_id = str(copied.get("id") or "").strip()
    pinned_rank = pinned_rank_by_id.get(thread_id)
    copied["pinned"] = pinned_rank is not None
    copied["pinnedRank"] = pinned_rank
    return copied


def curl_config_value(value: str) -> str:
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "")


def consume_codex_rate_limit_reset_credit(access_token: str, idempotency_key: str) -> dict:
    token = str(access_token or "").strip()
    if not token:
        raise RuntimeError("Account auth has no access token")

    body = json.dumps({
        "creditType": "usage_limit",
        "idempotencyKey": idempotency_key,
    }, separators=(",", ":"))
    config = "\n".join([
        'url = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume"',
        'request = "POST"',
        'header = "Accept: application/json"',
        'header = "Content-Type: application/json"',
        f'header = "Authorization: Bearer {curl_config_value(token)}"',
        f'data = "{curl_config_value(body)}"',
        "",
    ])
    completed = subprocess.run(
        ["/usr/bin/curl", "-fsS", "--max-time", "20", "--config", "-"],
        input=config,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip() or f"curl exited {completed.returncode}"
        raise RuntimeError(f"Rate limit reset request failed: {truncate_text(message, 500)}")
    if not completed.stdout.strip():
        return {}
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Rate limit reset response was not JSON: {exc}") from exc
    return payload if isinstance(payload, dict) else {"response": payload}


class GatewayState:
    def __init__(
        self,
        codex_home: Path,
        token: str,
        codex_path: Path,
        allow_dangerous: bool,
        app_server_cwd: Path | None = None,
        app_server_process_factory=subprocess.Popen,
        app_server_id_factory=None,
        push_notifier=None,
        login_runner=None,
        login_process_factory=subprocess.Popen,
        login_callback_relayer=None,
        remote_desktop_gateway=None,
        local_web_fetcher=None,
    ):
        self.codex_home = codex_home
        self.token = token
        self.codex_path = codex_path
        self.allow_dangerous = allow_dangerous
        self.app_server_cwd = app_server_cwd or Path.cwd()
        self.app_server_process_factory = app_server_process_factory
        self.app_server_id_factory = app_server_id_factory
        self._app_server_client = None
        self._app_server_auth_fingerprint = ""
        self._app_server_lock = threading.Lock()
        self.push_notifier = push_notifier if push_notifier is not None else APNsPushNotifier.from_environment()
        self.login_runner = login_runner
        self.login_process_factory = login_process_factory
        self.login_callback_relayer = login_callback_relayer
        self.remote_desktop_gateway = remote_desktop_gateway if remote_desktop_gateway is not None else RemoteDesktopGateway()
        self.local_web_fetcher = local_web_fetcher if local_web_fetcher is not None else fetch_local_web_url
        self._local_web_sessions = {}
        self._local_web_lock = threading.Lock()
        self._remote_login_sessions = {}
        self._remote_login_lock = threading.Lock()
        self._remote_login_start_lock = threading.Lock()

    @property
    def db_path(self) -> Path:
        return self.codex_home / "state_5.sqlite"

    @property
    def global_state_path(self) -> Path:
        return self.codex_home / ".codex-global-state.json"

    @property
    def active_account_marker(self) -> Path:
        return DEFAULT_SWITCHER_HOME / "active-account.txt"

    @property
    def active_auth_path(self) -> Path:
        return self.codex_home / "auth.json"

    @property
    def codex_config_path(self) -> Path:
        return self.codex_home / "config.toml"

    @property
    def mobile_codex_home(self) -> Path:
        return DEFAULT_SWITCHER_HOME / "mobile-codex-home"

    @property
    def mobile_codex_config_path(self) -> Path:
        return self.mobile_codex_home / "config.toml"

    @property
    def accounts_dir(self) -> Path:
        return DEFAULT_SWITCHER_HOME / "accounts"

    @property
    def usage_path(self) -> Path:
        return DEFAULT_SWITCHER_HOME / "usage.json"

    @property
    def notification_devices_path(self) -> Path:
        return DEFAULT_SWITCHER_HOME / "phone-notification-devices.json"

    @property
    def live_activities_path(self) -> Path:
        return DEFAULT_SWITCHER_HOME / "phone-live-activities.json"

    def codex_executable(self) -> Path:
        if self.codex_path.exists():
            return self.codex_path
        resolved = shutil.which("codex")
        if resolved:
            return Path(resolved)
        for directory in CODEX_CHILD_PATH_PREFIXES:
            candidate = Path(directory) / "codex"
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate
        return DEFAULT_CODEX

    def active_auth_fingerprint(self) -> str:
        try:
            return hashlib.sha256(self.active_auth_path.read_bytes()).hexdigest()
        except OSError:
            return ""

    def has_running_jobs(self) -> bool:
        with JOBS_LOCK:
            return any(job.get("status") == "running" for job in JOBS.values())

    def app_server_auth_status(self) -> dict:
        active_fingerprint = self.active_auth_fingerprint()
        with self._app_server_lock:
            client_running = self._app_server_client is not None
            in_sync = not client_running or self._app_server_auth_fingerprint == active_fingerprint
        restart_deferred = client_running and not in_sync and self.has_running_jobs()
        return {
            "clientRunning": client_running,
            "inSync": in_sync,
            "restartDeferred": restart_deferred,
        }

    def public_health(self) -> dict:
        return {
            "gateway": {
                "running": True,
            },
        }

    def diagnostic_health(self) -> dict:
        remote_desktop_status = {"available": False}
        remote_desktop = self.remote_desktop_gateway
        if remote_desktop is not None:
            public_status = getattr(remote_desktop, "public_status", None)
            if callable(public_status):
                try:
                    remote_desktop_status = public_status()
                except Exception as exc:
                    remote_desktop_status = {
                        "available": False,
                        "error": truncate_text(str(exc), 160),
                    }
            else:
                remote_desktop_status = {"available": True}

        return {
            "gateway": {
                "running": True,
                "version": read_marker(DEFAULT_SWITCHER_HOME / "gateway-version", "dev"),
            },
            "accounts": {
                "active": self.active_account_name(),
                "auth": self.app_server_auth_status(),
            },
            "turns": {
                "running": self.has_running_jobs(),
            },
            "notifications": {
                "configured": not isinstance(self.push_notifier, DisabledPushNotifier),
            },
            "remoteDesktop": remote_desktop_status,
            "localWeb": {
                "available": True,
                "sessionSeconds": LOCAL_WEB_SESSION_TIMEOUT_SECONDS,
            },
        }

    def close_app_server_if_auth_changed_and_idle(self):
        with self._app_server_lock:
            self._close_app_server_if_auth_changed_and_idle_locked()

    def close_app_server_client(self):
        with self._app_server_lock:
            self._close_app_server_client_locked()

    def ensure_app_server_ready_for_new_turn(self):
        with self._app_server_lock:
            stale_reason = self.active_account_auth_stale_reason()
            if stale_reason:
                account = self.active_account_name()
                raise RuntimeError(f"Refresh the {account} login before starting a Codex turn: {stale_reason}")
            active_fingerprint = self.active_auth_fingerprint()
            if self._app_server_client is None or self._app_server_auth_fingerprint == active_fingerprint:
                return
            if self.has_running_jobs():
                raise RuntimeError("Codex is still finishing a turn under the previous account. Try again after it finishes.")
            self._close_app_server_client_locked()

    def _close_app_server_client_locked(self):
        if self._app_server_client is None:
            return
        try:
            self._app_server_client.close()
        finally:
            self._app_server_client = None

    def _close_app_server_if_auth_changed_and_idle_locked(self):
        if self._app_server_client is None:
            return
        if self._app_server_auth_fingerprint == self.active_auth_fingerprint():
            return
        if self.has_running_jobs():
            return
        self._close_app_server_client_locked()

    def app_server_client(self) -> CodexAppServerClient:
        with self._app_server_lock:
            auth_fingerprint = self.active_auth_fingerprint()
            self._close_app_server_if_auth_changed_and_idle_locked()

            if self._app_server_client is None:
                env = codex_child_env(self.codex_home)
                self._app_server_client = CodexAppServerClient(
                    codex_path=self.codex_executable(),
                    cwd=self.app_server_cwd,
                    process_factory=self.app_server_process_factory,
                    id_factory=self.app_server_id_factory,
                    notification_handler=self.handle_app_server_notification,
                    env=env,
                    allow_dangerous=self.allow_dangerous,
                )
                self._app_server_auth_fingerprint = auth_fingerprint
            return self._app_server_client

    def job_response(self, job: dict, after_event_seq: int | None = None) -> dict:
        return {
            "activeAccount": self.active_account_name(),
            "appServerAuth": self.app_server_auth_status(),
            "job": public_job(job, after_event_seq),
        }

    def app_server_status(self) -> dict:
        response = self.app_server_client().start()
        return {
            "ok": True,
            "response": response,
        }

    def handle_app_server_notification(self, message: dict):
        thread_id = extract_app_server_thread_id(message)
        turn_id = extract_app_server_turn_id(message)
        method = str(message.get("method") or "")
        params = message.get("params") or {}
        if not isinstance(params, dict):
            params = {}
        event = app_server_notification_event(message)
        delta = str(params.get("delta") or "") if method == "item/agentMessage/delta" else ""
        turn_finished = False
        stale_auth_error = ""
        push_job = None

        with JOBS_LOCK:
            candidates = []
            for job in JOBS.values():
                if job.get("status") != "running":
                    continue
                if turn_id and job.get("turnId") == turn_id:
                    candidates.append(job)
                    continue
                if thread_id and job.get("threadId") == thread_id:
                    candidates.append(job)

            if not candidates:
                return

            job = max(candidates, key=lambda item: int(item.get("updatedAt") or item.get("createdAt") or 0))
            now = int(time.time())
            job["updatedAt"] = now
            if thread_id:
                job["threadId"] = thread_id
            if turn_id:
                job["turnId"] = turn_id
            if delta:
                job["lastMessage"] = str(job.get("lastMessage") or "") + delta
                job["output"] = job["lastMessage"]
                event = app_server_agent_delta_event(job, params)
            if event and event.get("kind") == "message":
                cache_thread_message(
                    str(job.get("threadId") or thread_id),
                    str(event.get("id") or ""),
                    str(event.get("body") or ""),
                    int(event.get("timestamp") or now),
                )
            append_job_event(job, event)
            self.record_connector_auth_warning_event(event)
            if method == "turn/completed":
                error_message = app_server_turn_error(params)
                if error_message:
                    job["status"] = "failed"
                    job["error"] = error_message
                    if is_stale_auth_message(error_message):
                        stale_auth_error = error_message
                else:
                    job["status"] = "completed"
                turn_finished = True
            elif method in {"turn/failed", "turn/error"}:
                error_message = compact_json(message.get("params") or {})
                job["status"] = "failed"
                job["error"] = error_message
                if is_stale_auth_message(error_message):
                    stale_auth_error = error_message
                turn_finished = True
            if turn_finished:
                push_job = self.prepare_turn_completion_push_locked(job)

        if turn_finished:
            if push_job:
                self.send_turn_completion_push(push_job)
            if stale_auth_error:
                self.mark_active_account_auth_stale(stale_auth_error)
                self.close_app_server_client()
            else:
                self.close_app_server_if_auth_changed_and_idle()
                with self.auth_file_lock():
                    self.sync_active_auth_to_active_profile()

    def active_account_name(self) -> str:
        return read_marker(self.active_account_marker, "unknown")

    def connect(self):
        return sqlite3.connect(f"file:{self.db_path}?mode=ro", uri=True, timeout=5)

    def list_threads(self) -> list[dict]:
        app_server_threads = self.list_threads_app_server()
        if app_server_threads is not None and (app_server_threads or not self.db_path.exists()):
            return self.apply_pinned_state(app_server_threads)
        return self.apply_pinned_state(self.list_threads_state_db())

    def list_threads_app_server(self) -> list[dict] | None:
        try:
            client = self.app_server_client()
            client.start()
            response = client.thread_list(limit=200)
        except Exception:
            return None

        raw_threads = response.get("data")
        if not isinstance(raw_threads, list):
            return None
        reasoning_by_thread_id = self.reasoning_effort_by_thread_id()
        return [
            self.apply_thread_reasoning_effort(app_server_thread_to_phone_thread(thread), reasoning_by_thread_id)
            for thread in raw_threads
            if isinstance(thread, dict) and str(thread.get("id") or "").strip()
        ]

    def list_threads_state_db(self) -> list[dict]:
        if not self.db_path.exists():
            return []
        with self.connect() as conn:
            conn.row_factory = sqlite3.Row
            try:
                rows = conn.execute(
                    """
                    select id, title, cwd, rollout_path, updated_at, created_at, source, thread_source, reasoning_effort
                    from threads
                    where archived = 0
                    order by updated_at desc
                    limit 200
                    """
                ).fetchall()
            except sqlite3.OperationalError:
                rows = conn.execute(
                    """
                    select id, title, cwd, rollout_path, updated_at, created_at, source, thread_source, null as reasoning_effort
                    from threads
                    where archived = 0
                    order by updated_at desc
                    limit 200
                    """
                ).fetchall()
        threads = [self.row_to_thread(row) for row in rows]
        return threads

    def get_thread(self, thread_id: str) -> dict | None:
        app_server_thread = self.get_thread_app_server(thread_id)
        if app_server_thread is not None:
            return self.apply_pinned_state_to_thread(app_server_thread)
        return self.apply_pinned_state_to_thread(self.get_thread_state_db(thread_id))

    def apply_pinned_state(self, threads: list[dict]) -> list[dict]:
        rank_by_id = pinned_thread_rank_by_id(self.global_state_path)
        return [apply_pinned_state(thread, rank_by_id) for thread in threads]

    def apply_pinned_state_to_thread(self, thread: dict | None) -> dict | None:
        if thread is None:
            return None
        return apply_pinned_state(thread, pinned_thread_rank_by_id(self.global_state_path))

    def get_thread_app_server(self, thread_id: str) -> dict | None:
        thread_id = str(thread_id or "").strip()
        if not thread_id:
            return None
        try:
            client = self.app_server_client()
            client.start()
            response = client.thread_read(thread_id, include_turns=True)
        except Exception:
            return None
        thread = response.get("thread")
        if not isinstance(thread, dict):
            return None
        return self.apply_thread_reasoning_effort(
            app_server_thread_to_phone_thread(thread, include_messages=True),
            self.reasoning_effort_by_thread_id(),
        )

    def get_thread_state_db(self, thread_id: str) -> dict | None:
        with self.connect() as conn:
            conn.row_factory = sqlite3.Row
            try:
                row = conn.execute(
                    """
                    select id, title, cwd, rollout_path, updated_at, created_at, source, thread_source, reasoning_effort
                    from threads
                    where id = ?
                    limit 1
                    """,
                    (thread_id,),
                ).fetchone()
            except sqlite3.OperationalError:
                row = conn.execute(
                    """
                    select id, title, cwd, rollout_path, updated_at, created_at, source, thread_source, null as reasoning_effort
                    from threads
                    where id = ?
                    limit 1
                    """,
                    (thread_id,),
                ).fetchone()
        return self.row_to_thread(row) if row else None

    def reasoning_effort_by_thread_id(self) -> dict[str, str]:
        if not self.db_path.exists():
            return {}
        try:
            with self.connect() as conn:
                conn.row_factory = sqlite3.Row
                rows = conn.execute(
                    "select id, reasoning_effort from threads where reasoning_effort is not null"
                ).fetchall()
        except sqlite3.Error:
            return {}
        efforts = {}
        for row in rows:
            effort = str(row["reasoning_effort"] or "").strip()
            if effort:
                efforts[str(row["id"])] = effort
        return efforts

    def apply_thread_reasoning_effort(self, thread: dict, reasoning_by_thread_id: dict[str, str]) -> dict:
        thread_id = str(thread.get("id") or "").strip()
        if thread_id and not thread.get("reasoningEffort"):
            thread["reasoningEffort"] = reasoning_by_thread_id.get(thread_id)
        return thread

    def active_job_for_thread(self, thread_id: str) -> dict | None:
        thread_id = str(thread_id or "").strip()
        if not thread_id:
            return None
        with JOBS_LOCK:
            jobs = [
                dict(job)
                for job in JOBS.values()
                if job.get("threadId") == thread_id and job.get("status") == "running"
            ]
        if not jobs:
            return None
        return public_job(max(jobs, key=lambda job: int(job.get("updatedAt") or job.get("createdAt") or 0)))

    def active_jobs(self) -> list[dict]:
        with JOBS_LOCK:
            jobs = [
                dict(job)
                for job in JOBS.values()
                if job.get("status") == "running"
            ]
        return [
            public_job(job)
            for job in sorted(
            jobs,
            key=lambda job: int(job.get("updatedAt") or job.get("createdAt") or 0),
            reverse=True,
            )
        ]

    def rename_thread(self, thread_id: str, name: str) -> dict:
        thread_id = str(thread_id or "").strip()
        name = str(name or "").strip()
        if not thread_id:
            raise ValueError("Thread id is required")
        if not name:
            raise ValueError("Thread name is required")
        client = self.app_server_client()
        client.start()
        return client.thread_set_name(thread_id, name)

    def archive_thread(self, thread_id: str) -> dict:
        thread_id = str(thread_id or "").strip()
        if not thread_id:
            raise ValueError("Thread id is required")
        client = self.app_server_client()
        client.start()
        return client.thread_archive(thread_id)

    def set_thread_pinned(self, thread_id: str, pinned: bool):
        thread_id = str(thread_id or "").strip()
        if not thread_id:
            raise ValueError("Thread id is required")
        if not isinstance(pinned, bool):
            raise ValueError("Pinned must be a boolean")

        payload = read_json_object(self.global_state_path)
        existing_ids = ordered_thread_ids(payload.get("pinned-thread-ids"))
        without_thread = [existing_id for existing_id in existing_ids if existing_id != thread_id]
        payload["pinned-thread-ids"] = ([thread_id] + without_thread) if pinned else without_thread
        write_json_object_atomic(self.global_state_path, payload)

    def steer_turn(self, thread_id: str, job_id: str, text: str) -> dict:
        thread_id = str(thread_id or "").strip()
        job_id = str(job_id or "").strip()
        text = str(text or "").strip()
        if not thread_id:
            raise ValueError("Thread id is required")
        if not job_id:
            raise ValueError("Job id is required")
        if not text:
            raise ValueError("Steer text is empty")

        with JOBS_LOCK:
            job = JOBS.get(job_id)
            if not job or job.get("threadId") != thread_id:
                raise LookupError("Job not found")
            if job.get("status") != "running":
                raise RuntimeError("Codex turn is not running")
            turn_id = str(job.get("turnId") or "").strip()
            if not turn_id:
                raise RuntimeError("This Codex turn does not support steering yet")

        client = self.app_server_client()
        client.start()
        client.turn_steer(thread_id, turn_id, text)

        with JOBS_LOCK:
            job = JOBS[job_id]
            job["updatedAt"] = int(time.time())
            append_job_event(
                job,
                make_stream_event(
                    f"steer.{int(time.time())}",
                    "context",
                    "completed",
                    "Steer sent",
                    text,
                    raw_type="turn.steer",
                ),
            )
            return dict(job)

    def stop_turn(self, thread_id: str, job_id: str) -> dict:
        thread_id = str(thread_id or "").strip()
        job_id = str(job_id or "").strip()
        if not thread_id:
            raise ValueError("Thread id is required")
        if not job_id:
            raise ValueError("Job id is required")

        with JOBS_LOCK:
            job = JOBS.get(job_id)
            if not job or job.get("threadId") != thread_id:
                raise LookupError("Job not found")
            if job.get("status") != "running":
                return dict(job)
            turn_id = str(job.get("turnId") or "").strip()
            process = JOB_PROCESSES.get(job_id)

        if turn_id:
            client = self.app_server_client()
            client.start()
            client.turn_interrupt(thread_id, turn_id)
        elif process is not None and process.poll() is None:
            process.terminate()

        with JOBS_LOCK:
            job = JOBS[job_id]
            job["updatedAt"] = int(time.time())
            job["status"] = "canceled"
            append_job_event(
                job,
                make_stream_event(
                    f"turn.stopped.{int(time.time())}",
                    "status",
                    "completed",
                    "Turn stopped",
                    "Codex was stopped from the iPhone app.",
                    raw_type="turn.stopped",
                ),
            )
            return dict(job)

    def row_to_thread(self, row) -> dict:
        title = (row["title"] or "").strip()
        if not title:
            title = "Untitled"
        return {
            "id": row["id"],
            "title": title,
            "cwd": row["cwd"],
            "rolloutPath": row["rollout_path"],
            "updatedAt": row["updated_at"],
            "createdAt": row["created_at"],
            "source": row["source"],
            "threadSource": row["thread_source"],
            "reasoningEffort": row["reasoning_effort"],
        }

    def normalize_workspace(self, cwd: str) -> str:
        raw_path = str(cwd or "").strip()
        if not raw_path:
            raise ValueError("Workspace is required")
        path = Path(raw_path).expanduser()
        if not path.is_absolute():
            raise ValueError("Workspace must be an absolute path")
        if not path.exists() or not path.is_dir():
            raise ValueError("Workspace does not exist")
        return str(path.resolve())

    def prepare_workspace(self, cwd: str, create: bool = False) -> str:
        raw_path = str(cwd or "").strip()
        if not raw_path:
            raise ValueError("Workspace is required")
        path = Path(raw_path).expanduser()
        if not path.is_absolute():
            raise ValueError("Workspace must be an absolute path")
        if create:
            if path.exists() and not path.is_dir():
                raise ValueError("Workspace path exists but is not a directory")
            path.mkdir(parents=True, exist_ok=True)
        return self.normalize_workspace(str(path))

    def account_status_snapshot(self) -> dict:
        plugin_sync = self.ensure_plugin_connectivity()
        active_account = self.active_account_name()
        usage = self.read_usage()
        accounts = []
        profile_names = self.account_profile_names()
        names_by_lower = {name.lower(): name for name in profile_names}

        names = list(profile_names)
        for usage_name in sorted(usage):
            lowered = usage_name.lower()
            if lowered == "current" or lowered in names_by_lower:
                continue
            names_by_lower[lowered] = usage_name
            names.append(usage_name)

        for name in names:
            usage_entry = self.usage_entry_for_account(name, usage)
            accounts.append(self.account_status(name, usage_entry, active_account))

        snapshot = {
            "generatedAt": int(time.time()),
            "activeAccount": active_account,
            "appServerAuth": self.app_server_auth_status(),
            "plugins": self.plugin_statuses(),
            "mcpServers": self.mcp_server_statuses(),
            "pluginSync": plugin_sync,
            "accounts": accounts,
        }
        try:
            self.publish_live_activity_state(snapshot)
        except Exception:
            pass
        return snapshot

    def consume_rate_limit_reset_credit(self, raw_name: str = "") -> dict:
        requested_name = str(raw_name or "").strip()
        if requested_name:
            account_name = self.resolve_account_profile_name(requested_name)
            result = self.consume_rate_limit_reset_credit_for_account(account_name)
            self.record_rate_limit_reset_credit_consumed(account_name)
            snapshot = self.account_status_snapshot()
            snapshot["rateLimitReset"] = {
                "accountName": account_name,
                "result": result,
            }
            return snapshot

        client = self.app_server_client()
        client.start()
        result = client.request("account/rateLimitResetCredit/consume", {
            "creditType": "usage_limit",
            "idempotencyKey": f"codepilot-rate-limit-reset-{uuid.uuid4()}",
        })
        snapshot = self.account_status_snapshot()
        snapshot["rateLimitReset"] = result
        return snapshot

    def consume_rate_limit_reset_credit_for_account(self, account_name: str) -> dict:
        target_auth = self.accounts_dir / account_name / "auth.json"
        if not target_auth.is_file():
            raise LookupError(f"No auth profile named {account_name}")

        previous_marker = None
        previous_auth = None
        if self.active_account_marker.is_file():
            previous_marker = self.active_account_marker.read_text(encoding="utf-8")
        if self.active_auth_path.is_file():
            previous_auth = self.active_auth_path.read_bytes()

        previous_account = self.active_account_name()
        needs_restore = account_name != previous_account or target_auth.read_bytes() != (previous_auth or b"")
        idempotency_key = f"codepilot-rate-limit-reset-{account_name}-{uuid.uuid4()}"

        with RUN_LOCK:
            if needs_restore and self.has_running_jobs():
                raise RuntimeError("Cannot reset a different account while a Codex turn is running")

            try:
                if needs_restore:
                    self.install_account_for_app_server_context(account_name, target_auth)
                return self.consume_active_app_server_rate_limit_reset_credit(idempotency_key)
            finally:
                if needs_restore:
                    self.restore_app_server_account_context(previous_auth, previous_marker)

    def consume_active_app_server_rate_limit_reset_credit(self, idempotency_key: str) -> dict:
        client = self.app_server_client()
        client.start()
        return client.request("account/rateLimitResetCredit/consume", {
            "creditType": "usage_limit",
            "idempotencyKey": idempotency_key,
        })

    def install_account_for_app_server_context(self, account_name: str, profile_auth: Path):
        with self._app_server_lock:
            self._close_app_server_client_locked()
            with self.auth_file_lock():
                self.sync_active_auth_to_active_profile()
                self.install_auth_file(profile_auth, self.active_auth_path)
            self.active_account_marker.parent.mkdir(parents=True, exist_ok=True)
            self.active_account_marker.write_text(account_name + "\n", encoding="utf-8")

    def restore_app_server_account_context(self, previous_auth: bytes | None, previous_marker: str | None):
        with self._app_server_lock:
            self._close_app_server_client_locked()
            with self.auth_file_lock():
                if previous_auth is None:
                    try:
                        self.active_auth_path.unlink()
                    except FileNotFoundError:
                        pass
                else:
                    self.write_active_auth_bytes(previous_auth)

            if previous_marker is None:
                try:
                    self.active_account_marker.unlink()
                except FileNotFoundError:
                    pass
            else:
                self.active_account_marker.parent.mkdir(parents=True, exist_ok=True)
                self.active_account_marker.write_text(previous_marker, encoding="utf-8")

    def write_active_auth_bytes(self, payload: bytes):
        self.active_auth_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(
            prefix=".auth.json.codex-phone-restore.",
            suffix=".tmp",
            dir=str(self.active_auth_path.parent),
        )
        tmp_path = Path(tmp_name)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(payload)
            os.chmod(tmp_path, 0o600)
            tmp_path.replace(self.active_auth_path)
            os.chmod(self.active_auth_path, 0o600)
        except Exception:
            try:
                tmp_path.unlink()
            except OSError:
                pass
            raise

    def access_token_from_auth_file(self, auth_path: Path) -> str:
        try:
            payload = json.loads(auth_path.read_text(encoding="utf-8"))
        except FileNotFoundError as exc:
            raise LookupError("Account auth profile is missing") from exc
        except json.JSONDecodeError as exc:
            raise RuntimeError("Account auth profile is not valid JSON") from exc

        if not isinstance(payload, dict):
            raise RuntimeError("Account auth profile is not valid")
        tokens = payload.get("tokens")
        if not isinstance(tokens, dict):
            raise RuntimeError("Account auth profile has no tokens")
        access_token = str(tokens.get("access_token") or "").strip()
        if not access_token:
            raise RuntimeError("Account auth profile has no access token")
        return access_token

    def record_rate_limit_reset_credit_consumed(self, account_name: str):
        usage = self.read_usage()
        usage_key = account_name
        for existing_key in usage:
            if str(existing_key).casefold() == account_name.casefold():
                usage_key = existing_key
                break
        entry = usage.get(usage_key, {})
        if not isinstance(entry, dict):
            entry = {}
        remaining = optional_int(entry.get("rateLimitResetCreditsRemaining"))
        if remaining is not None:
            entry["rateLimitResetCreditsRemaining"] = max(0, remaining - 1)
        usage[usage_key] = entry
        write_json_object_atomic(self.usage_path, usage)

    def ensure_plugin_connectivity(self) -> dict:
        status = {
            "source": str(self.mobile_codex_config_path),
            "target": str(self.codex_config_path),
            "repairedAt": int(time.time()),
            "sourceAvailable": self.mobile_codex_config_path.is_file(),
            "addedPlugins": [],
            "addedMcpServers": [],
            "missingConnectorEnvVars": [],
        }
        if not status["sourceAvailable"]:
            return status

        source_config = self.read_toml_config(self.mobile_codex_config_path)
        target_config = self.read_toml_config(self.codex_config_path)
        source_plugins = source_config.get("plugins")
        source_mcp_servers = source_config.get("mcp_servers")
        target_plugins = target_config.get("plugins")
        target_mcp_servers = target_config.get("mcp_servers")
        if not isinstance(source_plugins, dict):
            source_plugins = {}
        if not isinstance(source_mcp_servers, dict):
            source_mcp_servers = {}
        if not isinstance(target_plugins, dict):
            target_plugins = {}
        if not isinstance(target_mcp_servers, dict):
            target_mcp_servers = {}

        missing_plugins = {
            str(plugin_id): settings if isinstance(settings, dict) else {}
            for plugin_id, settings in source_plugins.items()
            if str(plugin_id) not in target_plugins
        }
        missing_mcp_servers = {
            str(name): settings
            for name, settings in source_mcp_servers.items()
            if str(name) not in target_mcp_servers and isinstance(settings, dict)
        }

        for settings in [*source_mcp_servers.values(), *target_mcp_servers.values()]:
            if not isinstance(settings, dict):
                continue
            env_var = str(settings.get("bearer_token_env_var") or "").strip()
            if env_var and not str(codex_child_env(self.codex_home).get(env_var) or "").strip():
                status["missingConnectorEnvVars"].append(env_var)
        status["missingConnectorEnvVars"] = sorted(set(status["missingConnectorEnvVars"]), key=str.casefold)

        if not missing_plugins and not missing_mcp_servers:
            return status

        self.codex_config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            existing_text = self.codex_config_path.read_text(encoding="utf-8")
        except OSError:
            existing_text = ""

        lines = existing_text.rstrip().splitlines() if existing_text.strip() else []
        for plugin_id, settings in sorted(missing_plugins.items(), key=lambda item: item[0].casefold()):
            append_toml_table(lines, ["plugins", plugin_id], settings or {"enabled": True})
            status["addedPlugins"].append(plugin_id)
        for name, settings in sorted(missing_mcp_servers.items(), key=lambda item: item[0].casefold()):
            append_toml_table(lines, ["mcp_servers", name], settings)
            status["addedMcpServers"].append(name)

        next_text = "\n".join(lines).rstrip() + "\n"
        fd, tmp_name = tempfile.mkstemp(prefix=".config.", suffix=".tmp", dir=str(self.codex_config_path.parent))
        tmp_path = Path(tmp_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(next_text)
            tmp_path.replace(self.codex_config_path)
        except Exception:
            try:
                tmp_path.unlink()
            except OSError:
                pass
            raise

        return status

    def plugin_statuses(self) -> list[dict]:
        config = self.read_codex_config()
        raw_plugins = config.get("plugins")
        if not isinstance(raw_plugins, dict):
            return []

        statuses = []
        for plugin_id in sorted(raw_plugins, key=str.casefold):
            settings = raw_plugins.get(plugin_id)
            if not isinstance(settings, dict):
                settings = {}
            name, marketplace = self.split_plugin_id(plugin_id)
            metadata = self.plugin_metadata(name, marketplace)
            display_name = str(
                metadata.get("displayName")
                or metadata.get("name")
                or connector_display_name(name)
            )
            enabled = bool(settings.get("enabled", True))
            installed = bool(metadata)
            statuses.append({
                "id": plugin_id,
                "name": name,
                "marketplace": marketplace,
                "displayName": display_name,
                "enabled": enabled,
                "installed": installed,
                "status": "enabled" if enabled else "disabled",
                "description": str(metadata.get("shortDescription") or metadata.get("description") or ""),
            })
        return statuses

    def read_codex_config(self) -> dict:
        return self.read_toml_config(self.codex_config_path)

    def read_toml_config(self, config_path: Path) -> dict:
        try:
            data = parse_toml_config_text(config_path.read_text(encoding="utf-8"))
        except (OSError, SimpleTOMLDecodeError, json.JSONDecodeError):
            return {}
        return data if isinstance(data, dict) else {}

    def split_plugin_id(self, plugin_id: str) -> tuple[str, str]:
        raw = str(plugin_id or "").strip()
        if "@" not in raw:
            return raw, ""
        name, marketplace = raw.rsplit("@", 1)
        return name, marketplace

    def plugin_metadata(self, name: str, marketplace: str) -> dict:
        manifest = self.plugin_manifest_path(name, marketplace)
        if not manifest:
            return {}
        try:
            data = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        if not isinstance(data, dict):
            return {}
        interface = data.get("interface")
        if not isinstance(interface, dict):
            interface = {}
        return {
            "name": str(data.get("name") or name),
            "description": str(data.get("description") or ""),
            "displayName": str(interface.get("displayName") or ""),
            "shortDescription": str(interface.get("shortDescription") or ""),
        }

    def plugin_manifest_path(self, name: str, marketplace: str) -> Path | None:
        cache_root = self.codex_home / "plugins" / "cache"
        candidates = []
        if marketplace:
            candidates.append(cache_root / marketplace / name)
        candidates.extend(sorted(cache_root.glob(f"*/{name}"), key=lambda path: str(path)))
        for base in candidates:
            if not base.is_dir():
                continue
            versions = sorted(
                [path for path in base.iterdir() if path.is_dir()],
                key=lambda path: path.stat().st_mtime,
                reverse=True,
            )
            for version_dir in versions:
                manifest = version_dir / ".codex-plugin" / "plugin.json"
                if manifest.is_file():
                    return manifest
        return None

    def mcp_server_statuses(self) -> list[dict]:
        try:
            result = subprocess.run(
                [str(self.codex_executable()), "mcp", "list"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(self.app_server_cwd),
                env=codex_child_env(self.codex_home),
                timeout=15,
            )
        except Exception as exc:
            return [{
                "name": "mcp",
                "displayName": "MCP",
                "status": "unknown",
                "auth": "Unknown",
                "needsLogin": False,
                "canReconnect": False,
                "lastAuthWarningAt": None,
                "lastAuthWarningReason": truncate_text(str(exc), 240),
            }]

        statuses = self.parse_mcp_list_output(result.stdout)
        env = codex_child_env(self.codex_home)
        for item in statuses:
            bearer_token_env_var = str(item.get("bearerTokenEnvVar") or "").strip()
            if str(item.get("auth") or "").lower() == "bearer token" and bearer_token_env_var:
                if not str(env.get(bearer_token_env_var) or "").strip():
                    item["needsLogin"] = True
                    item["lastAuthWarningReason"] = f"Missing {bearer_token_env_var} in the gateway environment."
        warnings = self.active_connector_auth_warnings()
        for item in statuses:
            warning = warnings.get(str(item.get("name") or "").casefold())
            if not warning:
                continue
            item["lastAuthWarningAt"] = epoch_seconds(warning.get("lastSeenAt"))
            item["lastAuthWarningReason"] = str(warning.get("message") or "")
            item["needsLogin"] = True

        if result.returncode != 0:
            detail = "\n".join(part.strip() for part in (result.stderr, result.stdout) if part and part.strip())
            statuses.append({
                "name": "mcp",
                "displayName": "MCP",
                "status": "unknown",
                "auth": "Unknown",
                "needsLogin": False,
                "canReconnect": False,
                "lastAuthWarningAt": None,
                "lastAuthWarningReason": truncate_text(detail or f"codex mcp list exited {result.returncode}", 240),
            })
        return statuses

    def parse_mcp_list_output(self, output: str) -> list[dict]:
        servers = []
        for line in str(output or "").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("Name "):
                continue
            parts = re.split(r"\s{2,}", stripped)
            if len(parts) < 3:
                continue
            name = parts[0].strip()
            status = parts[-2].strip() if len(parts) >= 2 else ""
            auth = parts[-1].strip() if parts else ""
            bearer_token_env_var = parts[-3].strip() if len(parts) >= 5 and auth.lower() == "bearer token" else ""
            if not name or name.lower() in {"name", "-"}:
                continue
            auth_lower = auth.lower()
            servers.append({
                "name": name,
                "displayName": connector_display_name(name),
                "status": status,
                "auth": auth,
                "bearerTokenEnvVar": "" if bearer_token_env_var == "-" else bearer_token_env_var,
                "needsLogin": "not logged in" in auth_lower or "authrequired" in auth_lower or "invalid_token" in auth_lower,
                "canReconnect": "oauth" in auth_lower or "not logged in" in auth_lower,
                "lastAuthWarningAt": None,
                "lastAuthWarningReason": "",
            })
        return servers

    def active_connector_auth_warnings(self) -> dict:
        entry = self.usage_entry_for_account(self.active_account_name())
        warnings = entry.get("connectorAuthWarnings")
        if not isinstance(warnings, list):
            return {}
        result = {}
        for item in warnings:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or "").strip()
            if name:
                result[name.casefold()] = item
        return result

    def account_profile_names(self) -> list[str]:
        if not self.accounts_dir.exists():
            return []
        names = []
        for auth_path in self.accounts_dir.glob("*/auth.json"):
            if auth_path.is_file():
                names.append(auth_path.parent.name)
        return sorted(names, key=str.casefold)

    def register_notification_device(self, payload: dict) -> dict:
        raw_token = str(payload.get("token") or "")
        token = re.sub(r"[^0-9a-fA-F]", "", raw_token).lower()
        if not token:
            raise ValueError("Device token is required")
        environment = str(payload.get("environment") or "production").strip().lower()
        if environment not in {"development", "production"}:
            environment = "production"
        bundle_id = str(payload.get("bundleId") or DEFAULT_APNS_TOPIC).strip() or DEFAULT_APNS_TOPIC
        device = {
            "token": token,
            "environment": environment,
            "bundleId": bundle_id,
            "platform": str(payload.get("platform") or "ios"),
            "updatedAt": int(time.time()),
        }
        devices = [
            item for item in self.read_notification_devices()
            if not (
                item.get("token") == token
                and item.get("environment") == environment
                and item.get("bundleId") == bundle_id
            )
        ]
        devices.insert(0, device)
        self.write_notification_devices(devices[:20])
        return {"ok": True, "deviceCount": len(devices[:20])}

    def register_live_activity(self, payload: dict) -> dict:
        activity_id = str(payload.get("activityId") or "").strip()
        if not activity_id:
            raise ValueError("Live Activity identifier is required")
        token = re.sub(r"[^0-9a-fA-F]", "", str(payload.get("pushToken") or "")).lower()
        if not token:
            raise ValueError("Live Activity push token is required")
        environment = str(payload.get("environment") or "production").strip().lower()
        if environment not in {"development", "production"}:
            raise ValueError("Live Activity environment must be development or production")
        bundle_id = str(payload.get("bundleId") or DEFAULT_APNS_TOPIC).strip() or DEFAULT_APNS_TOPIC
        existing = next(
            (item for item in self.read_live_activities() if item.get("activityId") == activity_id),
            None,
        )
        registration = {
            "activityId": activity_id,
            "pushToken": token,
            "environment": environment,
            "bundleId": bundle_id,
            "updatedAt": int(time.time()),
        }
        if existing and existing.get("pushToken") == token:
            registration["lastFingerprint"] = str(existing.get("lastFingerprint") or "")
        registrations = [
            item for item in self.read_live_activities()
            if item.get("activityId") != activity_id
        ]
        registrations.insert(0, registration)
        self.write_live_activities(registrations[:20])
        return {"ok": True, "activityCount": len(registrations[:20])}

    def unregister_live_activity(self, activity_id: str) -> dict:
        activity_id = str(activity_id or "").strip()
        registrations = [
            item for item in self.read_live_activities()
            if item.get("activityId") != activity_id
        ]
        self.write_live_activities(registrations)
        return {"ok": True, "activityCount": len(registrations)}

    def read_live_activities(self) -> list[dict]:
        try:
            data = json.loads(self.live_activities_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return []
        if not isinstance(data, list):
            return []
        return [item for item in data if isinstance(item, dict)]

    def write_live_activities(self, registrations: list[dict]):
        self.live_activities_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(
            prefix=".phone-live-activities.",
            suffix=".tmp",
            dir=str(self.live_activities_path.parent),
        )
        tmp_path = Path(tmp_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(registrations, handle, ensure_ascii=False, indent=2, sort_keys=True)
                handle.write("\n")
            tmp_path.replace(self.live_activities_path)
        except Exception:
            with contextlib.suppress(OSError):
                tmp_path.unlink()
            raise

    def live_activity_content_state(self, snapshot: dict) -> dict:
        generated_at = int(snapshot.get("generatedAt") or time.time())
        accounts = [item for item in snapshot.get("accounts", []) if isinstance(item, dict)]
        buckets = []
        for account in accounts:
            bucket = self.account_credit_bucket(account)
            if bucket is not None:
                buckets.append(bucket)
        available = [item for item in buckets if not item["authStale"]]
        reported = [item for item in available if item["remaining"] is not None]
        remaining = [max(0, min(100, int(item["remaining"]))) for item in reported]
        if remaining and sum(remaining) > 0:
            progress = sum(remaining) / (len(remaining) * 100)
            return {
                "kind": "available",
                "percent": round(progress * 100),
                "progress": progress,
                "usableAccountCount": sum(1 for value in remaining if value > 0),
                "reportedAccountCount": len(reported),
                "nextRefreshAt": None,
                "refreshLabel": None,
                "generatedAt": generated_at,
            }
        future = [item for item in available if int(item.get("resetAt") or 0) > generated_at]
        if future:
            next_refresh = min(future, key=lambda item: int(item["resetAt"]))
            remaining_seconds = max(0, int(next_refresh["resetAt"]) - generated_at)
            window_seconds = max(60, int(next_refresh.get("windowMins") or 0) * 60)
            return {
                "kind": "refilling",
                "percent": None,
                "progress": max(0, min(1, 1 - remaining_seconds / window_seconds)),
                "usableAccountCount": 0,
                "reportedAccountCount": len(reported),
                "nextRefreshAt": int(next_refresh["resetAt"]),
                "refreshLabel": next_refresh["label"],
                "generatedAt": generated_at,
            }
        kind = "authenticationRequired" if accounts and all(bool(item.get("authStale")) for item in accounts) else "unavailable"
        return {
            "kind": kind,
            "percent": None,
            "progress": 0,
            "usableAccountCount": 0,
            "reportedAccountCount": len(reported),
            "nextRefreshAt": None,
            "refreshLabel": None,
            "generatedAt": generated_at,
        }

    def account_credit_bucket(self, account: dict) -> dict | None:
        windows = []
        if account.get("fiveHourRemainingPercent") is not None or account.get("fiveHourResetsAt") is not None:
            windows.append({
                "remaining": account.get("fiveHourRemainingPercent"),
                "resetAt": account.get("fiveHourResetsAt"),
                "windowMins": account.get("fiveHourWindowMins"),
                "label": "5h",
            })
        if account.get("weeklyRemainingPercent") is not None or account.get("weeklyResetsAt") is not None:
            windows.append({
                "remaining": account.get("weeklyRemainingPercent"),
                "resetAt": account.get("weeklyResetsAt"),
                "windowMins": account.get("weeklyWindowMins"),
                "label": "weekly",
            })
        if not windows:
            return None

        known_remaining = [
            max(0, min(100, int(window["remaining"])))
            for window in windows
            if window.get("remaining") is not None
        ]
        effective_remaining = min(known_remaining) if known_remaining else None
        label = str(windows[0].get("label") or "credit")
        reset_at = None
        window_mins = windows[0].get("windowMins")

        if effective_remaining is not None and effective_remaining > 0:
            for window in windows:
                if window.get("remaining") is not None and max(0, min(100, int(window["remaining"]))) == effective_remaining:
                    label = str(window.get("label") or label)
                    window_mins = window.get("windowMins")
                    break
        else:
            depleted = [
                window for window in windows
                if window.get("remaining") is not None
                and int(window.get("remaining") or 0) <= 0
                and window.get("resetAt") is not None
            ]
            limiting = max(depleted, key=lambda item: int(item.get("resetAt") or 0), default=windows[0])
            label = str(limiting.get("label") or label)
            reset_at = limiting.get("resetAt")
            window_mins = limiting.get("windowMins")

        return {
            "remaining": effective_remaining,
            "resetAt": reset_at,
            "windowMins": window_mins,
            "label": label,
            "authStale": bool(account.get("authStale")),
        }

    def publish_live_activity_state(self, snapshot: dict):
        registrations = self.read_live_activities()
        if not registrations:
            return
        content_state = self.live_activity_content_state(snapshot)
        fingerprint_payload = dict(content_state)
        fingerprint_payload.pop("generatedAt", None)
        fingerprint = hashlib.sha256(
            json.dumps(fingerprint_payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()
        pending = [item for item in registrations if item.get("lastFingerprint") != fingerprint]
        if not pending:
            return
        invalid_activity_ids = set(self.push_notifier.send_live_activity(pending, content_state) or [])
        pending_ids = {item.get("activityId") for item in pending}
        next_registrations = []
        for item in registrations:
            activity_id = item.get("activityId")
            if activity_id in invalid_activity_ids:
                continue
            copied = dict(item)
            if activity_id in pending_ids:
                copied["lastFingerprint"] = fingerprint
            next_registrations.append(copied)
        self.write_live_activities(next_registrations)

    def read_notification_devices(self) -> list[dict]:
        try:
            data = json.loads(self.notification_devices_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return []
        if not isinstance(data, list):
            return []
        return [item for item in data if isinstance(item, dict)]

    def write_notification_devices(self, devices: list[dict]):
        self.notification_devices_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(prefix=".phone-notification-devices.", suffix=".tmp", dir=str(self.notification_devices_path.parent))
        tmp_path = Path(tmp_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(devices, handle, ensure_ascii=False, indent=2, sort_keys=True)
                handle.write("\n")
            tmp_path.replace(self.notification_devices_path)
        except Exception:
            try:
                tmp_path.unlink()
            except OSError:
                pass
            raise

    def prepare_turn_completion_push_locked(self, job: dict) -> dict | None:
        if job.get("_pushNotificationPreparedAt") is not None or job.get("_pushNotificationSentAt") is not None:
            return None
        if job.get("status") not in {"completed", "failed", "canceled"}:
            return None
        job["_pushNotificationPreparedAt"] = int(time.time())
        return dict(job)

    def send_turn_completion_push(self, job: dict):
        devices = self.read_notification_devices()
        if not devices:
            return
        sent_at = int(time.time())
        with JOBS_LOCK:
            live_job = JOBS.get(str(job.get("id") or ""))
            if live_job is not None:
                live_job["_pushNotificationSentAt"] = sent_at
        job["_pushNotificationSentAt"] = sent_at
        notification = self.turn_completion_notification(job)
        self.push_notifier.send_turn_completion(devices, notification)

    def turn_completion_notification(self, job: dict) -> dict:
        status = str(job.get("status") or "")
        if status == "failed":
            title = "Codex failed"
            body = "Open CodePilot to review the error."
        else:
            title = "Codex finished"
            body = "Open CodePilot to view the result."
        return {
            "title": title,
            "body": body,
            "threadId": str(job.get("threadId") or ""),
            "jobId": str(job.get("id") or ""),
        }

    def switch_account(self, raw_name: str) -> dict:
        account_name = self.resolve_account_profile_name(raw_name)

        if account_name == self.active_account_name():
            return self.account_status_snapshot()

        if self.has_running_jobs():
            raise RuntimeError("Cannot switch account while a Codex turn is running")

        profile_auth = self.accounts_dir / account_name / "auth.json"
        if not profile_auth.is_file():
            raise LookupError(f"No auth profile named {account_name}")

        stale_reason = self.account_auth_stale_reason(account_name)
        if stale_reason:
            raise RuntimeError(
                f"{account_name} auth is stale; refresh this account login before switching. "
                f"{truncate_text(stale_reason, 240)}"
            )

        with self._app_server_lock:
            if self.has_running_jobs():
                raise RuntimeError("Cannot switch account while a Codex turn is running")
            self._close_app_server_client_locked()
            with self.auth_file_lock():
                self.sync_active_auth_to_active_profile()
                self.install_auth_file(profile_auth, self.active_auth_path)

        self.active_account_marker.parent.mkdir(parents=True, exist_ok=True)
        self.active_account_marker.write_text(account_name + "\n", encoding="utf-8")
        self.record_manual_switch(account_name)
        return self.account_status_snapshot()

    def resolve_account_profile_name(self, raw_name: str) -> str:
        requested_name = str(raw_name or "").strip()
        if not requested_name:
            raise ValueError("Account name is required")

        profile_names = self.account_profile_names()
        names_by_folded = {name.casefold(): name for name in profile_names}
        account_name = names_by_folded.get(requested_name.casefold())
        if not account_name:
            raise LookupError(f"No profile named {requested_name}")
        return account_name

    def sanitized_new_account_profile_name(self, raw_name: str) -> str:
        name = str(raw_name or "").strip()
        for separator in ("/", ":", "\\"):
            name = name.replace(separator, "-")
        if not name or name in {".", ".."} or "\0" in name:
            raise ValueError("Account name is required")

        for existing_name in self.account_profile_names():
            if existing_name.casefold() == name.casefold():
                raise ValueError(f"A profile named {existing_name} already exists")
        return name

    def install_auth_file(self, source: Path, target: Path):
        if not source.is_file():
            raise LookupError(f"No auth file at {source}")
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(prefix=".auth.json.codex-phone.", suffix=".tmp", dir=str(target.parent))
        tmp_path = Path(tmp_name)
        try:
            os.close(fd)
            shutil.copyfile(source, tmp_path)
            os.chmod(tmp_path, 0o600)
            tmp_path.replace(target)
            os.chmod(target, 0o600)
        except Exception:
            try:
                tmp_path.unlink()
            except OSError:
                pass
            raise

    @contextlib.contextmanager
    def auth_file_lock(self):
        DEFAULT_SWITCHER_HOME.mkdir(parents=True, exist_ok=True)
        lock_path = DEFAULT_SWITCHER_HOME / "auth-files.lock"
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)

    def auth_file_snapshot(self, auth_path: Path) -> dict:
        data = json.loads(auth_path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("auth.json is not an object")
        tokens = data.get("tokens")
        if not isinstance(tokens, dict):
            tokens = {}
        return {
            "accountId": str(tokens.get("account_id") or ""),
            "lastRefresh": parse_iso_datetime(str(data.get("last_refresh") or "")),
        }

    def sync_active_auth_to_active_profile(self) -> bool:
        account_name = self.active_account_name()
        if not account_name or account_name == "unknown":
            return False
        profile_auth = self.accounts_dir / account_name / "auth.json"
        if not self.active_auth_path.is_file() or not profile_auth.is_file():
            return False
        try:
            if self.active_auth_path.read_bytes() == profile_auth.read_bytes():
                return False
            active = self.auth_file_snapshot(self.active_auth_path)
            profile = self.auth_file_snapshot(profile_auth)
        except (OSError, json.JSONDecodeError, ValueError):
            return False

        active_account = str(active.get("accountId") or "")
        profile_account = str(profile.get("accountId") or "")
        if active_account and profile_account and active_account != profile_account:
            return False

        active_refresh = active.get("lastRefresh")
        profile_refresh = profile.get("lastRefresh")
        if active_refresh is not None and profile_refresh is not None and active_refresh < profile_refresh:
            return False

        self.install_auth_file(self.active_auth_path, profile_auth)
        return True

    def run_access_token_login(self, temp_codex_home: Path, access_token: str):
        if self.login_runner is not None:
            self.login_runner(temp_codex_home, access_token)
            return

        temp_codex_home.mkdir(parents=True, exist_ok=True)
        env = codex_child_env(temp_codex_home)
        result = subprocess.run(
            [str(self.codex_executable()), "login", "--with-access-token"],
            input=access_token + "\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(self.app_server_cwd),
            env=env,
            timeout=120,
        )
        if result.returncode != 0:
            output = "\n".join(part.strip() for part in [result.stderr, result.stdout] if part and part.strip())
            raise RuntimeError(f"Codex login failed: {truncate_text(output or 'unknown error', 500)}")

    def install_refreshed_account_auth(self, account_name: str, generated_auth: Path):
        is_active_account = account_name == self.active_account_name()
        if is_active_account and self.has_running_jobs():
            raise RuntimeError("Cannot refresh active account auth while a Codex turn is running")

        profile_auth = self.accounts_dir / account_name / "auth.json"
        if is_active_account:
            with self._app_server_lock:
                if self.has_running_jobs():
                    raise RuntimeError("Cannot refresh active account auth while a Codex turn is running")
                self._close_app_server_client_locked()
                with self.auth_file_lock():
                    self.install_auth_file(generated_auth, profile_auth)
                    self.install_auth_file(generated_auth, self.active_auth_path)
        else:
            with self.auth_file_lock():
                self.install_auth_file(generated_auth, profile_auth)

        self.record_remote_login_refresh(account_name)

    def install_new_account_auth(self, account_name: str, generated_auth: Path):
        account_name = self.sanitized_new_account_profile_name(account_name)
        profile_auth = self.accounts_dir / account_name / "auth.json"
        with self.auth_file_lock():
            self.install_auth_file(generated_auth, profile_auth)
        self.record_remote_login_add(account_name)

    def refresh_account_auth_with_access_token(self, raw_name: str, access_token: str) -> dict:
        account_name = self.resolve_account_profile_name(raw_name)
        token = str(access_token or "").strip()
        if not token:
            raise ValueError("Access token is required")

        is_active_account = account_name == self.active_account_name()
        if is_active_account and self.has_running_jobs():
            raise RuntimeError("Cannot refresh active account auth while a Codex turn is running")

        DEFAULT_SWITCHER_HOME.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="codex-auth-refresh-", dir=str(DEFAULT_SWITCHER_HOME)) as temp_dir:
            temp_codex_home = Path(temp_dir)
            self.run_access_token_login(temp_codex_home, token)
            generated_auth = temp_codex_home / "auth.json"
            if not generated_auth.is_file():
                raise RuntimeError("Codex login did not produce auth.json")

            self.install_refreshed_account_auth(account_name, generated_auth)

        return self.account_status_snapshot()

    def start_remote_account_login(self, raw_name: str) -> dict:
        account_name = self.resolve_account_profile_name(raw_name)
        if account_name == self.active_account_name() and self.has_running_jobs():
            raise RuntimeError("Cannot refresh active account auth while a Codex turn is running")

        return self.start_remote_login_session(account_name, mode="refresh")

    def start_remote_new_account_login(self, raw_name: str) -> dict:
        account_name = self.sanitized_new_account_profile_name(raw_name)
        return self.start_remote_login_session(account_name, mode="add")

    def start_remote_login_session(self, account_name: str, mode: str) -> dict:
        with self._remote_login_start_lock:
            self.ensure_remote_login_capacity()
            return self._start_remote_login_session(account_name, mode)

    def _start_remote_login_session(self, account_name: str, mode: str) -> dict:
        DEFAULT_SWITCHER_HOME.mkdir(parents=True, exist_ok=True)
        session_id = secrets.token_urlsafe(16)
        temp_codex_home = Path(tempfile.mkdtemp(prefix="codex-remote-login-", dir=str(DEFAULT_SWITCHER_HOME)))
        output_queue = queue.Queue()
        env = codex_child_env(temp_codex_home)
        env["CI"] = "1"
        env.setdefault("BROWSER", "/usr/bin/false")
        process = self.login_process_factory(
            [str(self.codex_executable()), "login"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(self.app_server_cwd),
            env=env,
            bufsize=1,
        )
        session = {
            "id": session_id,
            "accountName": account_name,
            "mode": mode,
            "status": "starting",
            "authUrl": "",
            "output": "",
            "tempCodexHome": temp_codex_home,
            "process": process,
            "createdAt": int(time.time()),
        }
        with self._remote_login_lock:
            self._remote_login_sessions[session_id] = session

        def read_output():
            try:
                for line in process.stdout or []:
                    output_queue.put(str(line))
            finally:
                output_queue.put(None)

        threading.Thread(target=read_output, daemon=True).start()
        deadline = time.monotonic() + REMOTE_LOGIN_URL_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            try:
                line = output_queue.get(timeout=0.2)
            except queue.Empty:
                if process.poll() is not None:
                    break
                continue
            if line is None:
                break
            self._record_remote_login_output(session_id, line)
            match = REMOTE_LOGIN_AUTH_URL_RE.search(line)
            if match:
                with self._remote_login_lock:
                    session["authUrl"] = match.group(0)
                    session["status"] = "waiting_for_browser"
                return self.public_remote_login_session(session)

        output = str(session.get("output") or "").strip()
        self.cancel_remote_account_login(session_id)
        raise RuntimeError(f"Codex login did not provide a browser login URL. {truncate_text(output, 500)}")

    def start_remote_mcp_login(self, raw_name: str) -> dict:
        with self._remote_login_start_lock:
            self.ensure_remote_login_capacity()
            return self._start_remote_mcp_login(raw_name)

    def _start_remote_mcp_login(self, raw_name: str) -> dict:
        server_name = str(raw_name or "").strip()
        if not server_name:
            raise ValueError("MCP server name is required")

        known_servers = {str(item.get("name") or ""): item for item in self.mcp_server_statuses()}
        server = known_servers.get(server_name)
        if not server:
            raise LookupError(f"No MCP server named {server_name}")
        if not server.get("canReconnect"):
            raise RuntimeError(f"{server_name} does not expose an OAuth reconnect flow")

        session_id = secrets.token_urlsafe(16)
        output_queue = queue.Queue()
        env = codex_child_env(self.codex_home)
        env["CI"] = "1"
        env.setdefault("BROWSER", "/usr/bin/false")
        process = self.login_process_factory(
            [str(self.codex_executable()), "mcp", "login", server_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(self.app_server_cwd),
            env=env,
            bufsize=1,
        )
        session = {
            "id": session_id,
            "accountName": server_name,
            "mode": "mcp",
            "status": "starting",
            "authUrl": "",
            "output": "",
            "process": process,
            "createdAt": int(time.time()),
        }
        with self._remote_login_lock:
            self._remote_login_sessions[session_id] = session

        def read_output():
            try:
                for line in process.stdout or []:
                    output_queue.put(str(line))
            finally:
                output_queue.put(None)

        threading.Thread(target=read_output, daemon=True).start()
        deadline = time.monotonic() + REMOTE_LOGIN_URL_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            try:
                line = output_queue.get(timeout=0.2)
            except queue.Empty:
                if process.poll() is not None:
                    break
                continue
            if line is None:
                break
            self._record_remote_login_output(session_id, line)
            match = REMOTE_LOGIN_URL_RE.search(line)
            if match:
                with self._remote_login_lock:
                    session["authUrl"] = match.group(0).rstrip(".,)")
                    session["status"] = "waiting_for_browser"
                return self.public_remote_login_session(session)

        output = str(session.get("output") or "").strip()
        self.cancel_remote_account_login(session_id)
        raise RuntimeError(f"Codex MCP login did not provide a browser login URL. {truncate_text(output, 500)}")

    def _record_remote_login_output(self, session_id: str, line: str):
        with self._remote_login_lock:
            session = self._remote_login_sessions.get(session_id)
            if not session:
                return
            session["output"] = truncate_text(str(session.get("output") or "") + line, 8_000)

    def public_remote_login_session(self, session: dict) -> dict:
        return {
            "sessionId": str(session.get("id") or ""),
            "accountName": str(session.get("accountName") or ""),
            "status": str(session.get("status") or "unknown"),
            "authUrl": str(session.get("authUrl") or ""),
            "createdAt": int(session.get("createdAt") or 0),
        }

    def remote_account_login_status(self, session_id: str) -> dict:
        self.cleanup_expired_remote_login_sessions()
        with self._remote_login_lock:
            session = self._remote_login_sessions.get(str(session_id or "").strip())
            if not session:
                raise LookupError("Remote login session not found")
            return self.public_remote_login_session(session)

    def complete_remote_account_login(self, session_id: str, callback_url: str) -> dict:
        self.cleanup_expired_remote_login_sessions()
        session_id = str(session_id or "").strip()
        with self._remote_login_lock:
            session = self._remote_login_sessions.get(session_id)
            if not session:
                raise LookupError("Remote login session not found")
            if str(session.get("mode") or "") not in {"add", "refresh"}:
                raise ValueError("Remote login session is not an account login")
            session["status"] = "completing"

        try:
            local_callback_url = self.validated_remote_login_callback_url(session, callback_url)
            self.relay_remote_login_callback(local_callback_url)

            process = session["process"]
            returncode = process.wait(timeout=REMOTE_LOGIN_CALLBACK_TIMEOUT_SECONDS)
            if returncode != 0:
                output = str(session.get("output") or "").strip()
                raise RuntimeError(f"Codex login failed: {truncate_text(output or f'exit {returncode}', 500)}")

            generated_auth = Path(session["tempCodexHome"]) / "auth.json"
            if not generated_auth.is_file():
                raise RuntimeError("Codex login did not produce auth.json")

            if str(session.get("mode") or "") == "add":
                self.install_new_account_auth(str(session["accountName"]), generated_auth)
            else:
                self.install_refreshed_account_auth(str(session["accountName"]), generated_auth)
        except subprocess.TimeoutExpired as exc:
            self.cleanup_remote_account_login_session(session_id, terminate=True)
            raise RuntimeError("Timed out waiting for Codex login to finish") from exc
        except Exception:
            self.cleanup_remote_account_login_session(session_id, terminate=True)
            raise
        self.cleanup_remote_account_login_session(session_id, terminate=False)
        return self.account_status_snapshot()

    def complete_remote_mcp_login(self, session_id: str, callback_url: str) -> dict:
        self.cleanup_expired_remote_login_sessions()
        session_id = str(session_id or "").strip()
        with self._remote_login_lock:
            session = self._remote_login_sessions.get(session_id)
            if not session:
                raise LookupError("Remote MCP login session not found")
            if str(session.get("mode") or "") != "mcp":
                raise ValueError("Remote login session is not an MCP login")
            session["status"] = "completing"

        try:
            local_callback_url = self.validated_remote_login_callback_url(session, callback_url)
            self.relay_remote_login_callback(local_callback_url)

            process = session["process"]
            returncode = process.wait(timeout=REMOTE_LOGIN_CALLBACK_TIMEOUT_SECONDS)
            if returncode != 0:
                output = str(session.get("output") or "").strip()
                raise RuntimeError(f"Codex MCP login failed: {truncate_text(output or f'exit {returncode}', 500)}")

            self.clear_connector_auth_warning(str(session.get("accountName") or ""))
        except subprocess.TimeoutExpired as exc:
            self.cleanup_remote_account_login_session(session_id, terminate=True)
            raise RuntimeError("Timed out waiting for Codex MCP login to finish") from exc
        except Exception:
            self.cleanup_remote_account_login_session(session_id, terminate=True)
            raise
        self.cleanup_remote_account_login_session(session_id, terminate=False)
        return self.account_status_snapshot()

    def validated_remote_login_callback_url(self, session: dict, callback_url: str) -> str:
        raw_url = str(callback_url or "").strip()
        parsed = urllib.parse.urlparse(raw_url)
        if parsed.scheme != "http" or parsed.hostname not in {"localhost", "127.0.0.1"}:
            raise ValueError("Remote login callback must be a localhost http URL")

        auth_url = str(session.get("authUrl") or "")
        auth_query = urllib.parse.parse_qs(urllib.parse.urlparse(auth_url).query)
        redirect_values = auth_query.get("redirect_uri") or []
        state_values = auth_query.get("state") or []
        if len(redirect_values) != 1 or not redirect_values[0]:
            raise ValueError("Remote login redirect URL is invalid")
        if len(state_values) != 1 or not state_values[0]:
            raise ValueError("Remote login authorization state is invalid")
        expected_redirect = redirect_values[0]
        expected_state = state_values[0]
        redirect = urllib.parse.urlparse(expected_redirect)
        if redirect.scheme != "http" or redirect.hostname not in {"localhost", "127.0.0.1"}:
            raise ValueError("Remote login redirect URL is invalid")
        if parsed.port != redirect.port:
            raise ValueError("Remote login callback port is invalid")
        if parsed.path != redirect.path:
            raise ValueError("Remote login callback path is invalid")

        callback_query = urllib.parse.parse_qs(parsed.query)
        callback_state_values = callback_query.get("state") or []
        if len(callback_state_values) != 1 or callback_state_values[0] != expected_state:
            raise ValueError("Remote login callback state does not match")
        if callback_query.get("error"):
            error = (callback_query.get("error_description") or callback_query.get("error") or ["Login failed"])[0]
            raise RuntimeError(f"Login failed: {truncate_text(error, 300)}")

        netloc = f"127.0.0.1:{parsed.port}"
        return urllib.parse.urlunparse((parsed.scheme, netloc, parsed.path, "", parsed.query, ""))

    def relay_remote_login_callback(self, callback_url: str):
        if self.login_callback_relayer is not None:
            self.login_callback_relayer(callback_url)
            return
        with urllib.request.urlopen(callback_url, timeout=15) as response:
            response.read()

    def cancel_remote_account_login(self, session_id: str) -> dict:
        session_id = str(session_id or "").strip()
        self.cleanup_remote_account_login_session(session_id, terminate=True)
        return {"ok": True}

    def ensure_remote_login_capacity(self):
        self.cleanup_expired_remote_login_sessions()
        with self._remote_login_lock:
            if len(self._remote_login_sessions) >= REMOTE_LOGIN_MAX_ACTIVE_SESSIONS:
                raise ValueError("Too many remote login sessions are active; cancel one and try again")

    def cleanup_expired_remote_login_sessions(self, now: int | None = None) -> int:
        current_time = int(time.time()) if now is None else int(now)
        with self._remote_login_lock:
            expired_ids = [
                session_id
                for session_id, session in self._remote_login_sessions.items()
                if int(session.get("createdAt") or 0) + REMOTE_LOGIN_SESSION_TIMEOUT_SECONDS <= current_time
            ]
        for session_id in expired_ids:
            self.cleanup_remote_account_login_session(session_id, terminate=True)
        return len(expired_ids)

    def cleanup_remote_account_login_session(self, session_id: str, terminate: bool):
        with self._remote_login_lock:
            session = self._remote_login_sessions.pop(session_id, None)
        if not session:
            return
        process = session.get("process")
        if terminate and process is not None and process.poll() is None:
            try:
                process.terminate()
            except Exception:
                pass
        temp_codex_home = session.get("tempCodexHome")
        if temp_codex_home:
            try:
                shutil.rmtree(temp_codex_home)
            except OSError:
                pass

    def start_local_web_session(self, raw_url: str) -> dict:
        parsed = self.validated_local_web_url(raw_url)
        session_id = secrets.token_urlsafe(24)
        now = int(time.time())
        expires_at = now + LOCAL_WEB_SESSION_TIMEOUT_SECONDS
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        target_origin = f"{parsed.scheme}://127.0.0.1:{port}"
        session = {
            "id": session_id,
            "scheme": parsed.scheme,
            "port": port,
            "createdAt": now,
            "expiresAt": expires_at,
            "targetOrigin": target_origin,
            "requestCount": 0,
        }
        with self._local_web_lock:
            self.cleanup_expired_local_web_sessions_locked(now)
            while len(self._local_web_sessions) >= LOCAL_WEB_MAX_ACTIVE_SESSIONS:
                oldest_session_id = min(
                    self._local_web_sessions,
                    key=lambda candidate: int(self._local_web_sessions[candidate].get("createdAt") or 0),
                )
                self._local_web_sessions.pop(oldest_session_id, None)
            self._local_web_sessions[session_id] = session
        path = self.local_web_gateway_path(session_id, parsed.path or "/", parsed.query)
        return {
            "sessionId": session_id,
            "path": path,
            "targetOrigin": target_origin,
            "expiresAt": expires_at,
        }

    def validated_local_web_url(self, raw_url: str):
        value = str(raw_url or "").strip()
        parsed = urllib.parse.urlparse(value)
        if parsed.scheme not in {"http", "https"}:
            raise ValueError("Only http and https localhost URLs can be opened")
        hostname = (parsed.hostname or "").casefold()
        if hostname not in {"localhost", "127.0.0.1", "::1"}:
            raise ValueError("Only localhost URLs can be opened through the Mac gateway")
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        if port <= 0 or port > 65535:
            raise ValueError("Localhost URL port is invalid")
        return parsed

    def cleanup_expired_local_web_sessions_locked(self, now: int):
        expired = [
            session_id for session_id, session in self._local_web_sessions.items()
            if int(session.get("expiresAt") or 0) <= now
        ]
        for session_id in expired:
            self._local_web_sessions.pop(session_id, None)

    def local_web_gateway_path(self, session_id: str, path: str, query: str = "") -> str:
        clean_path = "/" + str(path or "/").lstrip("/")
        quoted_path = urllib.parse.quote(clean_path, safe="/:@!$&'()*+,;=-._~")
        gateway_path = f"/api/local-web/{session_id}{quoted_path}"
        if query:
            gateway_path += f"?{query}"
        return gateway_path

    def proxy_local_web_session(self, session_id: str, path_parts: list[str], query: str) -> dict:
        now = int(time.time())
        with self._local_web_lock:
            self.cleanup_expired_local_web_sessions_locked(now)
            session = self._local_web_sessions.get(str(session_id or ""))
            if session:
                session["requestCount"] = int(session.get("requestCount") or 0) + 1
                if session["requestCount"] > LOCAL_WEB_MAX_REQUESTS_PER_SESSION:
                    self._local_web_sessions.pop(str(session_id or ""), None)
                    session = None
        if not session:
            raise LookupError("Local web session not found or expired")

        path = "/" + "/".join(urllib.parse.quote(urllib.parse.unquote(part), safe=":@!$&'()*+,;=-._~") for part in path_parts)
        if path == "/":
            path = "/"
        url = urllib.parse.urlunparse((
            str(session["scheme"]),
            f"127.0.0.1:{int(session['port'])}",
            path,
            "",
            str(query or ""),
            "",
        ))
        status, headers, body = self.local_web_fetcher(url)
        content_type = str(headers.get("Content-Type") or headers.get("content-type") or "application/octet-stream")
        if "text/html" in content_type.lower():
            body = self.rewrite_local_web_html(session, body)
        return {
            "status": int(status),
            "contentType": content_type,
            "body": body,
        }

    def rewrite_local_web_html(self, session: dict, body: bytes) -> bytes:
        try:
            text = body.decode("utf-8")
        except UnicodeDecodeError:
            return body
        session_id = str(session["id"])
        port = int(session["port"])
        replacements = [
            (f"http://localhost:{port}", f"/api/local-web/{session_id}"),
            (f"http://127.0.0.1:{port}", f"/api/local-web/{session_id}"),
            (f"https://localhost:{port}", f"/api/local-web/{session_id}"),
            (f"https://127.0.0.1:{port}", f"/api/local-web/{session_id}"),
        ]
        for source, target in replacements:
            text = text.replace(source, target)
        session_base = f"/api/local-web/{session_id}"
        text = re.sub(
            r'''(?P<attr>\b(?:src|href|action)=["'])(?P<path>/(?!/|api/local-web/)[^"']*)''',
            lambda match: f"{match.group('attr')}{session_base}{match.group('path')}",
            text,
            flags=re.IGNORECASE,
        )
        return text.encode("utf-8")

    def read_usage(self) -> dict:
        try:
            data = json.loads(self.usage_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return {}
        return data if isinstance(data, dict) else {}

    def usage_entry_for_account(self, account_name: str, usage: dict | None = None) -> dict:
        usage = usage if isinstance(usage, dict) else self.read_usage()
        entry = usage.get(account_name, {})
        if isinstance(entry, dict):
            return entry

        folded = str(account_name or "").casefold()
        for usage_name, candidate in usage.items():
            if str(usage_name).casefold() == folded and isinstance(candidate, dict):
                return candidate
        return {}

    def record_manual_switch(self, account_name: str):
        usage = self.read_usage()
        entry = usage.get(account_name, {})
        if not isinstance(entry, dict):
            entry = {}
        entry["manualSwitches"] = (optional_int(entry.get("manualSwitches")) or 0) + 1
        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        entry["lastSwitchAt"] = now
        entry["lastUsedAt"] = now
        usage[account_name] = entry
        write_json_object_atomic(self.usage_path, usage)

    def record_remote_login_refresh(self, account_name: str):
        usage = self.read_usage()
        usage_key = account_name
        for existing_key in usage:
            if str(existing_key).casefold() == account_name.casefold():
                usage_key = existing_key
                break

        entry = usage.get(usage_key, {})
        if not isinstance(entry, dict):
            entry = {}
        entry.pop("authStaleAt", None)
        entry.pop("authStaleReason", None)
        rate_limit_error = str(entry.get("rateLimitError") or "")
        if is_stale_auth_message(rate_limit_error):
            entry.pop("rateLimitError", None)
        entry["remoteLoginRefreshes"] = (optional_int(entry.get("remoteLoginRefreshes")) or 0) + 1
        entry["lastLoginRefreshAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        usage[usage_key] = entry
        write_json_object_atomic(self.usage_path, usage)

    def record_remote_login_add(self, account_name: str):
        usage = self.read_usage()
        entry = usage.get(account_name, {})
        if not isinstance(entry, dict):
            entry = {}
        entry.pop("authStaleAt", None)
        entry.pop("authStaleReason", None)
        entry.pop("rateLimitError", None)
        entry["remoteLoginAdds"] = (optional_int(entry.get("remoteLoginAdds")) or 0) + 1
        entry["lastLoginRefreshAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        usage[account_name] = entry
        write_json_object_atomic(self.usage_path, usage)

    def active_account_auth_stale_reason(self) -> str:
        return self.account_auth_stale_reason(self.active_account_name())

    def account_auth_stale_reason(self, account_name: str) -> str:
        usage = self.usage_entry_for_account(account_name)
        reason = str(usage.get("authStaleReason") or usage.get("rateLimitError") or "")
        if usage.get("authStaleAt") is not None:
            return reason or "Auth is stale; refresh this account login."
        if is_stale_auth_message(reason):
            return reason
        return ""

    def mark_active_account_auth_stale(self, reason: str):
        account = self.active_account_name()
        if not account or account == "unknown":
            return
        usage = self.read_usage()
        entry = usage.get(account, {})
        if not isinstance(entry, dict):
            entry = {}
        entry["authStaleAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        entry["authStaleReason"] = truncate_text(reason, 500)
        entry["rateLimitError"] = truncate_text(reason, 500)
        usage[account] = entry
        write_json_object_atomic(self.usage_path, usage)

    def record_connector_auth_warning_event(self, event: dict | None):
        if not isinstance(event, dict) or not event.get("connectorAuthWarning"):
            return
        account = self.active_account_name()
        if not account or account == "unknown":
            return
        connector_name = str(event.get("connectorName") or "").strip()
        if not connector_name:
            return

        usage = self.read_usage()
        usage_key = account
        for existing_key in usage:
            if str(existing_key).casefold() == account.casefold():
                usage_key = existing_key
                break
        entry = usage.get(usage_key, {})
        if not isinstance(entry, dict):
            entry = {}

        warnings = entry.get("connectorAuthWarnings")
        if not isinstance(warnings, list):
            warnings = []
        warnings = [
            item for item in warnings
            if isinstance(item, dict) and str(item.get("name") or "").casefold() != connector_name.casefold()
        ]
        warnings.insert(0, {
            "name": connector_name,
            "displayName": connector_display_name(connector_name),
            "lastSeenAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "message": truncate_text(str(event.get("body") or event.get("title") or ""), 500),
        })
        entry["connectorAuthWarnings"] = warnings[:20]
        usage[usage_key] = entry
        write_json_object_atomic(self.usage_path, usage)

    def clear_connector_auth_warning(self, connector_name: str):
        connector_name = str(connector_name or "").strip()
        if not connector_name:
            return
        account = self.active_account_name()
        if not account or account == "unknown":
            return
        usage = self.read_usage()
        usage_key = account
        for existing_key in usage:
            if str(existing_key).casefold() == account.casefold():
                usage_key = existing_key
                break
        entry = usage.get(usage_key, {})
        if not isinstance(entry, dict):
            return
        warnings = entry.get("connectorAuthWarnings")
        if not isinstance(warnings, list):
            return
        entry["connectorAuthWarnings"] = [
            item for item in warnings
            if isinstance(item, dict) and str(item.get("name") or "").casefold() != connector_name.casefold()
        ]
        usage[usage_key] = entry
        write_json_object_atomic(self.usage_path, usage)

    def account_status(self, name: str, usage_entry, active_account: str) -> dict:
        usage = usage_entry if isinstance(usage_entry, dict) else {}
        auth_stale_at = epoch_seconds(usage.get("authStaleAt"))
        auth_stale_reason = str(usage.get("authStaleReason") or "")
        return {
            "name": name,
            "isActive": name == active_account,
            "fiveHourRemainingPercent": optional_int(usage.get("dailyLimitRemainingPercent")),
            "fiveHourUsedPercent": optional_int(usage.get("dailyLimitUsedPercent")),
            "fiveHourWindowMins": optional_int(usage.get("dailyLimitWindowMins")),
            "fiveHourResetsAt": epoch_seconds(usage.get("dailyLimitResetsAt")),
            "weeklyRemainingPercent": optional_int(usage.get("weeklyLimitRemainingPercent")),
            "weeklyUsedPercent": optional_int(usage.get("weeklyLimitUsedPercent")),
            "weeklyWindowMins": optional_int(usage.get("weeklyLimitWindowMins")),
            "weeklyResetsAt": epoch_seconds(usage.get("weeklyLimitResetsAt")),
            "rateLimitResetCreditsRemaining": optional_int(usage.get("rateLimitResetCreditsRemaining")),
            "lastRefreshAt": epoch_seconds(usage.get("lastRateLimitRefreshAt")),
            "lastUsedAt": epoch_seconds(usage.get("lastUsedAt")),
            "lastLimitAt": epoch_seconds(usage.get("lastLimitAt")),
            "lastSwitchAt": epoch_seconds(usage.get("lastSwitchAt")),
            "turnEvents": optional_int(usage.get("turnEvents")) or 0,
            "limitHits": optional_int(usage.get("limitHits")) or 0,
            "manualSwitches": optional_int(usage.get("manualSwitches")) or 0,
            "automaticSwitches": optional_int(usage.get("automaticSwitches")) or 0,
            "rateLimitError": str(usage.get("rateLimitError") or ""),
            "authStale": auth_stale_at is not None or bool(auth_stale_reason),
            "authStaleAt": auth_stale_at,
            "authStaleReason": auth_stale_reason,
        }

    def start_turn(
        self,
        thread_id: str,
        prompt: str,
        raw_attachments: list | None = None,
        reasoning_effort: str | None = None,
    ) -> dict:
        prompt = prompt.strip()
        attachments = raw_attachments if isinstance(raw_attachments, list) else []
        reasoning_effort = codex_app_server_reasoning_effort(reasoning_effort)
        if not prompt and not attachments:
            raise ValueError("Prompt is empty")

        thread = self.get_thread(thread_id)
        if not thread:
            raise LookupError("Thread not found")

        with RUN_LOCK:
            for job in JOBS.values():
                if job.get("status") == "running" and job.get("threadId") == thread_id:
                    raise RuntimeError("This thread already has a running Codex turn")
            self.ensure_app_server_ready_for_new_turn()

            job_id = secrets.token_urlsafe(12)
            job = {
                "id": job_id,
                "threadId": thread_id,
                "threadTitle": str(thread.get("title") or "").strip(),
                "status": "running",
                "createdAt": int(time.time()),
                "updatedAt": int(time.time()),
                "output": "",
                "lastMessage": "",
                "error": None,
                "reasoningEffort": reasoning_effort,
                "promptText": self.outgoing_message_text(prompt, attachments),
                "attachments": [],
                "events": [
                    make_stream_event(
                        "context.workspace",
                        "context",
                        "completed",
                        "Workspace",
                        str(thread["cwd"]),
                    )
                ],
            }
            saved_attachments = self.save_attachments(thread_id, job_id, attachments)
            prompt = self.prompt_with_attachments(prompt, saved_attachments)
            job["attachments"] = [
                {
                    "filename": attachment["filename"],
                    "mimeType": attachment["mimeType"],
                    "size": attachment["size"],
                    "path": str(attachment["path"]),
                    "isImage": attachment["isImage"],
                }
                for attachment in saved_attachments
            ]
            if saved_attachments:
                append_job_event(
                    job,
                    make_stream_event(
                        "context.attachments",
                        "context",
                        "completed",
                        "Files attached",
                        "\n".join(attachment["filename"] for attachment in saved_attachments),
                    ),
                )
            with JOBS_LOCK:
                JOBS[job_id] = job

            args = (job_id, thread, prompt, saved_attachments, True, reasoning_effort) if reasoning_effort else (job_id, thread, prompt, saved_attachments)
            worker = threading.Thread(target=self.run_turn, args=args, daemon=True)
            worker.start()
            return job

    def start_new_thread(
        self,
        cwd: str,
        prompt: str,
        raw_attachments: list | None = None,
        reasoning_effort: str | None = None,
        create_workspace: bool = False,
    ) -> dict:
        prompt = prompt.strip()
        attachments = raw_attachments if isinstance(raw_attachments, list) else []
        reasoning_effort = normalized_reasoning_effort(reasoning_effort)
        if not prompt and not attachments:
            raise ValueError("Prompt is empty")

        workspace = self.prepare_workspace(cwd, create_workspace)

        with RUN_LOCK:
            self.ensure_app_server_ready_for_new_turn()
            job_id = secrets.token_urlsafe(12)
            thread = {
                "id": "",
                "title": "New Thread",
                "cwd": workspace,
                "rolloutPath": "",
                "updatedAt": int(time.time()),
                "createdAt": int(time.time()),
                "source": None,
                "threadSource": None,
            }
            job = {
                "id": job_id,
                "threadId": "",
                "threadTitle": "New Thread",
                "cwd": workspace,
                "status": "running",
                "createdAt": int(time.time()),
                "updatedAt": int(time.time()),
                "output": "",
                "lastMessage": "",
                "error": None,
                "reasoningEffort": reasoning_effort,
                "promptText": self.outgoing_message_text(prompt, attachments),
                "attachments": [],
                "events": [
                    make_stream_event(
                        "context.workspace",
                        "context",
                        "completed",
                        "Workspace",
                        workspace,
                    )
                ],
            }
            saved_attachments = self.save_attachments("new-thread", job_id, attachments)
            prompt = self.prompt_with_attachments(prompt, saved_attachments)
            job["attachments"] = [
                {
                    "filename": attachment["filename"],
                    "mimeType": attachment["mimeType"],
                    "size": attachment["size"],
                    "path": str(attachment["path"]),
                    "isImage": attachment["isImage"],
                }
                for attachment in saved_attachments
            ]
            if saved_attachments:
                append_job_event(
                    job,
                    make_stream_event(
                        "context.attachments",
                        "context",
                        "completed",
                        "Files attached",
                        "\n".join(attachment["filename"] for attachment in saved_attachments),
                    ),
                )
            with JOBS_LOCK:
                JOBS[job_id] = job

            args = (job_id, thread, prompt, saved_attachments, False, reasoning_effort) if reasoning_effort else (job_id, thread, prompt, saved_attachments, False)
            worker = threading.Thread(target=self.run_turn, args=args, daemon=True)
            worker.start()
            return job

    def save_attachments(self, thread_id: str, job_id: str, raw_attachments: list) -> list[dict]:
        if len(raw_attachments) > MAX_ATTACHMENTS:
            raise ValueError(f"Too many attachments; maximum is {MAX_ATTACHMENTS}")

        cleanup_expired_uploads()
        if not raw_attachments:
            return []
        saved = []
        total_size = 0
        ensure_private_upload_directory(DEFAULT_UPLOADS_DIR, parents=True)
        thread_upload_dir = DEFAULT_UPLOADS_DIR / safe_filename(thread_id, "thread")
        ensure_private_upload_directory(thread_upload_dir)
        upload_dir = thread_upload_dir / f"{int(time.time())}-{safe_filename(job_id, 'job')}"
        ensure_private_upload_directory(upload_dir)
        created_paths = []
        try:
            for index, attachment in enumerate(raw_attachments, 1):
                if not isinstance(attachment, dict):
                    raise ValueError("Attachment is invalid")

                encoded = attachment.get("dataBase64")
                if not isinstance(encoded, str) or not encoded:
                    raise ValueError("Attachment data is missing")

                try:
                    data = base64.b64decode(encoded, validate=True)
                except Exception as exc:
                    raise ValueError("Attachment is not valid base64") from exc

                size = len(data)
                if size > MAX_ATTACHMENT_BYTES:
                    raise ValueError("Attachment is too large")
                total_size += size
                if total_size > MAX_TOTAL_ATTACHMENT_BYTES:
                    raise ValueError("Total attachment size is too large")

                filename = safe_filename(str(attachment.get("filename", "")), f"attachment-{index}")
                path = upload_dir / filename
                if path.exists():
                    stem = path.stem or "attachment"
                    suffix = path.suffix
                    path = upload_dir / f"{stem}-{index}{suffix}"
                descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                created_paths.append(path)
                with os.fdopen(descriptor, "wb") as handle:
                    handle.write(data)

                mime_type = str(attachment.get("mimeType") or "application/octet-stream")
                saved.append({
                    "filename": path.name,
                    "mimeType": mime_type,
                    "size": size,
                    "path": path,
                    "isImage": is_image_attachment(path, mime_type),
                })
        except Exception:
            for path in created_paths:
                try:
                    path.unlink()
                except OSError:
                    pass
            try:
                upload_dir.rmdir()
                thread_upload_dir.rmdir()
            except OSError:
                pass
            raise

        return saved

    def outgoing_message_text(self, prompt: str, raw_attachments: list) -> str:
        names = []
        for attachment in raw_attachments:
            if isinstance(attachment, dict):
                filename = str(attachment.get("filename") or "").strip()
                if filename:
                    names.append(filename)
        if not names:
            return prompt
        attachment_names = ", ".join(names)
        if prompt:
            return f"{prompt}\n\nAttached: {attachment_names}"
        return f"Attached: {attachment_names}"

    def prompt_with_attachments(self, prompt: str, attachments: list[dict]) -> str:
        if not attachments:
            return prompt

        lines = [
            "Files uploaded from the iPhone app have been saved on the Mac at these paths:",
        ]
        for attachment in attachments:
            marker = "image" if attachment["isImage"] else "file"
            lines.append(f"- {attachment['filename']} ({marker}, {attachment['mimeType']}, {attachment['size']} bytes): {attachment['path']}")
        attachment_note = "\n".join(lines)
        if prompt:
            return f"{prompt}\n\n{attachment_note}"
        return f"Please inspect the attached file(s).\n\n{attachment_note}"

    def run_turn(
        self,
        job_id: str,
        thread: dict,
        prompt: str,
        attachments: list[dict],
        resume_existing: bool = True,
        reasoning_effort: str | None = None,
    ):
        if self.run_turn_app_server(job_id, thread, prompt, resume_existing, reasoning_effort):
            return

        if reasoning_effort:
            self.run_turn_exec(job_id, thread, prompt, attachments, resume_existing, reasoning_effort)
        else:
            self.run_turn_exec(job_id, thread, prompt, attachments, resume_existing)

    def run_turn_app_server(
        self,
        job_id: str,
        thread: dict,
        prompt: str,
        resume_existing: bool = True,
        reasoning_effort: str | None = None,
    ) -> bool:
        try:
            client = self.app_server_client()
            client.start()

            thread_id = str(thread.get("id") or "").strip()
            if not resume_existing:
                response = client.thread_start(thread.get("cwd"), reasoning_effort) if reasoning_effort else client.thread_start(thread.get("cwd"))
                thread_id = str(
                    (response.get("thread") or {}).get("id")
                    or response.get("threadId")
                    or response.get("id")
                    or ""
                ).strip()
                if not thread_id:
                    raise RuntimeError("Codex app-server did not create a thread")
                with JOBS_LOCK:
                    job = JOBS[job_id]
                    job["threadId"] = thread_id
                    job["updatedAt"] = int(time.time())
                    append_job_event(
                        job,
                        make_stream_event("thread.started", "context", "completed", "Thread resumed", thread_id, raw_type="thread.started"),
                    )
            elif thread_id:
                client.thread_resume(thread_id)

            response = client.turn_start(thread_id, prompt, reasoning_effort) if reasoning_effort else client.turn_start(thread_id, prompt)
            turn_id = str((response.get("turn") or {}).get("id") or response.get("turnId") or response.get("id") or "").strip()
            with JOBS_LOCK:
                job = JOBS[job_id]
                job["threadId"] = thread_id
                if turn_id:
                    job["turnId"] = turn_id
                job["updatedAt"] = int(time.time())
                append_job_event(
                    job,
                    make_stream_event("turn.started", "context", "completed", "Context loaded", "Codex has started the turn.", raw_type="turn.started"),
                )

            while True:
                time.sleep(1)
                with JOBS_LOCK:
                    job = JOBS.get(job_id)
                    if not job or job.get("status") != "running":
                        return True
        except Exception as exc:
            stale_auth_error = str(exc) if is_stale_auth_message(str(exc)) else ""
            if resume_existing and is_app_server_thread_not_found_error(exc):
                try:
                    client.close()
                except Exception:
                    pass
                return False
            push_job = None
            with JOBS_LOCK:
                job = JOBS.get(job_id)
                if job is not None:
                    job["updatedAt"] = int(time.time())
                    job["status"] = "failed"
                    job["error"] = str(exc)
                    append_job_event(job, make_stream_event("job.failed", "error", "failed", "Codex failed", str(exc), raw_type="job"))
                    push_job = self.prepare_turn_completion_push_locked(job)
            if push_job:
                self.send_turn_completion_push(push_job)
            if stale_auth_error:
                self.mark_active_account_auth_stale(stale_auth_error)
                self.close_app_server_client()
            return True

    def run_turn_exec(
        self,
        job_id: str,
        thread: dict,
        prompt: str,
        attachments: list[dict],
        resume_existing: bool = True,
        reasoning_effort: str | None = None,
    ):
        env = codex_child_env(self.codex_home)
        codex = str(self.codex_path if self.codex_path.exists() else shutil.which("codex") or DEFAULT_CODEX)
        output_descriptor, output_name = tempfile.mkstemp(prefix=f"codex-phone-{job_id}-", suffix=".txt")
        os.close(output_descriptor)
        output_file = Path(output_name)
        os.chmod(output_file, 0o600)
        args = [
            codex,
            "exec",
            "-C",
            thread["cwd"],
        ]
        if reasoning_effort:
            args.extend(["-c", f'model_reasoning_effort="{reasoning_effort}"'])
        if resume_existing:
            args.append("resume")
        args.extend([
            "--skip-git-repo-check",
            "--json",
            "-o",
            str(output_file),
        ])
        if self.allow_dangerous:
            args.append("--dangerously-bypass-approvals-and-sandbox")
        for attachment in attachments:
            if attachment["isImage"]:
                args.extend(["--image", str(attachment["path"])])
        if resume_existing:
            args.extend([thread["id"], "-"])
        else:
            args.append("-")

        try:
            process = subprocess.Popen(
                args,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                env=env,
            )
            with JOBS_LOCK:
                JOB_PROCESSES[job_id] = process
            assert process.stdin is not None
            process.stdin.write(prompt)
            process.stdin.close()

            lines = []
            sequence = 0
            assert process.stdout is not None
            for line in process.stdout:
                stripped_line = line.rstrip()
                lines.append(stripped_line)
                sequence += 1
                event = format_stream_event(stripped_line, sequence)
                with JOBS_LOCK:
                    job = JOBS[job_id]
                    job["updatedAt"] = int(time.time())
                    job["output"] = "\n".join(lines[-200:])
                    update_job_thread_id(job, event)
                    append_job_event(job, event)
                    self.record_connector_auth_warning_event(event)

            status = process.wait()
            last_message = output_file.read_text(encoding="utf-8", errors="replace").strip() if output_file.exists() else ""
            push_job = None
            with JOBS_LOCK:
                job = JOBS[job_id]
                JOB_PROCESSES.pop(job_id, None)
                if job.get("status") != "running":
                    return
                job["updatedAt"] = int(time.time())
                job["lastMessage"] = last_message
                job["output"] = "\n".join(lines[-200:])
                if status == 0:
                    job["status"] = "completed"
                    append_job_event(
                        job,
                        make_stream_event("job.completed", "status", "completed", "Codex finished", raw_type="job"),
                    )
                else:
                    job["status"] = "failed"
                    detail = job["output"].strip()
                    job["error"] = f"codex exited with status {status}" + (f"\n\n{detail}" if detail else "")
                    append_job_event(
                        job,
                        make_stream_event("job.failed", "error", "failed", "Codex failed", f"Exit status {status}", raw_type="job"),
                    )
                push_job = self.prepare_turn_completion_push_locked(job)
            if push_job:
                self.send_turn_completion_push(push_job)
        except Exception as exc:
            push_job = None
            with JOBS_LOCK:
                JOB_PROCESSES.pop(job_id, None)
                job = JOBS[job_id]
                if job.get("status") != "running":
                    return
                job["updatedAt"] = int(time.time())
                job["status"] = "failed"
                job["error"] = str(exc)
                append_job_event(job, make_stream_event("job.failed", "error", "failed", "Codex failed", str(exc), raw_type="job"))
                push_job = self.prepare_turn_completion_push_locked(job)
            if push_job:
                self.send_turn_completion_push(push_job)
        finally:
            try:
                output_file.unlink()
            except FileNotFoundError:
                pass


class Handler(BaseHTTPRequestHandler):
    server_version = "CodePilotGateway"

    def version_string(self) -> str:
        return self.server_version

    def state(self) -> GatewayState:
        return self.server.state

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Allow", "GET, POST, DELETE, OPTIONS")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def end_headers(self):
        super().end_headers()

    def authenticate(self) -> bool:
        if self.is_authenticated():
            return True
        json_error(
            self,
            401,
            "unauthorized",
            "Unauthorized",
            "Update the CodePilot Gateway token in the iPhone app, then try again.",
        )
        return False

    def is_authenticated(self) -> bool:
        expected = self.state().token
        header = self.headers.get("authorization", "")
        return secrets.compare_digest(header, f"Bearer {expected}")

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        parts = [part for part in path.split("/") if part]

        if len(parts) >= 3 and parts[0] == "api" and parts[1] == "local-web":
            try:
                local_web_response(
                    self,
                    self.state().proxy_local_web_session(parts[2], parts[3:], parsed.query),
                )
            except LookupError as exc:
                json_error(
                    self,
                    404,
                    "local_web_unavailable",
                    "Local web session not found or expired",
                    "Open the localhost link again from CodePilot; local web sessions expire after a short time.",
                )
            except Exception:
                json_error(
                    self,
                    502,
                    "local_web_unavailable",
                    "The selected local web server is unavailable",
                    "Make sure the local web server is running on the Mac, then reopen the link.",
                )
            return

        if path == "/health" or path == "/api/health":
            payload = (
                self.state().diagnostic_health()
                if self.is_authenticated()
                else self.state().public_health()
            )
            json_response(self, 200, payload)
            return

        if not self.authenticate():
            return

        try:
            if path == "/api/threads":
                json_response(self, 200, {
                    "activeAccount": self.state().active_account_name(),
                    "threads": self.state().list_threads(),
                })
                return

            if path == "/api/accounts":
                json_response(self, 200, self.state().account_status_snapshot())
                return

            if len(parts) >= 2 and parts[0] == "api" and parts[1] == "remote":
                query = urllib.parse.parse_qs(parsed.query)
                status, payload = self.state().remote_desktop_gateway.handle("GET", parts[2:], query, None)
                if isinstance(payload, dict) and "_raw" in payload:
                    raw = payload.get("_raw") or b""
                    self.send_response(status)
                    self.send_header("Content-Type", str(payload.get("_content_type") or "application/octet-stream"))
                    self.send_header("Cache-Control", str(payload.get("_cache_control") or "no-store"))
                    self.send_header("Content-Length", str(len(raw)))
                    self.end_headers()
                    self.wfile.write(raw)
                    return
                json_response(self, status, payload)
                return

            if len(parts) == 3 and parts[0] == "api" and parts[1] == "files":
                query = urllib.parse.parse_qs(parsed.query)
                requested_path = (query.get("path") or [""])[0]
                file_path = resolve_requested_file_path(requested_path)
                if parts[2] == "metadata":
                    json_response(self, 200, {"file": file_metadata(file_path)})
                    return
                if parts[2] == "download":
                    file_response(self, file_path)
                    return

            if path == "/api/jobs/active":
                query = urllib.parse.parse_qs(parsed.query)
                thread_id = (query.get("threadId") or [""])[0]
                if thread_id:
                    job = self.state().active_job_for_thread(thread_id)
                    payload = {
                        "activeAccount": self.state().active_account_name(),
                        "appServerAuth": self.state().app_server_auth_status(),
                        "job": job,
                    }
                    json_response(self, 200, payload)
                else:
                    json_response(self, 200, {
                        "activeAccount": self.state().active_account_name(),
                        "appServerAuth": self.state().app_server_auth_status(),
                        "jobs": self.state().active_jobs(),
                    })
                return

            if len(parts) == 3 and parts[0] == "api" and parts[1] == "threads":
                thread = self.state().get_thread(parts[2])
                if not thread:
                    json_error(
                        self,
                        404,
                        "thread_not_found",
                        "Thread not found",
                        "Return to the thread list and refresh. The thread may have been moved, deleted, or not synced yet.",
                    )
                    return
                if "messages" not in thread:
                    rollout_messages = parse_messages(Path(thread["rolloutPath"]))
                    cached_messages = read_cached_thread_messages(thread["id"])
                    thread["messages"] = merge_thread_messages(rollout_messages, cached_messages)
                else:
                    cached_messages = read_cached_thread_messages(thread["id"])
                    thread["messages"] = merge_thread_messages(thread.get("messages") or [], cached_messages, limit=120)
                thread["messages"] = scope_thread_message_ids(thread["id"], thread["messages"])
                json_response(self, 200, {
                    "activeAccount": self.state().active_account_name(),
                    "thread": thread,
                })
                return

            if len(parts) == 3 and parts[0] == "api" and parts[1] == "jobs":
                query = urllib.parse.parse_qs(parsed.query)
                after_event_seq = optional_int((query.get("afterEventSeq") or [""])[0])
                with JOBS_LOCK:
                    job = JOBS.get(parts[2])
                if not job:
                    json_error(
                        self,
                        404,
                        "job_not_found",
                        "Job not found",
                        "Reload the thread. The live stream may have ended and saved messages can still be loaded.",
                    )
                    return
                json_response(self, 200, self.state().job_response(job, after_event_seq))
                return

            if len(parts) == 5 and parts[0] == "api" and parts[1] == "accounts" and parts[2] == "auth" and parts[3] == "login":
                json_response(self, 200, self.state().remote_account_login_status(parts[4]))
                return

            if len(parts) == 5 and parts[0] == "api" and parts[1] == "mcp" and parts[2] == "login" and parts[3] == "status":
                json_response(self, 200, self.state().remote_account_login_status(parts[4]))
                return

            json_error(self, 404, "gateway_unavailable", "Not found", "Update the app or gateway if this request should be supported.")
        except PermissionError as exc:
            json_error(
                self,
                403,
                "file_access_denied",
                str(exc),
                "Only preview files from a configured CodePilot download root.",
            )
        except LookupError as exc:
            json_error(self, 404, "gateway_unavailable", str(exc), "Refresh the app and try again.")
        except Exception as exc:
            json_error(self, 500, "gateway_unavailable", str(exc), "Restart CodePilot Gateway if the problem continues.")

    def do_POST(self):
        if not self.authenticate():
            return

        parsed = urllib.parse.urlparse(self.path)
        parts = [part for part in parsed.path.split("/") if part]

        try:
            if len(parts) == 2 and parts[0] == "api" and parts[1] == "threads":
                body = decode_body(self, max_length=MAX_ATTACHMENT_REQUEST_BYTES)
                attachments = body.get("attachments")
                job = self.state().start_new_thread(
                    str(body.get("cwd", "")),
                    str(body.get("prompt", "")),
                    attachments,
                    str(body.get("reasoningEffort") or ""),
                    bool(body.get("createWorkspace")),
                )
                json_response(self, 202, {"job": job})
                return

            if len(parts) == 3 and parts[0] == "api" and parts[1] == "accounts" and parts[2] == "switch":
                body = decode_body(self)
                snapshot = self.state().switch_account(str(body.get("name", "")))
                json_response(self, 200, snapshot)
                return

            if len(parts) == 3 and parts[0] == "api" and parts[1] == "accounts" and parts[2] == "rate-limit-reset":
                body = decode_body(self)
                snapshot = self.state().consume_rate_limit_reset_credit(str(body.get("name", "")))
                json_response(self, 200, snapshot)
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "accounts" and parts[2] == "auth" and parts[3] == "refresh":
                body = decode_body(self)
                snapshot = self.state().refresh_account_auth_with_access_token(
                    str(body.get("name", "")),
                    str(body.get("accessToken", "")),
                )
                json_response(self, 200, snapshot)
                return

            if len(parts) == 5 and parts[0] == "api" and parts[1] == "accounts" and parts[2] == "auth" and parts[3] == "login":
                body = decode_body(self)
                if parts[4] == "start":
                    session = self.state().start_remote_account_login(str(body.get("name", "")))
                    json_response(self, 200, session)
                    return
                if parts[4] == "callback":
                    snapshot = self.state().complete_remote_account_login(
                        str(body.get("sessionId", "")),
                        str(body.get("callbackURL", "")),
                    )
                    json_response(self, 200, snapshot)
                    return
                if parts[4] == "cancel":
                    result = self.state().cancel_remote_account_login(str(body.get("sessionId", "")))
                    json_response(self, 200, result)
                    return

            if len(parts) == 6 and parts[0] == "api" and parts[1] == "accounts" and parts[2] == "auth" and parts[3] == "login" and parts[4] == "add" and parts[5] == "start":
                body = decode_body(self)
                session = self.state().start_remote_new_account_login(str(body.get("name", "")))
                json_response(self, 200, session)
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "mcp" and parts[2] == "login":
                body = decode_body(self)
                if parts[3] == "start":
                    session = self.state().start_remote_mcp_login(str(body.get("name", "")))
                    json_response(self, 200, session)
                    return
                if parts[3] == "callback":
                    snapshot = self.state().complete_remote_mcp_login(
                        str(body.get("sessionId", "")),
                        str(body.get("callbackURL", "")),
                    )
                    json_response(self, 200, snapshot)
                    return
                if parts[3] == "cancel":
                    result = self.state().cancel_remote_account_login(str(body.get("sessionId", "")))
                    json_response(self, 200, result)
                    return

            if len(parts) == 3 and parts[0] == "api" and parts[1] == "notifications" and parts[2] == "device":
                body = decode_body(self)
                json_response(self, 200, self.state().register_notification_device(body))
                return

            if len(parts) == 2 and parts[0] == "api" and parts[1] == "live-activities":
                body = decode_body(self)
                json_response(self, 200, self.state().register_live_activity(body))
                return

            if len(parts) == 3 and parts[0] == "api" and parts[1] == "local-web" and parts[2] == "sessions":
                body = decode_body(self)
                try:
                    session = self.state().start_local_web_session(str(body.get("url", "")))
                except ValueError as exc:
                    json_error(
                        self,
                        400,
                        "local_web_invalid_target",
                        str(exc),
                        "Open a localhost, 127.0.0.1, or ::1 URL from the iPhone app.",
                    )
                    return
                json_response(self, 200, session)
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "threads" and parts[3] == "turns":
                body = decode_body(self, max_length=MAX_ATTACHMENT_REQUEST_BYTES)
                attachments = body.get("attachments")
                job = self.state().start_turn(
                    parts[2],
                    str(body.get("prompt", "")),
                    attachments,
                    str(body.get("reasoningEffort") or ""),
                )
                json_response(self, 202, {"job": job})
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "threads" and parts[3] == "steer":
                body = decode_body(self)
                job = self.state().steer_turn(parts[2], str(body.get("jobId", "")), str(body.get("text", "")))
                json_response(self, 200, {"job": job})
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "threads" and parts[3] == "stop":
                body = decode_body(self)
                job = self.state().stop_turn(parts[2], str(body.get("jobId", "")))
                json_response(self, 200, {"job": job})
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "threads" and parts[3] == "rename":
                body = decode_body(self)
                self.state().rename_thread(parts[2], str(body.get("name", "")))
                json_response(self, 200, {"ok": True})
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "threads" and parts[3] == "archive":
                self.state().archive_thread(parts[2])
                json_response(self, 200, {"ok": True})
                return

            if len(parts) == 4 and parts[0] == "api" and parts[1] == "threads" and parts[3] == "pin":
                body = decode_body(self)
                self.state().set_thread_pinned(parts[2], body.get("pinned"))
                json_response(self, 200, {"ok": True})
                return

            if len(parts) >= 2 and parts[0] == "api" and parts[1] == "remote":
                body = decode_body(self, max_length=1_048_576)
                status, payload = self.state().remote_desktop_gateway.handle("POST", parts[2:], {}, body)
                json_response(self, status, payload)
                return

            json_error(self, 404, "gateway_unavailable", "Not found", "Update the app or gateway if this request should be supported.")
        except LookupError as exc:
            json_error(self, 404, "gateway_unavailable", str(exc), "Refresh the app and try again.")
        except RequestBodyTooLarge as exc:
            json_error(self, 413, "gateway_unavailable", str(exc), "Send a smaller request or fewer attachments.")
        except ValueError as exc:
            json_error(self, 400, "gateway_unavailable", str(exc), "Check the request and try again.")
        except RuntimeError as exc:
            message = str(exc)
            code = "auth_stale" if is_stale_auth_message(message) else "active_turn_running"
            recovery = (
                "Refresh login for the active account, then try again."
                if code == "auth_stale"
                else "Wait for the active turn to finish, then try again."
            )
            json_error(self, 409, code, message, recovery)
        except Exception as exc:
            json_error(self, 500, "gateway_unavailable", str(exc), "Restart CodePilot Gateway if the problem continues.")

    def do_DELETE(self):
        if not self.authenticate():
            return
        parsed = urllib.parse.urlparse(self.path)
        parts = [part for part in parsed.path.split("/") if part]
        try:
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "live-activities":
                json_response(self, 200, self.state().unregister_live_activity(urllib.parse.unquote(parts[2])))
                return
            json_error(self, 404, "gateway_unavailable", "Not found", "Update the app or gateway if this request should be supported.")
        except Exception as exc:
            json_error(self, 500, "gateway_unavailable", str(exc), "Restart CodePilot Gateway if the problem continues.")

    def log_request(self, code="-", size="-"):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        if path.startswith("/api/local-web/"):
            path = "/api/local-web/[redacted]"
        self.log_message(
            '"%s %s %s" %s %s',
            self.command,
            path,
            self.request_version,
            str(code),
            str(size),
        )

    def log_message(self, format, *args):
        message = format % args
        safe_message = re.sub(
            r"[\x00-\x1f\x7f-\x9f]",
            lambda match: f"\\x{ord(match.group(0)):02x}",
            message,
        )
        print(f"{self.client_address[0]} - {safe_message}", flush=True)


class GatewayServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True
    block_on_close = False
    request_queue_size = GATEWAY_MAX_CONCURRENT_REQUESTS

    def __init__(
        self,
        address,
        state: GatewayState,
        *,
        max_concurrent_requests: int = GATEWAY_MAX_CONCURRENT_REQUESTS,
        request_timeout_seconds: float = GATEWAY_REQUEST_TIMEOUT_SECONDS,
    ):
        self._request_slots = threading.BoundedSemaphore(max(1, int(max_concurrent_requests)))
        self.request_timeout_seconds = max(1.0, float(request_timeout_seconds))
        super().__init__(address, Handler)
        self.state = state

    def get_request(self):
        request, client_address = super().get_request()
        request.settimeout(self.request_timeout_seconds)
        return request, client_address

    def process_request(self, request, client_address):
        if not self._request_slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self._request_slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._request_slots.release()


def main():
    parser = argparse.ArgumentParser(description="Small HTTP gateway for the Codex iPhone client.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=18790, type=int)
    parser.add_argument("--codex-home", default=str(DEFAULT_CODEX_HOME))
    parser.add_argument("--codex-path", default=str(DEFAULT_CODEX))
    parser.add_argument("--token-file", default=str(DEFAULT_TOKEN_FILE))
    parser.add_argument("--allow-dangerous", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument(
        "--allow-non-loopback",
        action="store_true",
        help="Allow direct binding outside loopback. Use only behind a trusted TLS/authentication proxy.",
    )
    args = parser.parse_args()

    if not is_loopback_host(args.host) and not args.allow_non_loopback:
        parser.error("Refusing a non-loopback bind without --allow-non-loopback")

    token = read_or_create_token(Path(args.token_file))
    cleanup_expired_uploads()
    state = GatewayState(
        codex_home=Path(args.codex_home),
        token=token,
        codex_path=Path(args.codex_path),
        allow_dangerous=args.allow_dangerous,
    )
    server = GatewayServer((args.host, args.port), state)
    print(f"Codex phone gateway listening on http://{args.host}:{args.port}", flush=True)
    print(f"Token file: {args.token_file}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
