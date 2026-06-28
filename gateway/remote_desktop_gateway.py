from __future__ import annotations

import base64
import binascii
import json
import os
import socket
import threading
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any


DEFAULT_REMOTE_DESKTOP_SOCKET_PATH = Path.home() / ".codepilot" / "remote-desktop" / "host.sock"
DEFAULT_TIMEOUT_SECONDS = 5.0
DEFAULT_MAX_REQUEST_BYTES = 1_048_576
DEFAULT_MAX_RESPONSE_BYTES = 1_048_576
ALLOWED_RESPONSE_KEYS = {"id", "status", "payload", "errorCode"}
ERROR_STATUS = {
    "host_unavailable": 503,
    "timeout": 503,
    "pairing_expired": 410,
    "untrusted_device": 403,
    "invalid_signature": 403,
    "accessibility_required": 403,
    "screen_recording_required": 403,
    "controller_busy": 409,
    "session_expired": 410,
    "sequence_replay": 409,
    "request_too_large": 413,
    "malformed_response": 502,
    "turn_unavailable": 503,
}
IDENTIFIER_MAX_LENGTH = 128
SIGNAL_QUEUE_LIMIT = 256
STUN_ONLY_ICE_SERVERS = [{"urls": ["stun:stun.l.google.com:19302"]}]
MAX_CLIPBOARD_TEXT_BYTES = 1_048_576
REMOTE_INPUT_KEYS = {
    "sessionId", "sequence", "kind", "x", "y", "button", "keyCode",
    "text", "deltaX", "deltaY",
}
REMOTE_INPUT_KINDS = {"pointer", "buttonDown", "buttonUp", "scroll", "keyDown", "keyUp", "text"}


class RemoteDesktopHostError(RuntimeError):
    def __init__(self, code: str, message: str | None = None):
        self.code = code
        super().__init__(message or _default_message_for_code(code))


