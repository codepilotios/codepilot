from __future__ import annotations

import base64
import json
import os
import socket
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    from .remote_desktop_gateway import NativeHostClient, RemoteDesktopGateway, RemoteDesktopHostError
except ImportError:
    from remote_desktop_gateway import NativeHostClient, RemoteDesktopGateway, RemoteDesktopHostError


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

    def test_call_accepts_case_changed_uuid_from_swift_host(self):
        response_payload = base64.b64encode(json.dumps({"ok": True}).encode("utf-8")).decode("ascii")

        def handler(conn):
            request = json.loads(_read_line(conn))
            response = {
                "id": request["id"].upper(),
                "status": 200,
                "payload": response_payload,
                "errorCode": None,
            }
            conn.sendall(json.dumps(response).encode("utf-8") + b"\n")

        with UnixSocketServer(self.socket_path, handler):
            client = NativeHostClient(self.socket_path, timeout_seconds=1.0, max_response_bytes=1024)
            response = client.call("status", {})

        self.assertEqual(response["status"], 200)
        self.assertEqual(json.loads(response["payload"].decode("utf-8")), {"ok": True})

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


class FakeNativeHostClient:
    def __init__(self):
        self.calls = []
        self.fail_code = None
        self.responses = {}

    def call(self, method, payload=None):
        self.calls.append((method, payload))
        if self.fail_code:
            raise RemoteDesktopHostError(self.fail_code)
        response = self.responses.get(method)
        if response is None:
            response = {"ok": True, "method": method, "payload": payload}
        if isinstance(response, dict) and {"status", "payload", "errorCode"}.issubset(response):
            return response
        return {
            "id": "native-response",
            "status": 200,
            "payload": json.dumps(response).encode("utf-8"),
            "errorCode": None,
        }


