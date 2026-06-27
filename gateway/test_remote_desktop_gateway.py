from __future__ import annotations

import base64
import json
import os
import socket
import tempfile
import threading
import time
import unittest
from pathlib import Path

try:
    from .remote_desktop_gateway import NativeHostClient, RemoteDesktopHostError
except ImportError:
    from remote_desktop_gateway import NativeHostClient, RemoteDesktopHostError


class UnixSocketServer:
    def __init__(self, socket_path: Path, handler):
        self.socket_path = socket_path
        self.handler = handler
        self._thread = None
        self._ready = threading.Event()
        self._stop = threading.Event()

    def __enter__(self):
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass
        self._server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server.bind(str(self.socket_path))
        self._server.listen(1)
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()
        self._ready.wait(1)
        return self

    def __exit__(self, exc_type, exc, tb):
        self._stop.set()
        try:
            self._server.close()
        finally:
            try:
                os.unlink(self.socket_path)
            except FileNotFoundError:
                pass
        if self._thread is not None:
            self._thread.join(1)

    def _serve(self):
        self._ready.set()
        while not self._stop.is_set():
            try:
                conn, _ = self._server.accept()
            except OSError:
                return
            with conn:
                self.handler(conn)


class NativeHostClientTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.socket_path = Path(self.tempdir.name) / "remote-desktop.sock"

    def tearDown(self):
        self.tempdir.cleanup()

    def test_call_succeeds_and_decodes_payload(self):
        response_payload = base64.b64encode(json.dumps({"ok": True}).encode("utf-8")).decode("ascii")
        expected_request = {}

        def handler(conn):
            line = _read_line(conn)
            expected_request.update(json.loads(line))
            response = {
                "id": expected_request["id"],
                "status": 200,
                "payload": response_payload,
                "errorCode": None,
            }
            conn.sendall(json.dumps(response).encode("utf-8") + b"\n")

        with UnixSocketServer(self.socket_path, handler):
            client = NativeHostClient(self.socket_path, timeout_seconds=1.0, max_response_bytes=1024)
            response = client.call("status", {"scope": "health"})

        self.assertEqual(expected_request["method"], "status")
        self.assertEqual(
            expected_request["payload"],
            base64.b64encode(json.dumps({"scope": "health"}, separators=(",", ":")).encode("utf-8")).decode("ascii"),
        )
        self.assertEqual(response["status"], 200)
        self.assertEqual(json.loads(response["payload"].decode("utf-8")), {"ok": True})

    def test_call_uses_empty_payload_envelope_when_payload_is_missing(self):
        expected_request = {}

        def handler(conn):
            line = _read_line(conn)
            expected_request.update(json.loads(line))
            response = {
                "id": expected_request["id"],
                "status": 200,
                "payload": "",
                "errorCode": None,
            }
            conn.sendall(json.dumps(response).encode("utf-8") + b"\n")

        with UnixSocketServer(self.socket_path, handler):
            client = NativeHostClient(self.socket_path, timeout_seconds=1.0, max_response_bytes=1024)
            response = client.call("status")

        self.assertEqual(expected_request["payload"], "")
        self.assertEqual(response["payload"], b"")

    def test_call_maps_connection_failure_to_safe_error(self):
        client = NativeHostClient(self.socket_path, timeout_seconds=0.1)

        with self.assertRaises(RemoteDesktopHostError) as raised:
            client.call("status", {})

        self.assertEqual(raised.exception.code, "host_unavailable")
        self.assertNotIn(self.socket_path.name, str(raised.exception))

    def test_call_times_out_when_host_is_silent(self):
        def handler(conn):
            _read_line(conn)
            time.sleep(0.5)

        with UnixSocketServer(self.socket_path, handler):
            client = NativeHostClient(self.socket_path, timeout_seconds=0.05)

            with self.assertRaises(RemoteDesktopHostError) as raised:
                client.call("status", {})

        self.assertEqual(raised.exception.code, "timeout")

    def test_call_rejects_malformed_response(self):
        def handler(conn):
            _read_line(conn)
            conn.sendall(b'{"status":200}\n')

        with UnixSocketServer(self.socket_path, handler):
            client = NativeHostClient(self.socket_path, timeout_seconds=1.0)

            with self.assertRaises(RemoteDesktopHostError) as raised:
                client.call("status", {})

        self.assertEqual(raised.exception.code, "malformed_response")

    def test_call_rejects_oversized_response(self):
        def handler(conn):
            _read_line(conn)
            conn.sendall(b'{"id":"1","status":200,"payload":"' + b"x" * 256 + b'","errorCode":null}\n')

        with UnixSocketServer(self.socket_path, handler):
            client = NativeHostClient(self.socket_path, timeout_seconds=1.0, max_response_bytes=128)

            with self.assertRaises(RemoteDesktopHostError) as raised:
                client.call("status", {})

        self.assertEqual(raised.exception.code, "response_too_large")


def _read_line(conn):
    buffer = bytearray()
    while True:
        chunk = conn.recv(1024)
        if not chunk:
            break
        buffer.extend(chunk)
        if b"\n" in chunk:
            break
    return bytes(buffer).split(b"\n", 1)[0].decode("utf-8")


if __name__ == "__main__":
    unittest.main()
