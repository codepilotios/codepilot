import json
import sqlite3
import io
import os
import subprocess
import tempfile
import tomllib
import unittest
import urllib.request
from unittest import mock
from pathlib import Path

import codex_phone_gateway as gateway
from codex_phone_gateway import CodexAppServerClient, GatewayState, format_stream_event, is_loopback_host


class FakeAppServerProcess:
    def __init__(self, stdout_lines):
        self.stdin = io.StringIO()
        self.stdout = io.StringIO("".join(stdout_lines))
        self.returncode = None

    def poll(self):
        return self.returncode

    def terminate(self):
        self.returncode = -15

    def wait(self, timeout=None):
        return self.returncode


class FailingAppServerClient:
    def start(self):
        raise RuntimeError("app-server disabled for test")


class RecordingRateLimitResetAppServerClient:
    def __init__(self):
        self.started = False
        self.requests = []
        self.closed = False

    def start(self):
        self.started = True
        return {"ok": True}

    def request(self, method, params=None):
        self.requests.append((method, params or {}))
        return {"consumed": True}

    def close(self):
        self.closed = True


class RecordingPushNotifier:
    def __init__(self):
        self.sent = []

    def send_turn_completion(self, devices, notification):
        self.sent.append((devices, notification))

    def send_live_activity(self, registrations, content_state):
        self.sent.append((registrations, content_state))
        return []


class RecordingLocalWebFetcher:
    def __init__(self):
        self.urls = []

    def __call__(self, url):
        self.urls.append(url)
        return 200, {"Content-Type": "text/html; charset=utf-8"}, (
            b'<html><head></head><body>'
            b'<script src="/app.js"></script>'
            b'<a href="http://localhost:3000/settings">Settings</a>'
            b"</body></html>"
        )


class FakeRemoteLoginProcess:
    def __init__(self, codex_home: Path, auth_url: str):
        self.codex_home = codex_home
        self.stdin = io.StringIO()
        self.stdout = io.StringIO(
            "Starting local login server on http://localhost:1455.\n"
            "If your browser did not open, navigate to this URL to authenticate:\n"
            "\n"
            f"{auth_url}\n"
        )
        self.stderr = io.StringIO()
        self.returncode = None
        self.completed = False
        self.terminated = False

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        if self.returncode is None:
            raise subprocess.TimeoutExpired("codex login", timeout)
        return self.returncode

    def terminate(self):
        self.terminated = True
        self.returncode = -15

    def complete(self, auth_payload='{"account":"new-main"}'):
        self.codex_home.mkdir(parents=True, exist_ok=True)
        (self.codex_home / "auth.json").write_text(auth_payload, encoding="utf-8")
        self.completed = True
        self.returncode = 0