class RemoteDesktopGatewayTests(unittest.TestCase):
    def test_public_status_reports_fail_closed_policy_without_probing_host(self):
        host = FakeNativeHostClient()
        gateway = RemoteDesktopGateway(host_client=host)

        self.assertEqual(
            gateway.public_status(),
            {"available": False, "remoteControlAvailable": False},
        )
        self.assertEqual(host.calls, [])

    def test_remote_control_routes_fail_closed_by_default(self):
        host = FakeNativeHostClient()
        gateway = RemoteDesktopGateway(host_client=host)

        status, payload = gateway.handle("GET", ["frame"], {}, None)

        self.assertEqual(status, 503)
        self.assertEqual(payload["error"], "remote_desktop_disabled")
        self.assertEqual(host.calls, [])

    def test_status_reports_remote_control_unavailable_by_default(self):
        gateway = RemoteDesktopGateway(host_client=FakeNativeHostClient())

        status, payload = gateway.handle("GET", ["status"], {}, None)

        self.assertEqual(status, 200)
        self.assertFalse(payload["capabilities"]["remoteControlAvailable"])
        self.assertFalse(payload["capabilities"]["relayAvailable"])
        self.assertEqual(payload["iceServers"], [])

    def test_rejects_unknown_body_keys_and_malformed_identifiers(self):
        host = FakeNativeHostClient()
        gateway = RemoteDesktopGateway(host_client=host, remote_control_enabled=True)

        status, payload = gateway.handle("POST", ["pairing", "start"], {}, {"deviceId": "phone-1", "extra": True})
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "invalid_request")

        status, payload = gateway.handle("POST", ["devices", "../bad", "revoke"], {}, {})
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "invalid_identifier")
        self.assertEqual(host.calls, [])

    def test_maps_native_errors_to_stable_public_statuses(self):
        host = FakeNativeHostClient()
        host.fail_code = "controller_busy"
        gateway = RemoteDesktopGateway(host_client=host, remote_control_enabled=True)

        status, payload = gateway.handle("POST", ["sessions"], {}, {
            "deviceId": "phone-1",
            "nonce": "nonce-1",
            "signature": base64.b64encode(b"sig").decode("ascii"),
        })

        self.assertEqual(status, 409)
        self.assertEqual(payload["error"], "controller_busy")
        self.assertNotIn("host.sock", json.dumps(payload))

    def test_pairing_and_session_routes_forward_validated_payloads(self):
        host = FakeNativeHostClient()
        gateway = RemoteDesktopGateway(host_client=host, remote_control_enabled=True)

        status, payload = gateway.handle("POST", ["pairing", "complete"], {}, {
            "challengeId": "challenge-1",
            "deviceId": "phone-1",
            "signature": base64.b64encode(b"proof").decode("ascii"),
        })

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(host.calls[0][0], "pairing.complete")
        self.assertEqual(host.calls[0][1]["signature"], base64.b64encode(b"proof").decode("ascii"))

    def test_rejects_invalid_signature_base64(self):
        gateway = RemoteDesktopGateway(host_client=FakeNativeHostClient(), remote_control_enabled=True)

        status, payload = gateway.handle("POST", ["sessions"], {}, {
            "deviceId": "phone-1",
            "nonce": "nonce-1",
            "signature": "not base64?",
        })

        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "invalid_base64")

    def test_signal_queue_is_bounded_monotonic_and_cleared_on_disconnect(self):
        gateway = RemoteDesktopGateway(
            host_client=FakeNativeHostClient(),
            signal_queue_limit=2,
            remote_control_enabled=True,
        )

        for sequence in [1, 2, 3]:
            status, payload = gateway.handle("POST", ["sessions", "session-1", "signal"], {}, {
                "sequence": sequence,
                "kind": "offer",
                "payload": base64.b64encode(f"signal-{sequence}".encode("utf-8")).decode("ascii"),
            })
            self.assertEqual(status, 200)
            self.assertEqual(payload["sequence"], sequence)

        status, payload = gateway.handle("POST", ["sessions", "session-1", "signal"], {}, {
            "sequence": 3,
            "kind": "offer",
            "payload": base64.b64encode(b"replay").decode("ascii"),
        })
        self.assertEqual(status, 409)
        self.assertEqual(payload["error"], "sequence_replay")

        status, payload = gateway.handle("GET", ["sessions", "session-1", "signal"], {"after": ["0"]}, None)
        self.assertEqual(status, 200)
        self.assertEqual([item["sequence"] for item in payload["signals"]], [2, 3])

        status, _ = gateway.handle("POST", ["sessions", "session-1", "disconnect"], {}, {})
        self.assertEqual(status, 200)
        status, payload = gateway.handle("GET", ["sessions", "session-1", "signal"], {"after": ["0"]}, None)
        self.assertEqual(payload["signals"], [])

    def test_clipboard_requires_explicit_text_under_size_limit(self):
        host = FakeNativeHostClient()
        gateway = RemoteDesktopGateway(host_client=host, remote_control_enabled=True)

        status, payload = gateway.handle("POST", ["sessions", "session-1", "clipboard"], {}, {
            "direction": "send",
            "text": "hello",
        })
        self.assertEqual(status, 200)
        self.assertEqual(host.calls[0][0], "session.clipboard")

        status, payload = gateway.handle("POST", ["sessions", "session-1", "clipboard"], {}, {
            "direction": "send",
            "text": "x" * (1_048_576 + 1),
        })
        self.assertEqual(status, 413)
        self.assertEqual(payload["error"], "clipboard_too_large")

        status, payload = gateway.handle("POST", ["sessions", "session-1", "clipboard"], {}, {
            "direction": "send",
            "text": 42,
        })
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "invalid_request")

    def test_status_returns_stun_only_when_turn_environment_is_unset(self):
        old_env = dict(os.environ)
        try:
            os.environ.pop("CODEPILOT_TURN_KEY_ID", None)
            os.environ.pop("CODEPILOT_TURN_API_TOKEN", None)
            gateway = RemoteDesktopGateway(host_client=FakeNativeHostClient(), remote_control_enabled=True)

            status, payload = gateway.handle("GET", ["status"], {}, None)

            self.assertEqual(status, 200)
            self.assertFalse(payload["capabilities"]["relayAvailable"])
            self.assertEqual(payload["iceServers"], [{"urls": ["stun:stun.l.google.com:19302"]}])
        finally:
            os.environ.clear()
            os.environ.update(old_env)

    def test_frame_returns_raw_jpeg_payload(self):
        host = FakeNativeHostClient()
        host.responses["frame.capture"] = {
            "status": 200,
            "payload": b"\xff\xd8jpeg\xff\xd9",
            "errorCode": None,
        }
        gateway = RemoteDesktopGateway(host_client=host, remote_control_enabled=True)

        status, payload = gateway.handle("GET", ["frame"], {}, None)

        self.assertEqual(status, 200)
        self.assertEqual(payload["_raw"], b"\xff\xd8jpeg\xff\xd9")
        self.assertEqual(payload["_content_type"], "image/jpeg")

    def test_input_forwards_validated_event_to_native_host(self):
        host = FakeNativeHostClient()
        gateway = RemoteDesktopGateway(host_client=host, remote_control_enabled=True)
        event = {
            "sessionId": "gateway-session",
            "sequence": 7,
            "kind": "pointer",
            "x": 0.25,
            "y": 0.75,
            "button": None,
            "keyCode": None,
            "text": None,
            "deltaX": None,
            "deltaY": None,
        }

        status, payload = gateway.handle("POST", ["input"], {}, event)

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(host.calls[-1], ("input.inject", event))

    def test_input_accepts_swift_payload_with_omitted_optional_fields(self):
        host = FakeNativeHostClient()
        gateway = RemoteDesktopGateway(host_client=host, remote_control_enabled=True)
        event = {
            "sessionId": "swift-session",
            "sequence": 1,
            "kind": "pointer",
            "x": 0.4,
            "y": 0.6,
        }

        status, payload = gateway.handle("POST", ["input"], {}, event)

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(host.calls[-1], ("input.inject", event))

    def test_input_rejects_unknown_fields(self):
        gateway = RemoteDesktopGateway(host_client=FakeNativeHostClient(), remote_control_enabled=True)

        status, payload = gateway.handle("POST", ["input"], {}, {
            "sessionId": "gateway-session",
            "sequence": 1,
            "kind": "pointer",
            "x": 0.5,
            "y": 0.5,
            "button": None,
            "keyCode": None,
            "text": None,
            "deltaX": None,
            "deltaY": None,
            "unexpected": True,
        })

        self.assertEqual(status, 400)
        self.assertEqual(payload, {"error": "invalid_request"})

    def test_status_generates_cloudflare_turn_ice_servers_when_configured(self):
        old_env = dict(os.environ)
        captured = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def read(self):
                return json.dumps({
                    "iceServers": [{
                        "urls": ["turn:relay.example.com:3478"],
                        "username": "generated-user",
                        "credential": "generated-password",
                    }]
                }).encode("utf-8")

        def fake_urlopen(request, timeout):
            captured["url"] = request.full_url
            captured["headers"] = dict(request.header_items())
            captured["body"] = json.loads(request.data.decode("utf-8"))
            captured["timeout"] = timeout
            return FakeResponse()

        try:
            os.environ["CODEPILOT_TURN_KEY_ID"] = "turn-key-id"
            os.environ["CODEPILOT_TURN_API_TOKEN"] = "secret-token"
            gateway = RemoteDesktopGateway(
                host_client=FakeNativeHostClient(),
                turn_urlopen=fake_urlopen,
                remote_control_enabled=True,
            )

            status, payload = gateway.handle("GET", ["status"], {}, None)

            self.assertEqual(status, 200)
            self.assertTrue(payload["capabilities"]["relayAvailable"])
            self.assertEqual(payload["iceServers"][0]["username"], "generated-user")
            self.assertEqual(captured["url"], "https://rtc.live.cloudflare.com/v1/turn/keys/turn-key-id/credentials/generate-ice-servers")
            self.assertEqual(captured["headers"]["Authorization"], "Bearer secret-token")
            self.assertEqual(captured["body"], {"ttl": 300})
            self.assertEqual(captured["timeout"], 5)
            self.assertNotIn("secret-token", json.dumps(payload))
        finally:
            os.environ.clear()
            os.environ.update(old_env)