class NativeHostClient:
    def __init__(
        self,
        socket_path: str | os.PathLike[str] = DEFAULT_REMOTE_DESKTOP_SOCKET_PATH,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        max_request_bytes: int = DEFAULT_MAX_REQUEST_BYTES,
        max_response_bytes: int = DEFAULT_MAX_RESPONSE_BYTES,
    ):
        self._socket_path = Path(socket_path)
        self._timeout_seconds = timeout_seconds
        self._max_request_bytes = max_request_bytes
        self._max_response_bytes = max_response_bytes

    def call(self, method: str, payload: Any | None = None) -> dict[str, Any]:
        method = str(method or "").strip()
        if not method:
            raise RemoteDesktopHostError("invalid_request")

        request_id = str(uuid.uuid4())
        request = {
            "id": request_id,
            "method": method,
            "payload": _encode_payload(payload),
        }
        request_bytes = json.dumps(request, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"
        if len(request_bytes) > self._max_request_bytes:
            raise RemoteDesktopHostError("request_too_large")

        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
                conn.settimeout(self._timeout_seconds)
                conn.connect(str(self._socket_path))
                conn.sendall(request_bytes)
                response = self._read_response(conn)
        except socket.timeout as exc:
            raise RemoteDesktopHostError("timeout") from exc
        except OSError as exc:
            raise RemoteDesktopHostError("host_unavailable") from exc

        parsed = _decode_response(response, request_id)
        return parsed

    def _read_response(self, conn: socket.socket) -> bytes:
        buffer = bytearray()
        while True:
            try:
                chunk = conn.recv(min(4096, max(1, self._max_response_bytes - len(buffer))))
            except socket.timeout:
                raise
            if not chunk:
                break
            buffer.extend(chunk)
            if len(buffer) > self._max_response_bytes:
                raise RemoteDesktopHostError("response_too_large")
            if b"\n" in chunk:
                break

        if len(buffer) > self._max_response_bytes:
            raise RemoteDesktopHostError("response_too_large")

        line, _, _ = bytes(buffer).partition(b"\n")
        if not line:
            raise RemoteDesktopHostError("malformed_response")
        return line


def _encode_payload(payload: Any | None) -> str | None:
    if payload is None:
        return ""
    if isinstance(payload, bytes):
        raw = payload
    elif isinstance(payload, str):
        raw = payload.encode("utf-8")
    else:
        raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return base64.b64encode(raw).decode("ascii")


def _decode_response(raw: bytes, expected_id: str) -> dict[str, Any]:
    try:
        message = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RemoteDesktopHostError("malformed_response") from exc

    if not isinstance(message, dict):
        raise RemoteDesktopHostError("malformed_response")

    if not set(message).issubset(ALLOWED_RESPONSE_KEYS):
        raise RemoteDesktopHostError("malformed_response")

    request_id = message.get("id")
    status = message.get("status")
    payload = message.get("payload")
    error_code = message.get("errorCode")

    if not isinstance(request_id, str) or request_id.lower() != expected_id.lower():
        raise RemoteDesktopHostError("malformed_response")
    if not isinstance(status, int):
        raise RemoteDesktopHostError("malformed_response")
    if not isinstance(payload, str):
        raise RemoteDesktopHostError("malformed_response")
    if error_code is not None and not isinstance(error_code, str):
        raise RemoteDesktopHostError("malformed_response")

    try:
        decoded_payload = base64.b64decode(payload.encode("ascii"), validate=True)
    except (UnicodeError, binascii.Error) as exc:
        raise RemoteDesktopHostError("malformed_response") from exc

    return {
        "id": request_id,
        "status": status,
        "payload": decoded_payload,
        "errorCode": error_code,
    }


def _default_message_for_code(code: str) -> str:
    if code == "timeout":
        return "Remote desktop host timed out"
    if code == "response_too_large":
        return "Remote desktop host response was too large"
    if code == "request_too_large":
        return "Remote desktop request was too large"
    if code == "malformed_response":
        return "Remote desktop host returned an invalid response"
    if code == "invalid_request":
        return "Remote desktop request is invalid"
    return "Remote desktop host is unavailable"


class RemoteDesktopGateway:
    def __init__(
        self,
        host_client: NativeHostClient | None = None,
        signal_queue_limit: int = SIGNAL_QUEUE_LIMIT,
        turn_urlopen=urllib.request.urlopen,
    ):
        self.host_client = host_client if host_client is not None else NativeHostClient()
        self.signal_queue_limit = max(1, int(signal_queue_limit))
        self.turn_urlopen = turn_urlopen
        self._signal_lock = threading.Lock()
        self._signals: dict[str, list[dict[str, Any]]] = {}
        self._last_signal_sequence: dict[str, int] = {}

    def handle(
        self,
        http_method: str,
        parts: list[str],
        query: dict[str, list[str]],
        body: dict[str, Any] | None,
    ) -> tuple[int, dict[str, Any]]:
        method = http_method.upper()
        try:
            return self._handle(method, parts, query, body)
        except RemoteDesktopHostError as exc:
            return ERROR_STATUS.get(exc.code, 503), {"error": exc.code}
        except RemoteDesktopRequestError as exc:
            return exc.status, {"error": exc.code}

    def _handle(
        self,
        method: str,
        parts: list[str],
        query: dict[str, list[str]],
        body: dict[str, Any] | None,
    ) -> tuple[int, dict[str, Any]]:
        if method == "GET" and parts == ["status"]:
            status = self._native_json("status", {})
            status.setdefault("iceServers", self._ice_servers())
            status.setdefault("capabilities", {})["relayAvailable"] = self._relay_available()
            return 200, status

        if method == "GET" and parts == ["frame"]:
            response = self.host_client.call("frame.capture", {})
            status = int(response.get("status") or 500)
            error_code = response.get("errorCode")
            if status >= 400 or error_code:
                raise RemoteDesktopHostError(str(error_code or "host_unavailable"))
            raw_payload = response.get("payload")
            if not isinstance(raw_payload, (bytes, bytearray)) or not raw_payload:
                raise RemoteDesktopHostError("malformed_response")
            return 200, {
                "_raw": bytes(raw_payload),
                "_content_type": "image/jpeg",
                "_cache_control": "no-store, max-age=0",
            }

        if method == "POST" and parts == ["input"]:
            payload = _input_body(body)
            _validate_identifier(payload["sessionId"])
            _positive_int(payload["sequence"])
            if payload["kind"] not in REMOTE_INPUT_KINDS:
                raise RemoteDesktopRequestError(400, "invalid_request")
            for key in ("x", "y", "deltaX", "deltaY"):
                if payload.get(key) is not None and not isinstance(payload[key], (int, float)):
                    raise RemoteDesktopRequestError(400, "invalid_request")
            for key in ("button", "keyCode"):
                if payload.get(key) is not None and not isinstance(payload[key], int):
                    raise RemoteDesktopRequestError(400, "invalid_request")
            if payload.get("text") is not None and not isinstance(payload["text"], str):
                raise RemoteDesktopRequestError(400, "invalid_request")
            return 200, self._native_json("input.inject", payload)

        if method == "POST" and parts == ["pairing", "start"]:
            payload = _strict_body(body, {"deviceId", "name", "publicKey"})
            _validate_identifier(payload["deviceId"])
            return 200, self._native_json("pairing.start", payload)

        if method == "POST" and parts == ["pairing", "complete"]:
            payload = _strict_body(body, {"challengeId", "deviceId", "signature"})
            _validate_identifier(payload["challengeId"])
            _validate_identifier(payload["deviceId"])
            _require_base64(payload["signature"])
            return 200, self._native_json("pairing.complete", payload)

        if method == "GET" and parts == ["devices"]:
            return 200, self._native_json("devices.list", {})

        if method == "POST" and len(parts) == 3 and parts[0] == "devices" and parts[2] == "revoke":
            device_id = _validate_identifier(parts[1])
            _strict_body(body, set())
            return 200, self._native_json("devices.revoke", {"deviceId": device_id})

        if method == "POST" and parts == ["sessions", "nonce"]:
            payload = _strict_body(body, {"deviceId"})
            _validate_identifier(payload["deviceId"])
            return 200, self._native_json("session.nonce", payload)

        if method == "POST" and parts == ["sessions"]:
            payload = _strict_body(body, {"deviceId", "nonce", "signature"})
            _validate_identifier(payload["deviceId"])
            _validate_identifier(payload["nonce"])
            _require_base64(payload["signature"])
            return 200, self._native_json("session.start", payload)

        if method == "POST" and len(parts) == 3 and parts[0] == "sessions" and parts[2] == "signal":
            session_id = _validate_identifier(parts[1])
            payload = _strict_body(body, {"sequence", "kind", "payload"})
            sequence = _positive_int(payload["sequence"])
            signal_kind = _validate_signal_kind(payload["kind"])
            _require_base64(payload["payload"])
            return 200, self._append_signal(session_id, sequence, signal_kind, payload["payload"])

        if method == "GET" and len(parts) == 3 and parts[0] == "sessions" and parts[2] == "signal":
            session_id = _validate_identifier(parts[1])
            after = _optional_int((query.get("after") or ["0"])[0])
            return 200, {"signals": self._signals_after(session_id, after)}

        if method == "POST" and len(parts) == 3 and parts[0] == "sessions" and parts[2] == "display":
            session_id = _validate_identifier(parts[1])
            payload = _strict_body(body, {"displayId"})
            _validate_identifier(payload["displayId"])
            return 200, self._native_json("session.display", {"sessionId": session_id, **payload})

        if method == "POST" and len(parts) == 3 and parts[0] == "sessions" and parts[2] == "clipboard":
            session_id = _validate_identifier(parts[1])
            payload = _strict_body(body, {"direction", "text"})
            if payload["direction"] not in {"send", "receive"}:
                raise RemoteDesktopRequestError(400, "invalid_request")
            if not isinstance(payload["text"], str):
                raise RemoteDesktopRequestError(400, "invalid_request")
            if len(payload["text"].encode("utf-8")) > MAX_CLIPBOARD_TEXT_BYTES:
                raise RemoteDesktopRequestError(413, "clipboard_too_large")
            return 200, self._native_json("session.clipboard", {"sessionId": session_id, **payload})

        if method == "POST" and len(parts) == 3 and parts[0] == "sessions" and parts[2] == "disconnect":
            session_id = _validate_identifier(parts[1])
            _strict_body(body, set())
            with self._signal_lock:
                self._signals.pop(session_id, None)
                self._last_signal_sequence.pop(session_id, None)
            return 200, self._native_json("session.end", {"sessionId": session_id})

        raise RemoteDesktopRequestError(404, "not_found")

    def _native_json(self, method: str, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.host_client.call(method, payload)
        status = int(response.get("status") or 500)
        error_code = response.get("errorCode")
        if status >= 400 or error_code:
            raise RemoteDesktopHostError(str(error_code or "host_unavailable"))

        raw_payload = response.get("payload")
        if raw_payload in (None, b""):
            return {"ok": True}
        try:
            decoded = json.loads(raw_payload.decode("utf-8"))
        except (AttributeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RemoteDesktopHostError("malformed_response") from exc
        if not isinstance(decoded, dict):
            raise RemoteDesktopHostError("malformed_response")
        return decoded

    def _append_signal(self, session_id: str, sequence: int, kind: str, payload: str) -> dict[str, Any]:
        with self._signal_lock:
            last_sequence = self._last_signal_sequence.get(session_id, 0)
            if sequence <= last_sequence:
                raise RemoteDesktopRequestError(409, "sequence_replay")
            signal = {"sequence": sequence, "kind": kind, "payload": payload}
            queue = self._signals.setdefault(session_id, [])
            queue.append(signal)
            del queue[:-self.signal_queue_limit]
            self._last_signal_sequence[session_id] = sequence
        return {"sequence": sequence}

    def _signals_after(self, session_id: str, after: int) -> list[dict[str, Any]]:
        with self._signal_lock:
            return [
                dict(signal)
                for signal in self._signals.get(session_id, [])
                if int(signal["sequence"]) > after
            ]

    def _relay_available(self) -> bool:
        return bool(os.environ.get("CODEPILOT_TURN_KEY_ID") and os.environ.get("CODEPILOT_TURN_API_TOKEN"))

    def _ice_servers(self) -> list[dict[str, Any]]:
        if not self._relay_available():
            return list(STUN_ONLY_ICE_SERVERS)
        key_id = os.environ["CODEPILOT_TURN_KEY_ID"]
        api_token = os.environ["CODEPILOT_TURN_API_TOKEN"]
        request = urllib.request.Request(
            f"https://rtc.live.cloudflare.com/v1/turn/keys/{key_id}/credentials/generate-ice-servers",
            data=json.dumps({"ttl": 300}, separators=(",", ":")).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with self.turn_urlopen(request, timeout=5) as response:
                raw = response.read()
        except (OSError, urllib.error.URLError) as exc:
            raise RemoteDesktopHostError("turn_unavailable") from exc
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RemoteDesktopHostError("turn_unavailable") from exc
        ice_servers = payload.get("iceServers") if isinstance(payload, dict) else None
        if not isinstance(ice_servers, list):
            raise RemoteDesktopHostError("turn_unavailable")
        return ice_servers


class RemoteDesktopRequestError(ValueError):
    def __init__(self, status: int, code: str):
        self.status = status
        self.code = code
        super().__init__(code)


def _strict_body(body: dict[str, Any] | None, allowed_keys: set[str]) -> dict[str, Any]:
    if body is None:
        body = {}
    if not isinstance(body, dict):
        raise RemoteDesktopRequestError(400, "invalid_request")
    keys = set(body)
    if keys != allowed_keys:
        raise RemoteDesktopRequestError(400, "invalid_request")
    return dict(body)


def _input_body(body: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(body, dict):
        raise RemoteDesktopRequestError(400, "invalid_request")
    keys = set(body)
    if not {"sessionId", "sequence", "kind"}.issubset(keys) or not keys.issubset(REMOTE_INPUT_KEYS):
        raise RemoteDesktopRequestError(400, "invalid_request")
    return dict(body)


def _validate_identifier(value: Any) -> str:
    if not isinstance(value, str):
        raise RemoteDesktopRequestError(400, "invalid_identifier")
    value = value.strip()
    if not value or len(value) > IDENTIFIER_MAX_LENGTH:
        raise RemoteDesktopRequestError(400, "invalid_identifier")
    for character in value:
        if not (character.isalnum() or character in {"-", "_", ".", ":"}):
            raise RemoteDesktopRequestError(400, "invalid_identifier")
    return value


def _require_base64(value: Any) -> str:
    if not isinstance(value, str):
        raise RemoteDesktopRequestError(400, "invalid_base64")
    try:
        base64.b64decode(value.encode("ascii"), validate=True)
    except (UnicodeError, binascii.Error) as exc:
        raise RemoteDesktopRequestError(400, "invalid_base64") from exc
    return value


def _positive_int(value: Any) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise RemoteDesktopRequestError(400, "invalid_request")
    return value


def _optional_int(value: Any) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise RemoteDesktopRequestError(400, "invalid_request") from exc
    return max(0, parsed)


def _validate_signal_kind(value: Any) -> str:
    if value not in {"offer", "answer", "ice"}:
        raise RemoteDesktopRequestError(400, "invalid_request")
    return str(value)