class AppServerClientTests(unittest.TestCase):
    def test_gateway_bind_host_recognizes_only_loopback_addresses(self):
        for host in ("localhost", "127.0.0.1", "127.9.8.7", "::1", "[::1]"):
            with self.subTest(host=host):
                self.assertTrue(is_loopback_host(host))
        for host in ("0.0.0.0", "::", "192.0.2.10", "gateway.example.com", ""):
            with self.subTest(host=host):
                self.assertFalse(is_loopback_host(host))

    def setUp(self):
        self._original_switcher_home = gateway.DEFAULT_SWITCHER_HOME
        self._switcher_home_tempdir = tempfile.TemporaryDirectory()
        gateway.DEFAULT_SWITCHER_HOME = Path(self._switcher_home_tempdir.name)
        gateway.DEFAULT_SWITCHER_HOME.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        gateway.DEFAULT_SWITCHER_HOME = self._original_switcher_home
        self._switcher_home_tempdir.cleanup()

    def test_codex_child_env_prepends_homebrew_path_and_sets_codex_home(self):
        old_env = dict(gateway.os.environ)
        try:
            gateway.os.environ.clear()
            gateway.os.environ.update({"PATH": "/usr/bin:/bin"})

            env = gateway.codex_child_env(Path("/tmp/codex-home"))

            self.assertEqual(env["CODEX_HOME"], "/tmp/codex-home")
            self.assertTrue(env["PATH"].startswith("/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:"))
            self.assertIn("/usr/bin:/bin", env["PATH"])
        finally:
            gateway.os.environ.clear()
            gateway.os.environ.update(old_env)

    def test_initializes_app_server_over_stdio(self):
        process = FakeAppServerProcess([
            json.dumps({
                "id": "init-id",
                "result": {
                    "userAgent": "codex-phone-gateway/0.1",
                    "codexHome": "/tmp/codex",
                    "platformFamily": "unix",
                    "platformOs": "macos",
                },
            }) + "\n",
        ])
        calls = []

        def fake_process_factory(args, **kwargs):
            calls.append((args, kwargs))
            return process

        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=fake_process_factory,
            id_factory=lambda: "init-id",
        )

        response = client.start()
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]

        self.assertEqual(calls[0][0], ["/usr/local/bin/codex", "app-server", "--listen", "stdio://"])
        self.assertEqual(calls[0][1]["cwd"], "/tmp/workspace")
        self.assertEqual(sent[0]["method"], "initialize")
        self.assertEqual(sent[0]["params"]["capabilities"]["experimentalApi"], True)
        self.assertEqual(sent[1]["method"], "initialized")
        self.assertEqual(response["platformOs"], "macos")

    def test_start_reuses_initialized_app_server_process(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=lambda: "init-id",
        )

        first = client.start()
        second = client.start()
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]

        self.assertEqual(first, second)
        self.assertEqual([message["method"] for message in sent], ["initialize", "initialized"])

    def test_app_server_client_restarts_when_active_auth_changes(self):
        class FakeClient:
            def __init__(self):
                self.close_count = 0

            def close(self):
                self.close_count += 1

        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            auth_file = codex_home / "auth.json"
            auth_file.write_text('{"account":"old"}', encoding="utf-8")

            state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
            stale_client = FakeClient()
            state._app_server_client = stale_client
            state._app_server_auth_fingerprint = state.active_auth_fingerprint()

            auth_file.write_text('{"account":"new"}', encoding="utf-8")

            next_client = state.app_server_client()

            self.assertIsNot(next_client, stale_client)
            self.assertEqual(stale_client.close_count, 1)
            self.assertEqual(state._app_server_auth_fingerprint, state.active_auth_fingerprint())

    def test_app_server_client_keeps_running_turn_when_active_auth_changes(self):
        class FakeClient:
            def __init__(self):
                self.close_count = 0

            def close(self):
                self.close_count += 1

        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            auth_file = codex_home / "auth.json"
            auth_file.write_text('{"account":"old"}', encoding="utf-8")

            with gateway.JOBS_LOCK:
                old_jobs = dict(gateway.JOBS)
                gateway.JOBS.clear()
                gateway.JOBS["job-1"] = {"id": "job-1", "status": "running"}

            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                stale_client = FakeClient()
                state._app_server_client = stale_client
                state._app_server_auth_fingerprint = state.active_auth_fingerprint()

                auth_file.write_text('{"account":"new"}', encoding="utf-8")

                next_client = state.app_server_client()

                self.assertIs(next_client, stale_client)
                self.assertEqual(stale_client.close_count, 0)
            finally:
                with gateway.JOBS_LOCK:
                    gateway.JOBS.clear()
                    gateway.JOBS.update(old_jobs)

    def test_new_turn_is_rejected_when_auth_changed_but_existing_turn_is_running(self):
        class FakeClient:
            def __init__(self):
                self.close_count = 0

            def close(self):
                self.close_count += 1

        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            auth_file = codex_home / "auth.json"
            auth_file.write_text('{"account":"old"}', encoding="utf-8")

            with gateway.JOBS_LOCK:
                old_jobs = dict(gateway.JOBS)
                gateway.JOBS.clear()
                gateway.JOBS["job-1"] = {"id": "job-1", "status": "running", "threadId": "thread-a"}

            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                stale_client = FakeClient()
                state._app_server_client = stale_client
                state._app_server_auth_fingerprint = state.active_auth_fingerprint()

                auth_file.write_text('{"account":"new"}', encoding="utf-8")

                with self.assertRaisesRegex(RuntimeError, "previous account"):
                    state.ensure_app_server_ready_for_new_turn()
                self.assertEqual(stale_client.close_count, 0)
            finally:
                with gateway.JOBS_LOCK:
                    gateway.JOBS.clear()
                    gateway.JOBS.update(old_jobs)

    def test_new_turn_is_rejected_when_active_account_auth_is_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            codex_home.mkdir()
            switcher_home.mkdir()
            (codex_home / "auth.json").write_text("{}", encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")
            (switcher_home / "usage.json").write_text(json.dumps({
                "Main": {
                    "authStaleAt": "2026-05-24T05:00:00Z",
                    "authStaleReason": "refresh token was already used",
                },
            }), encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)

                with self.assertRaisesRegex(RuntimeError, "Refresh the Main login"):
                    state.ensure_app_server_ready_for_new_turn()
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_completed_turn_closes_stale_app_server_after_last_running_job_finishes(self):
        class FakeClient:
            def __init__(self):
                self.close_count = 0

            def close(self):
                self.close_count += 1

        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            auth_file = codex_home / "auth.json"
            auth_file.write_text('{"account":"old"}', encoding="utf-8")

            with gateway.JOBS_LOCK:
                old_jobs = dict(gateway.JOBS)
                gateway.JOBS.clear()
                gateway.JOBS["job-1"] = {
                    "id": "job-1",
                    "status": "running",
                    "threadId": "thread-a",
                    "turnId": "turn-1",
                    "events": [],
                }

            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                stale_client = FakeClient()
                state._app_server_client = stale_client
                state._app_server_auth_fingerprint = state.active_auth_fingerprint()

                auth_file.write_text('{"account":"new"}', encoding="utf-8")
                state.handle_app_server_notification({
                    "method": "turn/completed",
                    "params": {"threadId": "thread-a", "turnId": "turn-1"},
                })

                self.assertEqual(gateway.JOBS["job-1"]["status"], "completed")
                self.assertEqual(stale_client.close_count, 1)
                self.assertIsNone(state._app_server_client)
            finally:
                with gateway.JOBS_LOCK:
                    gateway.JOBS.clear()
                    gateway.JOBS.update(old_jobs)

    def test_turn_auth_failure_marks_active_account_stale_and_closes_app_server(self):
        class FakeClient:
            def __init__(self):
                self.close_count = 0

            def close(self):
                self.close_count += 1

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            codex_home.mkdir()
            switcher_home.mkdir()
            (codex_home / "auth.json").write_text("{}", encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")

            with gateway.JOBS_LOCK:
                old_jobs = dict(gateway.JOBS)
                gateway.JOBS.clear()
                gateway.JOBS["job-1"] = {
                    "id": "job-1",
                    "status": "running",
                    "threadId": "thread-a",
                    "turnId": "turn-1",
                    "events": [],
                }

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                stale_client = FakeClient()
                state._app_server_client = stale_client
                state._app_server_auth_fingerprint = state.active_auth_fingerprint()

                state.handle_app_server_notification({
                    "method": "turn/completed",
                    "params": {
                        "threadId": "thread-a",
                        "turnId": "turn-1",
                        "turn": {
                            "error": {
                                "message": "Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again.",
                            },
                        },
                    },
                })

                usage = json.loads((switcher_home / "usage.json").read_text(encoding="utf-8"))
                self.assertEqual(gateway.JOBS["job-1"]["status"], "failed")
                self.assertIn("refresh token was already used", usage["Main"]["authStaleReason"])
                self.assertEqual(stale_client.close_count, 1)
                self.assertIsNone(state._app_server_client)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home
                with gateway.JOBS_LOCK:
                    gateway.JOBS.clear()
                    gateway.JOBS.update(old_jobs)

    def test_turn_steer_sends_expected_turn_precondition_and_text_input(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "steer-id", "result": {}}) + "\n",
        ])

        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "steer-id"]).__next__,
        )

        client.start()
        client.turn_steer("thread-1", "turn-1", "Focus on the iPhone UI.")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        steer = sent[2]

        self.assertEqual(steer["method"], "turn/steer")
        self.assertEqual(steer["params"]["threadId"], "thread-1")
        self.assertEqual(steer["params"]["expectedTurnId"], "turn-1")
        self.assertEqual(steer["params"]["input"], [{
            "type": "text",
            "text": "Focus on the iPhone UI.",
            "text_elements": [],
        }])

    def test_thread_start_sends_reasoning_effort_config(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "start-id", "result": {"thread": {"id": "thread-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "start-id"]).__next__,
        )

        client.start()
        client.thread_start("/tmp/workspace", reasoning_effort="high")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        start = sent[2]

        self.assertEqual(start["method"], "thread/start")
        self.assertEqual(start["params"]["config"], {"model_reasoning_effort": "medium"})

    def test_thread_start_uses_safe_policy_by_default(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "start-id", "result": {"thread": {"id": "thread-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "start-id"]).__next__,
        )

        client.start()
        client.thread_start("/tmp/workspace")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        start = sent[2]

        self.assertEqual(start["params"]["approvalPolicy"], "on-request")
        self.assertEqual(start["params"]["sandbox"], "workspace-write")

    def test_thread_start_allows_dangerous_mode_when_explicitly_enabled(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "start-id", "result": {"thread": {"id": "thread-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "start-id"]).__next__,
            allow_dangerous=True,
        )

        client.start()
        client.thread_start("/tmp/workspace")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        start = sent[2]

        self.assertEqual(start["params"]["approvalPolicy"], "never")
        self.assertEqual(start["params"]["sandbox"], "danger-full-access")

    def test_turn_start_sends_reasoning_effort(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "turn-id", "result": {"turn": {"id": "turn-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "turn-id"]).__next__,
        )

        client.start()
        client.turn_start("thread-1", "Hello", reasoning_effort="minimal")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        turn = sent[2]

        self.assertEqual(turn["method"], "turn/start")
        self.assertEqual(turn["params"]["effort"], "medium")

    def test_turn_start_uses_safe_policy_by_default(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "turn-id", "result": {"turn": {"id": "turn-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "turn-id"]).__next__,
        )

        client.start()
        client.turn_start("thread-1", "Hello")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        turn = sent[2]

        self.assertEqual(turn["params"]["approvalPolicy"], "on-request")
        self.assertEqual(turn["params"]["sandboxPolicy"], {"type": "workspaceWrite"})

    def test_turn_start_allows_dangerous_mode_only_when_explicitly_enabled(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "turn-id", "result": {"turn": {"id": "turn-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "turn-id"]).__next__,
            allow_dangerous=True,
        )

        client.start()
        client.turn_start("thread-1", "Hello")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        turn = sent[2]

        self.assertEqual(turn["params"]["approvalPolicy"], "never")
        self.assertEqual(turn["params"]["sandboxPolicy"], {"type": "dangerFullAccess"})

    def test_thread_start_maps_minimal_reasoning_effort_to_medium(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "start-id", "result": {"thread": {"id": "thread-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "start-id"]).__next__,
        )

        client.start()
        client.thread_start("/tmp/workspace", reasoning_effort="minimal")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        start = sent[2]

        self.assertEqual(start["method"], "thread/start")
        self.assertEqual(start["params"]["config"], {"model_reasoning_effort": "medium"})

    def test_thread_resume_sends_thread_id(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "resume-id", "result": {"thread": {"id": "thread-1"}}}) + "\n",
        ])

        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "resume-id"]).__next__,
        )

        client.start()
        client.thread_resume("thread-1")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]
        resume = sent[2]

        self.assertEqual(resume["method"], "thread/resume")
        self.assertEqual(resume["params"]["threadId"], "thread-1")

    def test_notifications_are_delivered_while_waiting_for_response(self):
        notifications = []
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"method": "turn/started", "params": {"threadId": "thread-1", "turn": {"id": "turn-1"}}}) + "\n",
            json.dumps({"id": "turn-id", "result": {"turn": {"id": "turn-1"}}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "turn-id"]).__next__,
            notification_handler=notifications.append,
        )

        client.start()
        response = client.turn_start("thread-1", "Hello")

        self.assertEqual(response["turn"]["id"], "turn-1")
        self.assertEqual(notifications, [{
            "method": "turn/started",
            "params": {"threadId": "thread-1", "turn": {"id": "turn-1"}},
        }])

    def test_thread_rename_and_archive_use_app_server_methods(self):
        process = FakeAppServerProcess([
            json.dumps({"id": "init-id", "result": {"userAgent": "ua", "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "macos"}}) + "\n",
            json.dumps({"id": "rename-id", "result": {}}) + "\n",
            json.dumps({"id": "archive-id", "result": {}}) + "\n",
        ])
        client = CodexAppServerClient(
            codex_path=Path("/usr/local/bin/codex"),
            cwd=Path("/tmp/workspace"),
            process_factory=lambda args, **kwargs: process,
            id_factory=iter(["init-id", "rename-id", "archive-id"]).__next__,
        )

        client.start()
        client.thread_set_name("thread-1", "New title")
        client.thread_archive("thread-1")
        sent = [json.loads(line) for line in process.stdin.getvalue().splitlines()]

        self.assertEqual(sent[2]["method"], "thread/name/set")
        self.assertEqual(sent[2]["params"], {"threadId": "thread-1", "name": "New title"})
        self.assertEqual(sent[3]["method"], "thread/archive")
        self.assertEqual(sent[3]["params"], {"threadId": "thread-1"})


class StreamEventFormattingTests(unittest.TestCase):
    def test_formats_mcp_tool_started_event(self):
        line = json.dumps({
            "type": "item.started",
            "item": {
                "id": "item_1",
                "type": "mcp_tool_call",
                "server": "codex_apps",
                "tool": "supabase_execute_sql",
                "arguments": {
                    "project_id": "abc123",
                    "query": "select * from public.payment_records",
                },
                "status": "in_progress",
            },
        })

        event = format_stream_event(line, 7)

        self.assertEqual(event["id"], "item_1")
        self.assertEqual(event["kind"], "tool")
        self.assertEqual(event["status"], "running")
        self.assertEqual(event["title"], "supabase_execute_sql")
        self.assertEqual(event["subtitle"], "codex_apps")
        self.assertIn("project_id", event["body"])

    def test_formats_agent_message_event(self):
        line = json.dumps({
            "type": "item.completed",
            "item": {
                "id": "item_2",
                "type": "agent_message",
                "text": "Updated the Tap to Pay payment record.",
            },
        })

        event = format_stream_event(line, 8)

        self.assertEqual(event["kind"], "message")
        self.assertEqual(event["status"], "completed")
        self.assertEqual(event["title"], "Codex")
        self.assertEqual(event["body"], "Updated the Tap to Pay payment record.")

    def test_formats_file_change_event_with_api_diff_stats(self):
        line = json.dumps({
            "type": "item.completed",
            "item": {
                "id": "change-1",
                "type": "fileChange",
                "status": "completed",
                "changes": [{
                    "path": "/tmp/App.swift",
                    "kind": {"type": "update"},
                    "diff": (
                        "@@ -1,3 +1,4 @@\n"
                        " import SwiftUI\n"
                        "-let old = true\n"
                        "+let newValue = true\n"
                        "+let other = false\n"
                        " struct AppView: View {}\n"
                    ),
                }],
            },
        })

        event = format_stream_event(line, 9)

        self.assertEqual(event["kind"], "fileChange")
        self.assertEqual(event["title"], "File changes")
        self.assertEqual(event["diffStats"], {"added": 2, "removed": 1})
        self.assertIn("/tmp/App.swift", event["body"])

    def test_app_server_turn_diff_updated_exposes_cumulative_diff_stats(self):
        event = gateway.app_server_notification_event({
            "method": "turn/diff/updated",
            "params": {
                "threadId": "thread-1",
                "turnId": "turn-1",
                "diff": (
                    "diff --git a/App.swift b/App.swift\n"
                    "--- a/App.swift\n"
                    "+++ b/App.swift\n"
                    "@@ -1,3 +1,4 @@\n"
                    " import SwiftUI\n"
                    "-let old = true\n"
                    "+let newValue = true\n"
                    "+let other = false\n"
                    " struct AppView: View {}\n"
                ),
            },
        })

        self.assertEqual(event["id"], "turn.diff")
        self.assertEqual(event["kind"], "context")
        self.assertEqual(event["title"], "Updated")
        self.assertEqual(event["rawType"], "turn/diff/updated")
        self.assertEqual(event["diffStats"], {"added": 2, "removed": 1})

    def test_formats_thread_context_event(self):
        line = json.dumps({
            "type": "thread.started",
            "thread_id": "019e2d2b-cec3-7f91-bc01-ec4401121c07",
        })

        event = format_stream_event(line, 1)

        self.assertEqual(event["kind"], "context")
        self.assertEqual(event["title"], "Thread resumed")
        self.assertIn("019e2d2b", event["body"])

    def test_summarizes_non_json_auth_warning(self):
        line = (
            "2026-05-16T17:48:16.070724Z ERROR rmcp::transport::worker: "
            "worker quit with fatal: Transport channel closed, when AuthRequired "
            'resource_metadata="https://mcp.cloudflare.com/.well-known/oauth-protected-resource/mcp"'
        )

        event = format_stream_event(line, 3)

        self.assertEqual(event["kind"], "warning")
        self.assertEqual(event["title"], "Cloudflare auth warning")
        self.assertNotIn("2026-05-16T17:48:16", event["body"])

    def test_app_server_agent_delta_event_accumulates_inline_message(self):
        job = {}

        first = gateway.app_server_agent_delta_event(job, {
            "itemId": "msg-1",
            "delta": "Hello",
        })
        second = gateway.app_server_agent_delta_event(job, {
            "itemId": "msg-1",
            "delta": " world",
        })

        self.assertEqual(first["id"], "msg-1")
        self.assertEqual(first["kind"], "message")
        self.assertEqual(first["body"], "Hello")
        self.assertEqual(first["rawType"], "item/agentMessage/delta")
        self.assertEqual(second["body"], "Hello world")

    def test_cached_streamed_messages_merge_with_rollout_messages(self):
        rollout_messages = [{
            "id": "rollout-1",
            "role": "assistant",
            "text": "Persisted rollout message",
            "timestamp": "2026-05-20T18:00:00Z",
        }]
        cached_messages = [{
            "id": "msg-1",
            "role": "assistant",
            "text": "Recovered streamed message",
            "timestamp": "2026-05-20T18:01:00+00:00",
        }]

        merged = gateway.merge_thread_messages(rollout_messages, cached_messages)

        self.assertEqual([message["id"] for message in merged], ["rollout-1", "msg-1"])

    def test_cached_streamed_messages_are_merged_by_timestamp(self):
        app_server_messages = [{
            "id": "newer",
            "role": "assistant",
            "text": "Newer app-server message",
            "timestamp": "2026-05-22T05:22:08+00:00",
        }]
        cached_messages = [{
            "id": "older",
            "role": "assistant",
            "text": "Older cached streamed message",
            "timestamp": "2026-05-20T18:58:22+00:00",
        }]

        merged = gateway.merge_thread_messages(app_server_messages, cached_messages)

        self.assertEqual([message["id"] for message in merged], ["older", "newer"])

    def test_messages_without_timestamps_do_not_sort_after_latest_messages(self):
        timestamped_messages = [{
            "id": "latest",
            "role": "assistant",
            "text": "Latest finished turn",
            "timestamp": "2026-06-12T04:34:32+00:00",
        }]
        untimestamped_messages = [{
            "id": "old-cache",
            "role": "assistant",
            "text": "Old cached status update",
            "timestamp": "",
        }]

        merged = gateway.merge_thread_messages(timestamped_messages, untimestamped_messages)

        self.assertEqual([message["id"] for message in merged], ["old-cache", "latest"])

    def test_app_server_thread_read_extracts_user_and_agent_messages(self):
        thread = {
            "id": "thread-1",
            "name": "Main",
            "preview": "Fallback title",
            "cwd": "/tmp/workspace",
            "path": "/tmp/rollout.jsonl",
            "updatedAt": 20,
            "createdAt": 10,
            "source": "vscode",
            "threadSource": "user",
            "turns": [{
                "id": "turn-1",
                "startedAt": 100,
                "completedAt": 110,
                "items": [
                    {
                        "type": "userMessage",
                        "id": "user-1",
                        "content": [{"type": "text", "text": "Please fix sync"}],
                    },
                    {
                        "type": "agentMessage",
                        "id": "agent-1",
                        "text": "I fixed the sync path.",
                        "phase": "final",
                    },
                    {
                        "type": "agentMessage",
                        "id": "hidden-1",
                        "text": "<environment_context>hidden</environment_context>",
                        "phase": "commentary",
                    },
                ],
            }],
        }

        phone_thread = gateway.app_server_thread_to_phone_thread(thread, include_messages=True)

        self.assertEqual(phone_thread["title"], "Main")
        self.assertEqual(phone_thread["rolloutPath"], "/tmp/rollout.jsonl")
        self.assertEqual(
            [(message["role"], message["text"]) for message in phone_thread["messages"]],
            [("user", "Please fix sync"), ("assistant", "I fixed the sync path.")],
        )
        self.assertEqual(phone_thread["messages"][0]["timestamp"], "1970-01-01T00:01:40+00:00")

    def test_app_server_message_ids_are_scoped_to_thread(self):
        def phone_message_ids(thread_id):
            thread = {
                "id": thread_id,
                "turns": [{
                    "startedAt": 100,
                    "items": [
                        {
                            "type": "userMessage",
                            "id": "item-1",
                            "content": [{"type": "text", "text": f"Hello from {thread_id}"}],
                        },
                        {
                            "type": "agentMessage",
                            "id": "item-2",
                            "text": f"Reply from {thread_id}",
                            "phase": "final",
                        },
                    ],
                }],
            }
            return [message["id"] for message in gateway.messages_from_app_server_thread(thread)]

        self.assertEqual(phone_message_ids("thread-a"), ["thread-a:item-1", "thread-a:item-2"])
        self.assertEqual(phone_message_ids("thread-b"), ["thread-b:item-1", "thread-b:item-2"])


class GatewayStateTests(unittest.TestCase):
    def setUp(self):
        self._original_switcher_home = gateway.DEFAULT_SWITCHER_HOME
        self._switcher_home_tempdir = tempfile.TemporaryDirectory()
        gateway.DEFAULT_SWITCHER_HOME = Path(self._switcher_home_tempdir.name)
        gateway.DEFAULT_SWITCHER_HOME.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        gateway.DEFAULT_SWITCHER_HOME = self._original_switcher_home
        self._switcher_home_tempdir.cleanup()

    def test_gateway_token_file_permissions_are_repaired(self):
        token_path = gateway.DEFAULT_SWITCHER_HOME / "gateway-token"
        token_path.write_text("existing-token\n", encoding="utf-8")
        token_path.chmod(0o644)

        self.assertEqual(gateway.read_or_create_token(token_path), "existing-token")
        self.assertEqual(token_path.stat().st_mode & 0o777, 0o600)

    def test_gateway_token_rejects_symlink(self):
        target = gateway.DEFAULT_SWITCHER_HOME / "target"
        target.write_text("token\n", encoding="utf-8")
        token_path = gateway.DEFAULT_SWITCHER_HOME / "gateway-token"
        token_path.symlink_to(target)

        with self.assertRaisesRegex(RuntimeError, "regular file"):
            gateway.read_or_create_token(token_path)

    def test_saved_attachments_are_private(self):
        original_uploads_dir = gateway.DEFAULT_UPLOADS_DIR
        gateway.DEFAULT_UPLOADS_DIR = gateway.DEFAULT_SWITCHER_HOME / "uploads"
        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            saved = state.save_attachments("thread", "job", [{
                "filename": "notes.txt",
                "mimeType": "text/plain",
                "dataBase64": "c2VjcmV0",
            }])
        finally:
            gateway.DEFAULT_UPLOADS_DIR = original_uploads_dir

        path = saved[0]["path"]
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(path.parent.parent.stat().st_mode & 0o777, 0o700)

    def test_expired_upload_batches_are_removed_without_following_symlinks(self):
        uploads = gateway.DEFAULT_SWITCHER_HOME / "uploads"
        expired = uploads / "thread-a" / "expired-job"
        current = uploads / "thread-a" / "current-job"
        outside = gateway.DEFAULT_SWITCHER_HOME / "outside"
        expired.mkdir(parents=True)
        current.mkdir(parents=True)
        outside.mkdir()
        (expired / "private.txt").write_text("expired", encoding="utf-8")
        (current / "private.txt").write_text("current", encoding="utf-8")
        (uploads / "thread-a" / "linked-job").symlink_to(outside, target_is_directory=True)
        os.utime(expired, (100, 100))
        os.utime(current, (900, 900))

        removed = gateway.cleanup_expired_uploads(
            uploads,
            now=1_000,
            retention_seconds=500,
        )

        self.assertEqual(removed, 1)
        self.assertFalse(expired.exists())
        self.assertTrue((current / "private.txt").exists())
        self.assertTrue(outside.exists())
        self.assertTrue((uploads / "thread-a" / "linked-job").is_symlink())

    def test_upload_cleanup_refuses_symlinked_root(self):
        outside = gateway.DEFAULT_SWITCHER_HOME / "outside"
        outside.mkdir()
        private_file = outside / "private.txt"
        private_file.write_text("keep", encoding="utf-8")
        uploads = gateway.DEFAULT_SWITCHER_HOME / "uploads"
        uploads.symlink_to(outside, target_is_directory=True)

        removed = gateway.cleanup_expired_uploads(
            uploads,
            now=1_000,
            retention_seconds=1,
        )

        self.assertEqual(removed, 0)
        self.assertTrue(private_file.exists())

    def test_saved_attachments_reject_symlinked_upload_root(self):
        original_uploads_dir = gateway.DEFAULT_UPLOADS_DIR
        outside = gateway.DEFAULT_SWITCHER_HOME / "outside"
        outside.mkdir()
        gateway.DEFAULT_UPLOADS_DIR = gateway.DEFAULT_SWITCHER_HOME / "uploads"
        gateway.DEFAULT_UPLOADS_DIR.symlink_to(outside, target_is_directory=True)
        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            with self.assertRaisesRegex(RuntimeError, "real directory"):
                state.save_attachments("thread", "job", [{
                    "filename": "notes.txt",
                    "mimeType": "text/plain",
                    "dataBase64": "c2VjcmV0",
                }])
        finally:
            gateway.DEFAULT_UPLOADS_DIR = original_uploads_dir

        self.assertEqual(list(outside.iterdir()), [])

    def test_cached_thread_messages_are_private(self):
        original_cache_dir = gateway.DEFAULT_THREAD_MESSAGE_CACHE_DIR
        gateway.DEFAULT_THREAD_MESSAGE_CACHE_DIR = gateway.DEFAULT_SWITCHER_HOME / "message-cache"
        gateway.DEFAULT_THREAD_MESSAGE_CACHE_DIR.mkdir(mode=0o755)
        try:
            gateway.cache_thread_message("thread", "message", "private response")
            cache_path = gateway.message_cache_path("thread")
            cached = gateway.read_cached_thread_messages("thread")
        finally:
            gateway.DEFAULT_THREAD_MESSAGE_CACHE_DIR = original_cache_dir

        self.assertEqual(cache_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(cache_path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(cached[0]["text"], "private response")

    def test_gateway_logs_redact_queries_and_local_web_capabilities(self):
        handler = object.__new__(gateway.Handler)
        handler.command = "GET"
        handler.path = "/api/local-web/private-capability/dashboard?path=/private/file"
        handler.request_version = "HTTP/1.1"

        with mock.patch.object(handler, "log_message") as log_message:
            handler.log_request(200, 42)

        format_string, *arguments = log_message.call_args.args
        rendered = format_string % tuple(arguments)
        self.assertIn("/api/local-web/[redacted]", rendered)
        self.assertNotIn("private-capability", rendered)
        self.assertNotIn("/private/file", rendered)

    def test_gateway_logs_escape_control_characters(self):
        handler = object.__new__(gateway.Handler)
        handler.client_address = ("127.0.0.1", 12345)

        with mock.patch("builtins.print") as print_mock:
            handler.log_message("request %s", "safe\nforged")

        self.assertEqual(print_mock.call_args.args[0], r"127.0.0.1 - request safe\x0aforged")

    def test_exec_fallback_uses_private_temporary_output_and_removes_it(self):
        captured = {}

        class Process:
            stdin = io.StringIO()
            stdout = []

            @staticmethod
            def wait():
                return 0

        def process_factory(arguments, **_kwargs):
            output_path = Path(arguments[arguments.index("-o") + 1])
            captured["path"] = output_path
            captured["mode"] = output_path.stat().st_mode & 0o777
            output_path.write_text("Finished privately", encoding="utf-8")
            return Process()

        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        job_id = "private-output-test"
        gateway.JOBS[job_id] = {
            "id": job_id,
            "threadId": "thread-id",
            "status": "running",
            "events": [],
        }
        try:
            with mock.patch.object(gateway.subprocess, "Popen", side_effect=process_factory):
                state.run_turn_exec(
                    job_id,
                    {"id": "thread-id", "cwd": "/tmp"},
                    "prompt",
                    [],
                )

            self.assertEqual(captured["mode"], 0o600)
            self.assertFalse(captured["path"].exists())
            self.assertEqual(gateway.JOBS[job_id]["lastMessage"], "Finished privately")
        finally:
            gateway.JOBS.pop(job_id, None)

    def test_public_health_exposes_safe_gateway_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            original_switcher_home = gateway.DEFAULT_SWITCHER_HOME
            switcher_home = Path(tmp) / "switcher"
            codex_home = Path(tmp) / "codex"
            try:
                gateway.DEFAULT_SWITCHER_HOME = switcher_home
                switcher_home.mkdir()
                codex_home.mkdir()
                (switcher_home / "active-account.txt").write_text("main", encoding="utf-8")
                state = GatewayState(codex_home, "secret-token", Path("/missing-codex"), False)

                health = state.public_health()
            finally:
                gateway.DEFAULT_SWITCHER_HOME = original_switcher_home

            self.assertTrue(health["gateway"]["running"])
            self.assertEqual(health["accounts"]["active"], "main")
            self.assertIn("auth", health["accounts"])
            self.assertIn("notifications", health)
            self.assertIn("remoteDesktop", health)
            self.assertIn("localWeb", health)
            self.assertNotIn("secret-token", json.dumps(health))

    def test_error_payload_has_stable_code_message_and_recovery(self):
        payload = gateway.error_payload(
            "local_web_invalid_target",
            "Only localhost URLs can be opened.",
            "Open a localhost, 127.0.0.1, or ::1 URL from the iPhone app.",
        )

        self.assertEqual(payload["error"]["code"], "local_web_invalid_target")
        self.assertEqual(payload["error"]["message"], "Only localhost URLs can be opened.")
        self.assertIn("localhost", payload["error"]["recovery"])

    def test_decode_body_rejects_oversized_json_by_default(self):
        class Handler:
            headers = {"content-length": str(gateway.MAX_JSON_BODY_BYTES + 1)}
            rfile = io.BytesIO(b"")

        with self.assertRaises(gateway.RequestBodyTooLarge):
            gateway.decode_body(Handler())

    def test_decode_body_rejects_invalid_content_length(self):
        class Handler:
            headers = {"content-length": "invalid"}
            rfile = io.BytesIO(b"")

        with self.assertRaisesRegex(ValueError, "invalid_content_length"):
            gateway.decode_body(Handler())

    def test_decode_body_requires_json_object(self):
        body = b"[]"

        class Handler:
            headers = {"content-length": str(len(body))}
            rfile = io.BytesIO(body)

        with self.assertRaisesRegex(ValueError, "request_body_must_be_an_object"):
            gateway.decode_body(Handler())

    def test_resolve_requested_file_path_accepts_absolute_file_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            file_path = Path(tmp) / "created-by-codex.txt"
            file_path.write_text("hello", encoding="utf-8")

            resolved = gateway.resolve_requested_file_path(f"{file_path}:12", allowed_roots=[Path(tmp)])

            self.assertEqual(resolved, file_path.resolve())

    def test_resolve_requested_file_path_rejects_relative_paths(self):
        with self.assertRaises(ValueError):
            gateway.resolve_requested_file_path("created-by-codex.txt")

    def test_resolve_requested_file_path_rejects_files_outside_allowed_roots(self):
        with tempfile.TemporaryDirectory() as tmp, tempfile.TemporaryDirectory() as other:
            file_path = Path(other) / "private.txt"
            file_path.write_text("private", encoding="utf-8")

            with self.assertRaisesRegex(PermissionError, "download roots"):
                gateway.resolve_requested_file_path(str(file_path), allowed_roots=[Path(tmp)])

    def test_file_metadata_reports_download_details(self):
        with tempfile.TemporaryDirectory() as tmp:
            file_path = Path(tmp) / "created-by-codex.txt"
            file_path.write_text("hello", encoding="utf-8")

            metadata = gateway.file_metadata(file_path)

            self.assertEqual(metadata["path"], str(file_path))
            self.assertEqual(metadata["filename"], "created-by-codex.txt")
            self.assertEqual(metadata["mimeType"], "text/plain")
            self.assertEqual(metadata["size"], 5)

    def test_local_web_session_rejects_non_loopback_url(self):
        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)

        with self.assertRaises(ValueError):
            state.start_local_web_session("https://example.com")

    def test_local_web_session_returns_gateway_path_for_localhost_url(self):
        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)

        session = state.start_local_web_session("http://localhost:3000/dashboard?tab=logs")

        self.assertEqual(session["targetOrigin"], "http://127.0.0.1:3000")
        self.assertRegex(session["path"], r"^/api/local-web/[^/]+/dashboard\?tab=logs$")
        self.assertGreater(session["expiresAt"], 0)
        self.assertLessEqual(
            session["expiresAt"] - int(gateway.time.time()),
            gateway.LOCAL_WEB_SESSION_TIMEOUT_SECONDS,
        )

    def test_local_web_session_evicts_oldest_capability_at_limit(self):
        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)

        sessions = [
            state.start_local_web_session("http://localhost:3000/")
            for _ in range(gateway.LOCAL_WEB_MAX_ACTIVE_SESSIONS + 1)
        ]

        with self.assertRaises(LookupError):
            state.proxy_local_web_session(sessions[0]["sessionId"], [], "")
        self.assertEqual(len(state._local_web_sessions), gateway.LOCAL_WEB_MAX_ACTIVE_SESSIONS)

    def test_local_web_session_expires_after_request_limit(self):
        fetcher = RecordingLocalWebFetcher()
        state = GatewayState(
            Path("/tmp/codex"),
            "token",
            Path("/missing-codex"),
            False,
            local_web_fetcher=fetcher,
        )
        session = state.start_local_web_session("http://localhost:3000/")
        session_id = session["sessionId"]
        state._local_web_sessions[session_id]["requestCount"] = gateway.LOCAL_WEB_MAX_REQUESTS_PER_SESSION

        with self.assertRaises(LookupError):
            state.proxy_local_web_session(session_id, [], "")

    def test_local_web_redirect_cannot_leave_selected_loopback_origin(self):
        handler = gateway.LoopbackOnlyRedirectHandler()
        request = urllib.request.Request("http://127.0.0.1:3000/")

        with self.assertRaisesRegex(RuntimeError, "selected loopback origin"):
            handler.redirect_request(request, None, 302, "Found", {}, "https://example.com/")

    def test_local_web_session_proxies_localhost_content_and_rewrites_same_origin_links(self):
        fetcher = RecordingLocalWebFetcher()
        state = GatewayState(
            Path("/tmp/codex"),
            "token",
            Path("/missing-codex"),
            False,
            local_web_fetcher=fetcher,
        )
        session = state.start_local_web_session("http://localhost:3000/dashboard")
        session_id = session["sessionId"]

        response = state.proxy_local_web_session(session_id, ["dashboard"], "")

        self.assertEqual(fetcher.urls, ["http://127.0.0.1:3000/dashboard"])
        self.assertEqual(response["status"], 200)
        self.assertEqual(response["contentType"], "text/html; charset=utf-8")
        self.assertIn(b'src="/api/local-web/', response["body"])
        self.assertIn(b'href="/api/local-web/', response["body"])

    def test_prepare_workspace_can_create_new_project_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
            project_path = Path(tmp) / "Developer" / "new-project"

            workspace = state.prepare_workspace(str(project_path), create=True)

            self.assertEqual(workspace, str(project_path.resolve()))
            self.assertTrue(project_path.is_dir())

    def test_prepare_workspace_rejects_file_when_creating_project(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
            project_path = Path(tmp) / "not-a-project"
            project_path.write_text("not a directory", encoding="utf-8")

            with self.assertRaises(ValueError):
                state.prepare_workspace(str(project_path), create=True)

    def test_revoked_token_message_is_auth_stale(self):
        message = (
            'Codex usage request failed with HTTP 401: { "error": { "message": '
            '"Encountered invalidated oauth token for user, failing request", '
            '"code": "token_revoked" }, "status": 401 }'
        )

        self.assertTrue(gateway.is_stale_auth_message(message))

    def test_list_threads_prefers_app_server_thread_list(self):
        class FakeClient:
            def start(self):
                return {}

            def thread_list(self, limit=200):
                return {
                    "data": [{
                        "id": "thread-app",
                        "name": "From app server",
                        "preview": "Preview",
                        "cwd": "/tmp/app",
                        "path": "/tmp/app.jsonl",
                        "updatedAt": 30,
                        "createdAt": 20,
                        "source": "vscode",
                        "threadSource": None,
                        "turns": [],
                    }],
                }

        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        state._app_server_client = FakeClient()

        threads = state.list_threads()

        self.assertEqual([thread["id"] for thread in threads], ["thread-app"])
        self.assertEqual(threads[0]["title"], "From app server")

    def test_list_threads_marks_pinned_threads_from_global_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            (codex_home / ".codex-global-state.json").write_text(json.dumps({
                "pinned-thread-ids": ["thread-b"],
            }), encoding="utf-8")

            class FakeClient:
                def start(self):
                    return {}

                def thread_list(self, limit=200):
                    return {
                        "data": [
                            {
                                "id": "thread-a",
                                "name": "Unpinned",
                                "preview": "",
                                "cwd": "/tmp/app",
                                "path": "/tmp/a.jsonl",
                                "updatedAt": 30,
                                "createdAt": 20,
                            },
                            {
                                "id": "thread-b",
                                "name": "Pinned",
                                "preview": "",
                                "cwd": "/tmp/app",
                                "path": "/tmp/b.jsonl",
                                "updatedAt": 20,
                                "createdAt": 10,
                            },
                        ],
                    }

            state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
            state._app_server_client = FakeClient()

            threads = state.list_threads()

            self.assertEqual(
                [(thread["id"], thread["pinned"], thread["pinnedRank"]) for thread in threads],
                [("thread-a", False, None), ("thread-b", True, 0)],
            )

    def test_get_thread_prefers_app_server_thread_read_with_turns(self):
        class FakeClient:
            def start(self):
                return {}

            def thread_read(self, thread_id, include_turns=True):
                return {
                    "thread": {
                        "id": thread_id,
                        "name": "Read from app server",
                        "preview": "Preview",
                        "cwd": "/tmp/app",
                        "path": "/tmp/app.jsonl",
                        "updatedAt": 30,
                        "createdAt": 20,
                        "source": "vscode",
                        "threadSource": None,
                        "turns": [{
                            "id": "turn-1",
                            "startedAt": 100,
                            "items": [{
                                "type": "agentMessage",
                                "id": "agent-1",
                                "text": "Loaded from app-server.",
                                "phase": "final",
                            }],
                        }],
                    },
                }

        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        state._app_server_client = FakeClient()

        thread = state.get_thread("thread-app")

        self.assertEqual(thread["title"], "Read from app server")
        self.assertEqual(thread["messages"][0]["text"], "Loaded from app-server.")

    def test_set_thread_pinned_updates_global_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            codex_home.mkdir()
            (codex_home / ".codex-global-state.json").write_text(json.dumps({
                "pinned-thread-ids": ["thread-a"],
                "project-order": ["/tmp/app"],
            }), encoding="utf-8")
            state = GatewayState(codex_home, "token", Path("/missing-codex"), False)

            state.set_thread_pinned(" thread-b ", True)
            pinned = json.loads((codex_home / ".codex-global-state.json").read_text(encoding="utf-8"))["pinned-thread-ids"]
            self.assertEqual(pinned, ["thread-b", "thread-a"])

            state.set_thread_pinned("thread-a", False)
            payload = json.loads((codex_home / ".codex-global-state.json").read_text(encoding="utf-8"))
            self.assertEqual(payload["pinned-thread-ids"], ["thread-b"])
            self.assertEqual(payload["project-order"], ["/tmp/app"])

    def test_account_statuses_include_profiles_usage_and_active_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Free").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text("{}", encoding="utf-8")
            (accounts_dir / "Free" / "auth.json").write_text("{}", encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Free\n", encoding="utf-8")
            (switcher_home / "usage.json").write_text(json.dumps({
                "Main": {
                    "dailyLimitRemainingPercent": 12,
                    "dailyLimitUsedPercent": 88,
                    "dailyLimitResetsAt": "2026-05-16T23:10:06Z",
                    "weeklyLimitRemainingPercent": 45,
                    "weeklyLimitUsedPercent": 55,
                    "weeklyLimitResetsAt": "2026-05-17T19:42:05Z",
                    "rateLimitResetCreditsRemaining": 3,
                    "lastRateLimitRefreshAt": "2026-05-16T19:18:02Z",
                    "limitHits": 4,
                    "automaticSwitches": 2,
                    "manualSwitches": 1,
                    "authStaleAt": "2026-05-16T18:00:00Z",
                    "authStaleReason": "invalid_token",
                }
            }), encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(tmp_path / "codex", "token", Path("/missing-codex"), False)

                snapshot = state.account_status_snapshot()

                self.assertEqual(snapshot["activeAccount"], "Free")
                statuses = {account["name"]: account for account in snapshot["accounts"]}
                self.assertTrue(statuses["Free"]["isActive"])
                self.assertTrue(statuses["Main"]["authStale"])
                self.assertEqual(statuses["Main"]["fiveHourRemainingPercent"], 12)
                self.assertEqual(statuses["Main"]["weeklyRemainingPercent"], 45)
                self.assertEqual(statuses["Main"]["rateLimitResetCreditsRemaining"], 3)
                self.assertEqual(statuses["Main"]["fiveHourResetsAt"], 1778973006)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_switch_account_persists_refreshed_active_auth_before_installing_next_account(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            codex_home.mkdir()
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Free").mkdir(parents=True)
            active_auth = {
                "last_refresh": "2026-06-24T08:00:00Z",
                "tokens": {"account_id": "main-account", "access_token": "active-refreshed"},
            }
            main_profile_auth = {
                "last_refresh": "2026-06-23T08:00:00Z",
                "tokens": {"account_id": "main-account", "access_token": "old-profile"},
            }
            free_profile_auth = {
                "last_refresh": "2026-06-24T07:00:00Z",
                "tokens": {"account_id": "free-account", "access_token": "free"},
            }
            (codex_home / "auth.json").write_text(json.dumps(active_auth), encoding="utf-8")
            (accounts_dir / "Main" / "auth.json").write_text(json.dumps(main_profile_auth), encoding="utf-8")
            (accounts_dir / "Free" / "auth.json").write_text(json.dumps(free_profile_auth), encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            with gateway.JOBS_LOCK:
                old_jobs = dict(gateway.JOBS)
                gateway.JOBS.clear()
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)

                state.switch_account("Free")

                persisted_main = json.loads((accounts_dir / "Main" / "auth.json").read_text(encoding="utf-8"))
                installed_active = json.loads((codex_home / "auth.json").read_text(encoding="utf-8"))
                self.assertEqual(persisted_main["tokens"]["access_token"], "active-refreshed")
                self.assertEqual(installed_active["tokens"]["access_token"], "free")
            finally:
                with gateway.JOBS_LOCK:
                    gateway.JOBS.clear()
                    gateway.JOBS.update(old_jobs)
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_consume_rate_limit_reset_credit_calls_app_server_and_returns_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"main"}', encoding="utf-8")
            (codex_home / "auth.json").write_text('{"account":"main"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(tmp_path / "codex", "token", Path("/missing-codex"), False)
                client = RecordingRateLimitResetAppServerClient()
                state._app_server_client = client
                state._app_server_auth_fingerprint = state.active_auth_fingerprint()

                with mock.patch("codex_phone_gateway.uuid.uuid4", return_value="reset-id"):
                    snapshot = state.consume_rate_limit_reset_credit()

                self.assertTrue(client.started)
                self.assertEqual(
                    client.requests,
                    [(
                        "account/rateLimitResetCredit/consume",
                        {
                            "creditType": "usage_limit",
                            "idempotencyKey": "codepilot-rate-limit-reset-reset-id",
                        },
                    )],
                )
                self.assertEqual(snapshot["activeAccount"], "Main")
                self.assertEqual(snapshot["rateLimitReset"]["consumed"], True)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_consume_rate_limit_reset_credit_for_named_account_temporarily_switches_and_restores(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Free").mkdir(parents=True)
            main_auth = json.dumps({"tokens": {"account_id": "main", "access_token": "main-token"}})
            free_auth = json.dumps({"tokens": {"account_id": "free", "access_token": "free-token"}})
            (accounts_dir / "Main" / "auth.json").write_text(main_auth, encoding="utf-8")
            (accounts_dir / "Free" / "auth.json").write_text(free_auth, encoding="utf-8")
            (codex_home / "auth.json").write_text(main_auth, encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")
            (switcher_home / "usage.json").write_text(json.dumps({
                "Free": {"rateLimitResetCreditsRemaining": 2}
            }), encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                client = RecordingRateLimitResetAppServerClient()

                with mock.patch("codex_phone_gateway.uuid.uuid4", return_value="reset-id"), \
                        mock.patch.object(state, "app_server_client", return_value=client):
                    snapshot = state.consume_rate_limit_reset_credit("Free")

                self.assertTrue(client.started)
                self.assertEqual(
                    client.requests,
                    [(
                        "account/rateLimitResetCredit/consume",
                        {
                            "creditType": "usage_limit",
                            "idempotencyKey": "codepilot-rate-limit-reset-Free-reset-id",
                        },
                    )],
                )
                self.assertEqual(snapshot["activeAccount"], "Main")
                statuses = {account["name"]: account for account in snapshot["accounts"]}
                self.assertEqual(statuses["Free"]["rateLimitResetCreditsRemaining"], 1)
                self.assertEqual(snapshot["rateLimitReset"]["accountName"], "Free")
                self.assertEqual((switcher_home / "active-account.txt").read_text(encoding="utf-8"), "Main\n")
                self.assertEqual((codex_home / "auth.json").read_text(encoding="utf-8"), main_auth)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_parse_mcp_list_output_marks_reconnectable_auth_states(self):
        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        output = """Name                   Url                                                          Bearer Token Env Var  Status   Auth
cloudflare-api         https://mcp.cloudflare.com/mcp                               -                     enabled  OAuth
home-assistant-remote  https://example.invalid/private-token                   -                     enabled  Not logged in

Name           Command                                                            Args                          Env  Cwd  Status   Auth
node_repl      /Applications/Codex.app/Contents/Resources/cua_node/bin/node_repl  -                             -    -    enabled  Unsupported
"""

        statuses = {item["name"]: item for item in state.parse_mcp_list_output(output)}

        self.assertTrue(statuses["cloudflare-api"]["canReconnect"])
        self.assertFalse(statuses["cloudflare-api"]["needsLogin"])
        self.assertTrue(statuses["home-assistant-remote"]["canReconnect"])
        self.assertTrue(statuses["home-assistant-remote"]["needsLogin"])
        self.assertFalse(statuses["node_repl"]["canReconnect"])

    def test_plugin_statuses_come_from_codex_config_and_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / "codex"
            manifest = codex_home / "plugins" / "cache" / "openai-curated" / "supabase" / "015c0dff" / ".codex-plugin" / "plugin.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({
                "name": "supabase",
                "description": "Supabase plugin",
                "interface": {
                    "displayName": "Supabase",
                    "shortDescription": "Supabase skills and MCP tools",
                },
            }), encoding="utf-8")
            codex_home.mkdir(exist_ok=True)
            (codex_home / "config.toml").write_text(
                '[plugins."supabase@openai-curated"]\n'
                'enabled = true\n'
                '[plugins."documents@openai-primary-runtime"]\n'
                'enabled = false\n',
                encoding="utf-8",
            )
            state = GatewayState(codex_home, "token", Path("/missing-codex"), False)

            statuses = {item["id"]: item for item in state.plugin_statuses()}

            self.assertEqual(statuses["supabase@openai-curated"]["displayName"], "Supabase")
            self.assertTrue(statuses["supabase@openai-curated"]["enabled"])
            self.assertTrue(statuses["supabase@openai-curated"]["installed"])
            self.assertFalse(statuses["documents@openai-primary-runtime"]["enabled"])

    def test_plugin_connectivity_syncs_mobile_config_without_overwriting_desktop(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            mobile_home = switcher_home / "mobile-codex-home"
            codex_home.mkdir(parents=True)
            mobile_home.mkdir(parents=True)
            (codex_home / "config.toml").write_text(
                '[plugins."github@openai-curated"]\n'
                'enabled = false\n'
                '\n'
                '[mcp_servers.cloudflare-api]\n'
                'url = "https://mcp.cloudflare.com/mcp"\n',
                encoding="utf-8",
            )
            (mobile_home / "config.toml").write_text(
                '[plugins."github@openai-curated"]\n'
                'enabled = true\n'
                '\n'
                '[plugins."supabase@openai-curated"]\n'
                'enabled = true\n'
                '\n'
                '[mcp_servers.supabase]\n'
                'url = "https://mcp.supabase.com/mcp?project_ref=test"\n'
                'bearer_token_env_var = "SUPABASE_ACCESS_TOKEN"\n'
                '\n'
                '[mcp_servers.supabase.env]\n'
                'SUPABASE_PROJECT_REF = "test"\n',
                encoding="utf-8",
            )

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)

                status = state.ensure_plugin_connectivity()
                merged = tomllib.loads((codex_home / "config.toml").read_text(encoding="utf-8"))

                self.assertEqual(status["addedPlugins"], ["supabase@openai-curated"])
                self.assertEqual(status["addedMcpServers"], ["supabase"])
                self.assertEqual(status["missingConnectorEnvVars"], ["SUPABASE_ACCESS_TOKEN"])
                self.assertFalse(merged["plugins"]["github@openai-curated"]["enabled"])
                self.assertTrue(merged["plugins"]["supabase@openai-curated"]["enabled"])
                self.assertEqual(merged["mcp_servers"]["cloudflare-api"]["url"], "https://mcp.cloudflare.com/mcp")
                self.assertEqual(merged["mcp_servers"]["supabase"]["bearer_token_env_var"], "SUPABASE_ACCESS_TOKEN")
                self.assertEqual(merged["mcp_servers"]["supabase"]["env"]["SUPABASE_PROJECT_REF"], "test")
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_account_status_snapshot_includes_plugin_sync_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            mobile_home = switcher_home / "mobile-codex-home"
            codex_home.mkdir(parents=True)
            mobile_home.mkdir(parents=True)
            (codex_home / "config.toml").write_text("", encoding="utf-8")
            (mobile_home / "config.toml").write_text(
                '[plugins."supabase@openai-curated"]\n'
                'enabled = true\n'
                '\n'
                '[mcp_servers.supabase]\n'
                'url = "https://mcp.supabase.com/mcp"\n'
                'bearer_token_env_var = "SUPABASE_ACCESS_TOKEN"\n',
                encoding="utf-8",
            )

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)

                snapshot = state.account_status_snapshot()

                self.assertIn("pluginSync", snapshot)
                self.assertEqual(snapshot["pluginSync"]["addedPlugins"], ["supabase@openai-curated"])
                self.assertEqual(snapshot["pluginSync"]["missingConnectorEnvVars"], ["SUPABASE_ACCESS_TOKEN"])
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_connector_auth_warning_is_persisted_for_active_account(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text("{}", encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(tmp_path / "codex", "token", Path("/missing-codex"), False)
                event = gateway.format_non_json_stream_line(
                    "rmcp::transport::worker invalid_token https://mcp.cloudflare.com/mcp",
                    1,
                )

                state.record_connector_auth_warning_event(event)

                usage = json.loads((switcher_home / "usage.json").read_text(encoding="utf-8"))
                warning = usage["Main"]["connectorAuthWarnings"][0]
                self.assertEqual(warning["name"], "cloudflare-api")
                self.assertIn("stale auth", warning["message"])
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_notification_device_registration_persists_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            switcher_home = tmp_path / "switcher"
            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(tmp_path / "codex", "token", Path("/missing-codex"), False)

                response = state.register_notification_device({
                    "token": " ABC123 ",
                    "environment": "production",
                    "bundleId": "io.codepilot.iOS",
                })

                self.assertTrue(response["ok"])
                devices = json.loads((switcher_home / "phone-notification-devices.json").read_text(encoding="utf-8"))
                self.assertEqual(devices[0]["token"], "abc123")
                self.assertEqual(devices[0]["environment"], "production")
                self.assertEqual(devices[0]["bundleId"], "io.codepilot.iOS")
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_live_activity_registration_is_separate_and_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            switcher_home = tmp_path / "switcher"
            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(tmp_path / "codex", "token", Path("/missing-codex"), False)
                payload = {
                    "activityId": "activity-1",
                    "pushToken": " ABC123 ",
                    "environment": "production",
                    "bundleId": "io.codepilot.iOS",
                }

                first = state.register_live_activity(payload)
                second = state.register_live_activity({**payload, "pushToken": "def456"})

                self.assertEqual(first["activityCount"], 1)
                self.assertEqual(second["activityCount"], 1)
                registrations = state.read_live_activities()
                self.assertEqual(registrations[0]["pushToken"], "def456")
                self.assertFalse((switcher_home / "phone-notification-devices.json").exists())
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_live_activity_registration_rejects_invalid_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = tmp_path / "switcher"
            try:
                state = GatewayState(tmp_path / "codex", "token", Path("/missing-codex"), False)
                with self.assertRaisesRegex(ValueError, "environment"):
                    state.register_live_activity({
                        "activityId": "activity-1",
                        "pushToken": "abc123",
                        "environment": "staging",
                    })
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_unchanged_live_activity_state_is_not_pushed_twice(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = tmp_path / "switcher"
            notifier = RecordingPushNotifier()
            try:
                state = GatewayState(
                    tmp_path / "codex",
                    "token",
                    Path("/missing-codex"),
                    False,
                    push_notifier=notifier,
                )
                state.register_live_activity({
                    "activityId": "activity-1",
                    "pushToken": "abc123",
                    "environment": "production",
                    "bundleId": "io.codepilot.iOS",
                })
                snapshot = {
                    "generatedAt": 1_800_000_000,
                    "accounts": [{
                        "authStale": False,
                        "fiveHourRemainingPercent": 68,
                        "fiveHourResetsAt": 1_800_003_600,
                        "fiveHourWindowMins": 300,
                    }],
                }

                state.publish_live_activity_state(snapshot)
                state.publish_live_activity_state(snapshot)

                self.assertEqual(len(notifier.sent), 1)
                registrations, content_state = notifier.sent[0]
                self.assertEqual(registrations[0]["activityId"], "activity-1")
                self.assertEqual(content_state["kind"], "available")
                self.assertEqual(content_state["percent"], 68)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_live_activity_uses_limiting_account_window(self):
        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        now = 1_800_000_000
        weekly_reset = now + 604_800

        content = state.live_activity_content_state({
            "generatedAt": now,
            "accounts": [{
                "name": "Main",
                "fiveHourRemainingPercent": 99,
                "fiveHourResetsAt": now + 3_600,
                "fiveHourWindowMins": 300,
                "weeklyRemainingPercent": 0,
                "weeklyResetsAt": weekly_reset,
                "weeklyWindowMins": 10_080,
                "authStale": False,
            }],
        })

        self.assertEqual(content["kind"], "refilling")
        self.assertIsNone(content["percent"])
        self.assertEqual(content["progress"], 0)
        self.assertEqual(content["usableAccountCount"], 0)
        self.assertEqual(content["nextRefreshAt"], weekly_reset)
        self.assertEqual(content["refreshLabel"], "weekly")

    def test_apns_notifier_uses_certificate_credentials_from_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            cert_path = tmp_path / "apns-cert.pem"
            key_path = tmp_path / "apns-key.pem"
            cert_path.write_text("cert", encoding="utf-8")
            key_path.write_text("key", encoding="utf-8")
            old_env = dict(gateway.os.environ)
            try:
                gateway.os.environ.clear()
                gateway.os.environ.update({
                    "CODEX_PHONE_APNS_CERT_PATH": str(cert_path),
                    "CODEX_PHONE_APNS_CERT_KEY_PATH": str(key_path),
                    "CODEX_PHONE_APNS_TEAM_ID": "ignored-when-cert-is-present",
                    "CODEX_PHONE_APNS_KEY_ID": "ignored-when-cert-is-present",
                    "CODEX_PHONE_APNS_KEY_PATH": "/missing/token-key.p8",
                    "CODEX_PHONE_APNS_TOPIC": "io.codepilot.iOS",
                })

                notifier = gateway.APNsPushNotifier.from_environment()

                self.assertIsInstance(notifier, gateway.APNsCertificatePushNotifier)
                self.assertEqual(notifier.cert_path, cert_path)
                self.assertEqual(notifier.key_path, key_path)
                self.assertEqual(notifier.default_topic, "io.codepilot.iOS")
            finally:
                gateway.os.environ.clear()
                gateway.os.environ.update(old_env)

    def test_apns_live_activity_uses_liveactivity_headers_and_event_payload(self):
        notifier = gateway.APNsPushNotifier("team", "key", Path("/tmp/key.p8"))
        notifier.jwt = lambda: "jwt-token"
        completed = subprocess.CompletedProcess([], 0, stdout=b"{}\n200", stderr=b"")

        with mock.patch.object(gateway.subprocess, "run", return_value=completed) as run:
            invalid = notifier.send_live_activity([{
                "activityId": "activity-1",
                "pushToken": "abc123",
                "environment": "production",
                "bundleId": "io.codepilot.iOS",
            }], {
                "kind": "available",
                "percent": 68,
                "progress": 0.68,
                "generatedAt": 1_800_000_000,
            })

        command = run.call_args.args[0]
        config = run.call_args.kwargs["input"].decode("utf-8")
        self.assertNotIn("jwt-token", command)
        self.assertNotIn("abc123", command)
        self.assertIn('header = "authorization: bearer jwt-token"', config)
        self.assertIn('header = "apns-push-type: liveactivity"', config)
        self.assertIn('header = "apns-topic: io.codepilot.iOS.push-type.liveactivity"', config)
        payload_line = next(line for line in config.splitlines() if line.startswith('data-binary = "'))
        payload_text = payload_line.removeprefix('data-binary = "').removesuffix('"')
        payload = json.loads(payload_text.replace('\\"', '"').replace('\\\\', '\\'))
        self.assertEqual(payload["aps"]["event"], "update")
        self.assertEqual(payload["aps"]["content-state"]["percent"], 68)
        self.assertEqual(invalid, [])

    def test_app_server_turn_completion_sends_registered_push_notification(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            switcher_home = tmp_path / "switcher"
            switcher_home.mkdir()
            (switcher_home / "phone-notification-devices.json").write_text(json.dumps([
                {"token": "abc123", "environment": "production", "bundleId": "io.codepilot.iOS"}
            ]), encoding="utf-8")
            push_notifier = RecordingPushNotifier()

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(
                    tmp_path / "codex",
                    "token",
                    Path("/missing-codex"),
                    False,
                    push_notifier=push_notifier,
                )
                with gateway.JOBS_LOCK:
                    old_jobs = dict(gateway.JOBS)
                    gateway.JOBS.clear()
                    gateway.JOBS["job-1"] = {
                        "id": "job-1",
                        "status": "running",
                        "threadId": "thread-a",
                        "threadTitle": "Main",
                        "events": [],
                    }
                try:
                    state.handle_app_server_notification({
                        "method": "turn/completed",
                        "params": {
                            "thread_id": "thread-a",
                            "turn_id": "turn-a",
                        },
                    })

                    self.assertEqual(len(push_notifier.sent), 1)
                    devices, notification = push_notifier.sent[0]
                    self.assertEqual(devices[0]["token"], "abc123")
                    self.assertEqual(notification["title"], "Codex finished")
                    self.assertEqual(notification["body"], "Open CodePilot to view the result.")
                    self.assertNotIn("Main", json.dumps(notification))
                    self.assertEqual(notification["jobId"], "job-1")
                    public = gateway.public_job(gateway.JOBS["job-1"])
                    self.assertIsInstance(public["completionNotificationSentAt"], int)
                    self.assertNotIn("_pushNotificationSentAt", public)
                finally:
                    with gateway.JOBS_LOCK:
                        gateway.JOBS.clear()
                        gateway.JOBS.update(old_jobs)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_failure_push_excludes_thread_title_and_error_details(self):
        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        notification = state.turn_completion_notification({
            "id": "job-1",
            "threadId": "thread-a",
            "threadTitle": "Private project",
            "status": "failed",
            "error": "credential rejected at a private path",
        })

        self.assertEqual(notification["title"], "Codex failed")
        self.assertEqual(notification["body"], "Open CodePilot to review the error.")
        serialized = json.dumps(notification)
        self.assertNotIn("Private project", serialized)
        self.assertNotIn("credential rejected", serialized)

    def test_completion_push_without_registered_device_does_not_mark_sent(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            switcher_home = tmp_path / "switcher"
            switcher_home.mkdir()
            push_notifier = RecordingPushNotifier()

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(
                    tmp_path / "codex",
                    "token",
                    Path("/missing-codex"),
                    False,
                    push_notifier=push_notifier,
                )
                with gateway.JOBS_LOCK:
                    old_jobs = dict(gateway.JOBS)
                    gateway.JOBS.clear()
                    gateway.JOBS["job-1"] = {
                        "id": "job-1",
                        "status": "completed",
                        "threadId": "thread-a",
                        "threadTitle": "Main",
                        "events": [],
                    }
                    push_job = state.prepare_turn_completion_push_locked(gateway.JOBS["job-1"])
                try:
                    self.assertIsNotNone(push_job)
                    state.send_turn_completion_push(push_job)

                    self.assertEqual(push_notifier.sent, [])
                    self.assertNotIn("_pushNotificationSentAt", gateway.JOBS["job-1"])
                    public = gateway.public_job(gateway.JOBS["job-1"])
                    self.assertNotIn("completionNotificationSentAt", public)
                finally:
                    with gateway.JOBS_LOCK:
                        gateway.JOBS.clear()
                        gateway.JOBS.update(old_jobs)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_switch_account_installs_profile_auth_and_updates_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Free").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"main"}', encoding="utf-8")
            (accounts_dir / "Free" / "auth.json").write_text('{"account":"free"}', encoding="utf-8")
            (codex_home / "auth.json").write_text('{"account":"free"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Free\n", encoding="utf-8")
            (switcher_home / "usage.json").write_text(json.dumps({"Free": {"manualSwitches": 2}}), encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                with gateway.JOBS_LOCK:
                    old_jobs = dict(gateway.JOBS)
                    gateway.JOBS.clear()
                try:
                    snapshot = state.switch_account("Main")
                finally:
                    with gateway.JOBS_LOCK:
                        gateway.JOBS.clear()
                        gateway.JOBS.update(old_jobs)

                self.assertEqual((codex_home / "auth.json").read_text(encoding="utf-8"), '{"account":"main"}')
                self.assertEqual((switcher_home / "active-account.txt").read_text(encoding="utf-8"), "Main\n")
                self.assertEqual(snapshot["activeAccount"], "Main")
                statuses = {account["name"]: account for account in snapshot["accounts"]}
                self.assertTrue(statuses["Main"]["isActive"])
                self.assertEqual(statuses["Main"]["manualSwitches"], 1)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_switch_account_rejects_stale_auth_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Free").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"main"}', encoding="utf-8")
            (accounts_dir / "Free" / "auth.json").write_text('{"account":"free"}', encoding="utf-8")
            (codex_home / "auth.json").write_text('{"account":"main"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")
            (switcher_home / "usage.json").write_text(json.dumps({
                "Free": {
                    "authStaleAt": "2026-05-26T05:13:41Z",
                    "authStaleReason": "Provided authentication token is expired.",
                }
            }), encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                with gateway.JOBS_LOCK:
                    old_jobs = dict(gateway.JOBS)
                    gateway.JOBS.clear()
                try:
                    with self.assertRaisesRegex(RuntimeError, "Free auth is stale"):
                        state.switch_account("Free")
                finally:
                    with gateway.JOBS_LOCK:
                        gateway.JOBS.clear()
                        gateway.JOBS.update(old_jobs)

                self.assertEqual((codex_home / "auth.json").read_text(encoding="utf-8"), '{"account":"main"}')
                self.assertEqual((switcher_home / "active-account.txt").read_text(encoding="utf-8"), "Main\n")
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_switch_account_rejects_running_phone_jobs(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"main"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Free\n", encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                with gateway.JOBS_LOCK:
                    old_jobs = dict(gateway.JOBS)
                    gateway.JOBS.clear()
                    gateway.JOBS["job-running"] = {"id": "job-running", "status": "running", "threadId": "thread-a"}
                try:
                    with self.assertRaisesRegex(RuntimeError, "turn"):
                        state.switch_account("Main")
                finally:
                    with gateway.JOBS_LOCK:
                        gateway.JOBS.clear()
                        gateway.JOBS.update(old_jobs)
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_refresh_account_auth_with_access_token_installs_auth_and_clears_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Free").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            (accounts_dir / "Free" / "auth.json").write_text('{"account":"free"}', encoding="utf-8")
            (codex_home / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")
            (switcher_home / "usage.json").write_text(json.dumps({
                "Main": {
                    "authStaleAt": "2026-05-26T05:13:41Z",
                    "authStaleReason": "Provided authentication token is expired.",
                    "rateLimitError": "Provided authentication token is expired.",
                }
            }), encoding="utf-8")
            login_calls = []

            def fake_login_runner(temp_codex_home, access_token):
                login_calls.append((temp_codex_home, access_token))
                (temp_codex_home / "auth.json").write_text('{"account":"new-main"}', encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            state = None
            started = None
            try:
                state = GatewayState(
                    codex_home,
                    "token",
                    Path("/missing-codex"),
                    False,
                    login_runner=fake_login_runner,
                )
                with gateway.JOBS_LOCK:
                    old_jobs = dict(gateway.JOBS)
                    gateway.JOBS.clear()
                try:
                    snapshot = state.refresh_account_auth_with_access_token("main", " access-token \n")
                finally:
                    with gateway.JOBS_LOCK:
                        gateway.JOBS.clear()
                        gateway.JOBS.update(old_jobs)

                self.assertEqual(len(login_calls), 1)
                self.assertEqual(login_calls[0][1], "access-token")
                self.assertFalse(login_calls[0][0].exists())
                self.assertEqual((accounts_dir / "Main" / "auth.json").read_text(encoding="utf-8"), '{"account":"new-main"}')
                self.assertEqual((codex_home / "auth.json").read_text(encoding="utf-8"), '{"account":"new-main"}')
                usage = json.loads((switcher_home / "usage.json").read_text(encoding="utf-8"))
                self.assertNotIn("authStaleAt", usage["Main"])
                self.assertNotIn("authStaleReason", usage["Main"])
                self.assertNotIn("rateLimitError", usage["Main"])
                self.assertEqual(usage["Main"]["remoteLoginRefreshes"], 1)
                statuses = {account["name"]: account for account in snapshot["accounts"]}
                self.assertFalse(statuses["Main"]["authStale"])
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_refresh_active_account_auth_rejects_running_phone_jobs(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")

            def fake_login_runner(temp_codex_home, access_token):
                (temp_codex_home / "auth.json").write_text('{"account":"new-main"}', encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(
                    codex_home,
                    "token",
                    Path("/missing-codex"),
                    False,
                    login_runner=fake_login_runner,
                )
                with gateway.JOBS_LOCK:
                    old_jobs = dict(gateway.JOBS)
                    gateway.JOBS.clear()
                    gateway.JOBS["job-running"] = {"id": "job-running", "status": "running", "threadId": "thread-a"}
                try:
                    with self.assertRaisesRegex(RuntimeError, "turn"):
                        state.refresh_account_auth_with_access_token("Main", "access-token")
                finally:
                    with gateway.JOBS_LOCK:
                        gateway.JOBS.clear()
                        gateway.JOBS.update(old_jobs)

                self.assertEqual((accounts_dir / "Main" / "auth.json").read_text(encoding="utf-8"), '{"account":"old-main"}')
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_remote_account_login_relays_callback_and_installs_auth(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            (codex_home / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")
            (switcher_home / "usage.json").write_text(json.dumps({
                "Main": {
                    "authStaleAt": "2026-05-26T05:13:41Z",
                    "authStaleReason": "Provided authentication token is expired.",
                    "rateLimitError": "Provided authentication token is expired.",
                }
            }), encoding="utf-8")
            auth_url = (
                "https://auth.openai.com/oauth/authorize?"
                "response_type=code&"
                "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&"
                "state=state-123"
            )
            processes = []
            relayed_urls = []

            def fake_login_process_factory(args, **kwargs):
                process = FakeRemoteLoginProcess(Path(kwargs["env"]["CODEX_HOME"]), auth_url)
                processes.append(process)
                return process

            def fake_callback_relayer(callback_url):
                relayed_urls.append(callback_url)
                processes[0].complete()

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(
                    codex_home,
                    "token",
                    Path("/missing-codex"),
                    False,
                    login_process_factory=fake_login_process_factory,
                    login_callback_relayer=fake_callback_relayer,
                )

                started = state.start_remote_account_login("main")
                snapshot = state.complete_remote_account_login(
                    started["sessionId"],
                    "http://localhost:1455/auth/callback?code=abc&state=state-123",
                )

                self.assertEqual(started["accountName"], "Main")
                self.assertEqual(started["status"], "waiting_for_browser")
                self.assertEqual(started["authUrl"], auth_url)
                self.assertEqual(relayed_urls, ["http://127.0.0.1:1455/auth/callback?code=abc&state=state-123"])
                self.assertTrue(processes[0].completed)
                self.assertFalse(processes[0].codex_home.exists())
                self.assertEqual((accounts_dir / "Main" / "auth.json").read_text(encoding="utf-8"), '{"account":"new-main"}')
                self.assertEqual((codex_home / "auth.json").read_text(encoding="utf-8"), '{"account":"new-main"}')
                usage = json.loads((switcher_home / "usage.json").read_text(encoding="utf-8"))
                self.assertNotIn("authStaleAt", usage["Main"])
                self.assertEqual(usage["Main"]["remoteLoginRefreshes"], 1)
                statuses = {account["name"]: account for account in snapshot["accounts"]}
                self.assertFalse(statuses["Main"]["authStale"])
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_remote_account_login_rejects_mismatched_callback_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            auth_url = (
                "https://auth.openai.com/oauth/authorize?"
                "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&"
                "state=expected-state"
            )
            processes = []
            relayed_urls = []

            def fake_login_process_factory(args, **kwargs):
                process = FakeRemoteLoginProcess(Path(kwargs["env"]["CODEX_HOME"]), auth_url)
                processes.append(process)
                return process

            def fake_callback_relayer(callback_url):
                relayed_urls.append(callback_url)
                processes[0].complete()

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(
                    codex_home,
                    "token",
                    Path("/missing-codex"),
                    False,
                    login_process_factory=fake_login_process_factory,
                    login_callback_relayer=fake_callback_relayer,
                )

                started = state.start_remote_account_login("Main")
                with self.assertRaisesRegex(ValueError, "state"):
                    state.complete_remote_account_login(
                        started["sessionId"],
                        "http://localhost:1455/auth/callback?code=abc&state=wrong-state",
                    )

                self.assertEqual(relayed_urls, [])
                self.assertEqual((accounts_dir / "Main" / "auth.json").read_text(encoding="utf-8"), '{"account":"old-main"}')
            finally:
                if state is not None and started is not None:
                    state.cancel_remote_account_login(started["sessionId"])
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_remote_new_account_login_saves_profile_without_switching(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Main").mkdir(parents=True)
            (accounts_dir / "Main" / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            (codex_home / "auth.json").write_text('{"account":"old-main"}', encoding="utf-8")
            (switcher_home / "active-account.txt").write_text("Main\n", encoding="utf-8")
            auth_url = (
                "https://auth.openai.com/oauth/authorize?"
                "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&"
                "state=state-123"
            )
            processes = []
            relayed_urls = []

            def fake_login_process_factory(args, **kwargs):
                process = FakeRemoteLoginProcess(Path(kwargs["env"]["CODEX_HOME"]), auth_url)
                processes.append(process)
                return process

            def fake_callback_relayer(callback_url):
                relayed_urls.append(callback_url)
                processes[0].complete('{"account":"new-free"}')

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(
                    codex_home,
                    "token",
                    Path("/missing-codex"),
                    False,
                    login_process_factory=fake_login_process_factory,
                    login_callback_relayer=fake_callback_relayer,
                )

                started = state.start_remote_new_account_login(" New/Free:Test ")
                snapshot = state.complete_remote_account_login(
                    started["sessionId"],
                    "http://localhost:1455/auth/callback?code=abc&state=state-123",
                )

                self.assertEqual(started["accountName"], "New-Free-Test")
                self.assertEqual(started["status"], "waiting_for_browser")
                self.assertEqual(relayed_urls, ["http://127.0.0.1:1455/auth/callback?code=abc&state=state-123"])
                self.assertTrue(processes[0].completed)
                self.assertFalse(processes[0].codex_home.exists())
                self.assertEqual((accounts_dir / "New-Free-Test" / "auth.json").read_text(encoding="utf-8"), '{"account":"new-free"}')
                self.assertEqual((codex_home / "auth.json").read_text(encoding="utf-8"), '{"account":"old-main"}')
                self.assertEqual((switcher_home / "active-account.txt").read_text(encoding="utf-8"), "Main\n")
                self.assertEqual(snapshot["activeAccount"], "Main")
                statuses = {account["name"]: account for account in snapshot["accounts"]}
                self.assertIn("New-Free-Test", statuses)
                self.assertFalse(statuses["New-Free-Test"]["authStale"])
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_remote_new_account_login_rejects_duplicate_profile_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            switcher_home = tmp_path / "switcher"
            accounts_dir = switcher_home / "accounts"
            codex_home.mkdir()
            (accounts_dir / "Free").mkdir(parents=True)
            (accounts_dir / "Free" / "auth.json").write_text('{"account":"free"}', encoding="utf-8")

            old_home = gateway.DEFAULT_SWITCHER_HOME
            gateway.DEFAULT_SWITCHER_HOME = switcher_home
            try:
                state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
                with self.assertRaisesRegex(ValueError, "already exists"):
                    state.start_remote_new_account_login("free")
            finally:
                gateway.DEFAULT_SWITCHER_HOME = old_home

    def test_start_new_thread_uses_selected_workspace_without_resume(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            workspace = tmp_path / "workspace"
            codex_home.mkdir()
            workspace.mkdir()
            state = GatewayState(codex_home, "token", Path("/missing-codex"), False)
            captured = {}

            old_run_turn = GatewayState.run_turn

            def fake_run_turn(self, job_id, thread, prompt, attachments, resume_existing=True):
                captured["job_id"] = job_id
                captured["thread"] = thread
                captured["prompt"] = prompt
                captured["attachments"] = attachments
                captured["resume_existing"] = resume_existing

            GatewayState.run_turn = fake_run_turn
            try:
                job = state.start_new_thread(str(workspace), "Start a new task")

                self.assertEqual(job["threadId"], "")
                expected_workspace = str(workspace.resolve())
                self.assertEqual(job["cwd"], expected_workspace)
                self.assertEqual(captured["thread"]["cwd"], expected_workspace)
                self.assertFalse(captured["resume_existing"])
                self.assertEqual(captured["prompt"], "Start a new task")
            finally:
                GatewayState.run_turn = old_run_turn

    def test_start_turn_rejects_second_running_turn_in_same_thread(self):
        old_jobs = {}
        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS["running"] = {
                "id": "running",
                "threadId": "thread-a",
                "status": "running",
                "updatedAt": 1,
            }

        old_run_turn = GatewayState.run_turn
        GatewayState.run_turn = lambda self, job_id, thread, prompt, attachments, resume_existing=True, reasoning_effort=None: None
        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            state.get_thread = lambda thread_id: {
                "id": thread_id,
                "cwd": "/tmp/workspace",
                "rolloutPath": "/tmp/rollout.jsonl",
            }

            with self.assertRaisesRegex(RuntimeError, "This thread already has a running Codex turn"):
                state.start_turn("thread-a", "Continue")
        finally:
            GatewayState.run_turn = old_run_turn
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_start_turn_allows_running_turn_in_different_thread(self):
        old_jobs = {}
        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS["running"] = {
                "id": "running",
                "threadId": "thread-a",
                "status": "running",
                "updatedAt": 1,
            }

        old_run_turn = GatewayState.run_turn
        GatewayState.run_turn = lambda self, job_id, thread, prompt, attachments, resume_existing=True, reasoning_effort=None: None
        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            state.get_thread = lambda thread_id: {
                "id": thread_id,
                "cwd": "/tmp/workspace",
                "rolloutPath": "/tmp/rollout.jsonl",
            }

            job = state.start_turn("thread-b", "Start parallel work")

            self.assertEqual(job["threadId"], "thread-b")
            self.assertEqual(job["status"], "running")
        finally:
            GatewayState.run_turn = old_run_turn
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_start_turn_passes_reasoning_effort_to_runner(self):
        old_jobs = {}
        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()

        captured = {}
        old_run_turn = GatewayState.run_turn

        def fake_run_turn(self, job_id, thread, prompt, attachments, resume_existing=True, reasoning_effort=None):
            captured["reasoning_effort"] = reasoning_effort

        GatewayState.run_turn = fake_run_turn
        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            state.get_thread = lambda thread_id: {
                "id": thread_id,
                "cwd": "/tmp/workspace",
                "rolloutPath": "/tmp/rollout.jsonl",
            }

            job = state.start_turn("thread-b", "Start parallel work", reasoning_effort="high")

            self.assertEqual(job["reasoningEffort"], "medium")
            self.assertEqual(captured["reasoning_effort"], "medium")
        finally:
            GatewayState.run_turn = old_run_turn
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_start_turn_rejects_invalid_reasoning_effort(self):
        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        state.get_thread = lambda thread_id: {
            "id": thread_id,
            "cwd": "/tmp/workspace",
            "rolloutPath": "/tmp/rollout.jsonl",
        }

        with self.assertRaisesRegex(ValueError, "Reasoning effort"):
            state.start_turn("thread-b", "Start parallel work", reasoning_effort="extreme")

    def test_updates_new_thread_job_when_thread_started_event_arrives(self):
        job = {"threadId": ""}
        event = {
            "id": "thread.started",
            "kind": "context",
            "status": "completed",
            "title": "Thread resumed",
            "body": "019e2d2b-cec3-7f91-bc01-ec4401121c07",
            "timestamp": 1,
            "rawType": "thread.started",
        }

        gateway.update_job_thread_id(job, event)

        self.assertEqual(job["threadId"], "019e2d2b-cec3-7f91-bc01-ec4401121c07")

    def test_app_server_status_initializes_lazy_client_with_codex_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            codex_home = tmp_path / "codex"
            workspace = tmp_path / "workspace"
            codex_home.mkdir()
            workspace.mkdir()
            process = FakeAppServerProcess([
                json.dumps({"id": "init-id", "result": {
                    "userAgent": "ua",
                    "codexHome": str(codex_home),
                    "platformFamily": "unix",
                    "platformOs": "macos",
                }}) + "\n",
            ])
            calls = []

            def fake_process_factory(args, **kwargs):
                calls.append((args, kwargs))
                return process

            state = GatewayState(
                codex_home,
                "token",
                Path("/usr/local/bin/codex"),
                False,
                app_server_cwd=workspace,
                app_server_process_factory=fake_process_factory,
                app_server_id_factory=lambda: "init-id",
            )

            status = state.app_server_status()

            self.assertTrue(status["ok"])
            self.assertEqual(status["response"]["platformOs"], "macos")
            self.assertEqual(calls[0][1]["env"]["CODEX_HOME"], str(codex_home))

    def test_active_job_for_thread_returns_latest_running_job(self):
        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS.update({
                "old": {
                    "id": "old",
                    "threadId": "thread-a",
                    "status": "completed",
                    "updatedAt": 10,
                },
                "other": {
                    "id": "other",
                    "threadId": "thread-b",
                    "status": "running",
                    "updatedAt": 30,
                },
                "new": {
                    "id": "new",
                    "threadId": "thread-a",
                    "status": "running",
                    "updatedAt": 20,
                },
            })

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)

            job = state.active_job_for_thread("thread-a")

            self.assertEqual(job["id"], "new")
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_active_jobs_returns_all_running_jobs(self):
        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS.update({
                "running-a": {
                    "id": "running-a",
                    "threadId": "thread-a",
                    "status": "running",
                    "updatedAt": 20,
                },
                "completed": {
                    "id": "completed",
                    "threadId": "thread-b",
                    "status": "completed",
                    "updatedAt": 30,
                },
                "running-b": {
                    "id": "running-b",
                    "threadId": "thread-c",
                    "status": "running",
                    "updatedAt": 10,
                },
            })

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)

            jobs = state.active_jobs()

            self.assertEqual([job["id"] for job in jobs], ["running-a", "running-b"])
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_public_job_strips_internal_fields_and_compacts_large_payloads(self):
        long_text = "x" * 20_000
        job = {
            "id": "job-1",
            "threadId": "thread-a",
            "status": "running",
            "output": long_text,
            "lastMessage": long_text,
            "_messageBodies": {"message-a": long_text},
            "_eventSeq": 2,
            "events": [
                {"id": "event-1", "body": long_text, "eventSeq": 1},
                {"id": "event-2", "body": "short", "eventSeq": 2},
            ],
        }

        public = gateway.public_job(job)

        self.assertNotIn("_messageBodies", public)
        self.assertNotIn("_eventSeq", public)
        self.assertLess(len(public["output"]), 5_000)
        self.assertLess(len(public["lastMessage"]), 5_000)
        self.assertLess(len(public["events"][0]["body"]), 13_000)
        self.assertEqual(job["lastMessage"], long_text)

    def test_public_job_can_return_only_events_after_cursor(self):
        job = {
            "id": "job-1",
            "threadId": "thread-a",
            "status": "running",
            "events": [
                {"id": "event-1", "body": "old", "eventSeq": 1},
                {"id": "event-2", "body": "new", "eventSeq": 2},
            ],
        }

        public = gateway.public_job(job, after_event_seq=1)

        self.assertEqual([event["id"] for event in public["events"]], ["event-2"])

    def test_run_turn_falls_back_to_cli_when_app_server_loses_existing_thread(self):
        calls = []

        class FakeClient:
            def start(self):
                calls.append(("start",))

            def thread_resume(self, thread_id):
                calls.append(("resume", thread_id))
                raise RuntimeError("thread not found: thread-a")

            def turn_start(self, thread_id, prompt):
                calls.append(("turn_start", thread_id, prompt))

            def close(self):
                calls.append(("close",))

        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS["job-1"] = {
                "id": "job-1",
                "threadId": "thread-a",
                "status": "running",
                "updatedAt": 1,
                "events": [],
            }

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            state._app_server_client = FakeClient()

            def fake_run_turn_exec(job_id, thread, prompt, attachments, resume_existing=True):
                calls.append(("exec", job_id, thread["id"], prompt, resume_existing))

            state.run_turn_exec = fake_run_turn_exec
            state.run_turn("job-1", {"id": "thread-a", "cwd": "/tmp/workspace"}, "Continue", [], True)

            self.assertEqual(calls, [
                ("start",),
                ("resume", "thread-a"),
                ("close",),
                ("exec", "job-1", "thread-a", "Continue", True),
            ])
            self.assertEqual(gateway.JOBS["job-1"]["status"], "running")
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_existing_turn_resumes_thread_before_starting_turn(self):
        calls = []

        class FakeClient:
            def start(self):
                calls.append(("start",))

            def thread_resume(self, thread_id):
                calls.append(("resume", thread_id))
                return {"thread": {"id": thread_id}}

            def turn_start(self, thread_id, prompt):
                calls.append(("turn_start", thread_id, prompt))
                with gateway.JOBS_LOCK:
                    gateway.JOBS["job-1"]["status"] = "completed"
                return {"turn": {"id": "turn-1"}}

        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS["job-1"] = {
                "id": "job-1",
                "threadId": "thread-a",
                "status": "running",
                "updatedAt": 1,
                "events": [],
            }

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            state._app_server_client = FakeClient()

            did_handle = state.run_turn_app_server("job-1", {"id": "thread-a", "cwd": "/tmp/workspace"}, "Continue", True)

            self.assertTrue(did_handle)
            self.assertEqual(calls, [
                ("start",),
                ("resume", "thread-a"),
                ("turn_start", "thread-a", "Continue"),
            ])
            self.assertEqual(gateway.JOBS["job-1"]["turnId"], "turn-1")
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_rename_and_archive_thread_validate_input_and_delegate_to_app_server(self):
        calls = []

        class FakeClient:
            def start(self):
                calls.append(("start", None))

            def thread_set_name(self, thread_id, name):
                calls.append(("rename", thread_id, name))

            def thread_archive(self, thread_id):
                calls.append(("archive", thread_id))

        state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
        state._app_server_client = FakeClient()

        state.rename_thread(" thread-a ", "  Better title  ")
        state.archive_thread(" thread-a ")

        self.assertEqual(calls, [
            ("start", None),
            ("rename", "thread-a", "Better title"),
            ("start", None),
            ("archive", "thread-a"),
        ])
        with self.assertRaises(ValueError):
            state.rename_thread("thread-a", " ")
        with self.assertRaises(ValueError):
            state.archive_thread(" ")

    def test_steer_turn_delegates_to_app_server_for_running_job(self):
        calls = []

        class FakeClient:
            def start(self):
                calls.append(("start", None))

            def turn_steer(self, thread_id, turn_id, text):
                calls.append(("steer", thread_id, turn_id, text))
                return {}

        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS["job-1"] = {
                "id": "job-1",
                "threadId": "thread-a",
                "turnId": "turn-1",
                "status": "running",
                "updatedAt": 1,
                "events": [],
            }

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            state._app_server_client = FakeClient()

            job = state.steer_turn("thread-a", "job-1", "Focus on the failing test.")

            self.assertEqual(job["id"], "job-1")
            self.assertEqual(calls, [
                ("start", None),
                ("steer", "thread-a", "turn-1", "Focus on the failing test."),
            ])
            self.assertEqual(job["events"][-1]["title"], "Steer sent")
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_steer_turn_requires_running_job_with_turn_id(self):
        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS["job-1"] = {
                "id": "job-1",
                "threadId": "thread-a",
                "status": "running",
                "updatedAt": 1,
                "events": [],
            }

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)

            with self.assertRaisesRegex(RuntimeError, "does not support steering yet"):
                state.steer_turn("thread-a", "job-1", "Focus")
            with self.assertRaisesRegex(ValueError, "Steer text is empty"):
                state.steer_turn("thread-a", "job-1", " ")
            with self.assertRaisesRegex(LookupError, "Job not found"):
                state.steer_turn("thread-a", "missing", "Focus")
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)

    def test_stop_turn_terminates_cli_process_and_marks_job_canceled(self):
        class FakeProcess:
            def __init__(self):
                self.terminated = False

            def poll(self):
                return None

            def terminate(self):
                self.terminated = True

        process = FakeProcess()
        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            old_processes = dict(gateway.JOB_PROCESSES)
            gateway.JOBS.clear()
            gateway.JOB_PROCESSES.clear()
            gateway.JOBS["job-1"] = {
                "id": "job-1",
                "threadId": "thread-a",
                "status": "running",
                "updatedAt": 1,
                "events": [],
            }
            gateway.JOB_PROCESSES["job-1"] = process

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)

            job = state.stop_turn("thread-a", "job-1")

            self.assertTrue(process.terminated)
            self.assertEqual(job["status"], "canceled")
            self.assertEqual(job["events"][-1]["title"], "Turn stopped")
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)
                gateway.JOB_PROCESSES.clear()
                gateway.JOB_PROCESSES.update(old_processes)

    def test_stop_turn_interrupts_app_server_turn(self):
        calls = []

        class FakeClient:
            def start(self):
                calls.append(("start",))

            def turn_interrupt(self, thread_id, turn_id):
                calls.append(("interrupt", thread_id, turn_id))

        with gateway.JOBS_LOCK:
            old_jobs = dict(gateway.JOBS)
            gateway.JOBS.clear()
            gateway.JOBS["job-1"] = {
                "id": "job-1",
                "threadId": "thread-a",
                "turnId": "turn-1",
                "status": "running",
                "updatedAt": 1,
                "events": [],
            }

        try:
            state = GatewayState(Path("/tmp/codex"), "token", Path("/missing-codex"), False)
            state._app_server_client = FakeClient()

            job = state.stop_turn("thread-a", "job-1")

            self.assertEqual(calls, [("start",), ("interrupt", "thread-a", "turn-1")])
            self.assertEqual(job["status"], "canceled")
        finally:
            with gateway.JOBS_LOCK:
                gateway.JOBS.clear()
                gateway.JOBS.update(old_jobs)


if __name__ == "__main__":
    unittest.main()
