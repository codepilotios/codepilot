from __future__ import annotations

import base64
import binascii
import json
import os
import socket
import uuid
from pathlib import Path
from typing import Any


DEFAULT_REMOTE_DESKTOP_SOCKET_PATH = Path.home() / ".codepilot" / "remote-desktop" / "host.sock"
DEFAULT_TIMEOUT_SECONDS = 5.0
DEFAULT_MAX_REQUEST_BYTES = 1_048_576
DEFAULT_MAX_RESPONSE_BYTES = 1_048_576
ALLOWED_RESPONSE_KEYS = {"id", "status", "payload", "errorCode"}


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

    if not isinstance(request_id, str) or request_id != expected_id:
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