class RemoteDesktopHTTPRouteTests(unittest.TestCase):
    def test_remote_routes_require_bearer_auth(self):
        try:
            from . import codex_phone_gateway as phone_gateway
        except ImportError:
            import codex_phone_gateway as phone_gateway

        state = phone_gateway.GatewayState(Path(self._tempdir().name), "secret", Path("/missing-codex"), False)
        server = phone_gateway.GatewayServer(("127.0.0.1", 0), state)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

        url = f"http://127.0.0.1:{server.server_port}/api/remote/status"
        with self.assertRaises(urllib.error.HTTPError) as raised:
            urllib.request.urlopen(url, timeout=2)

        self.assertEqual(raised.exception.code, 401)

    def test_remote_http_route_forwards_after_auth(self):
        try:
            from . import codex_phone_gateway as phone_gateway
        except ImportError:
            import codex_phone_gateway as phone_gateway

        class FakeRemoteDesktopGateway:
            def handle(self, method, parts, query, body):
                return 200, {"method": method, "parts": parts, "body": body}

        tempdir = self._tempdir()
        state = phone_gateway.GatewayState(
            Path(tempdir.name),
            "secret",
            Path("/missing-codex"),
            False,
            remote_desktop_gateway=FakeRemoteDesktopGateway(),
        )
        server = phone_gateway.GatewayServer(("127.0.0.1", 0), state)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_port}/api/remote/pairing/start",
            data=json.dumps({"deviceId": "phone-1", "name": "Phone", "publicKey": "pk"}).encode("utf-8"),
            headers={"Authorization": "Bearer secret", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=2) as response:
            payload = json.loads(response.read().decode("utf-8"))

        self.assertEqual(payload["method"], "POST")
        self.assertEqual(payload["parts"], ["pairing", "start"])
        self.assertEqual(payload["body"]["deviceId"], "phone-1")

    def test_remote_http_route_rejects_oversized_body(self):
        try:
            from . import codex_phone_gateway as phone_gateway
        except ImportError:
            import codex_phone_gateway as phone_gateway

        tempdir = self._tempdir()
        state = phone_gateway.GatewayState(
            Path(tempdir.name),
            "secret",
            Path("/missing-codex"),
            False,
            remote_desktop_gateway=object(),
        )
        server = phone_gateway.GatewayServer(("127.0.0.1", 0), state)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

        with socket.create_connection(("127.0.0.1", server.server_port), timeout=2) as conn:
            request = (
                "POST /api/remote/pairing/start HTTP/1.1\r\n"
                "Host: 127.0.0.1\r\n"
                "Authorization: Bearer secret\r\n"
                "Content-Type: application/json\r\n"
                "Content-Length: 1048577\r\n"
                "Connection: close\r\n"
                "\r\n"
            ).encode("ascii")
            conn.sendall(request)
            response = conn.recv(1024)

        self.assertIn(b"413", response.splitlines()[0])

    def _tempdir(self):
        tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(tempdir.cleanup)
        return tempdir


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
