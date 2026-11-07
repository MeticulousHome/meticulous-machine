"""The smoke report's Sentry alert for a Dial that does not reach its home screen.

meticulous-smoke-report runs on /opt/meticulous-venv/bin/python3, which is the
image's own python3 on images with the Rust backend: nothing beyond the
standard library is there, and the alert once died on `import sentry_sdk` on
every such machine. e2e/image/check_image.py checks the same on a built image.
"""

import ast
import http.server
import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SMOKE_REPORT = REPO_ROOT / "scripts" / "meticulous-smoke-report"

FAILED_CHECKS = {
    "backend_service": True,
    "dial_service": True,
    "dial_ready": True,
    "dial_home_ready": False,
    "backend_initialized": True,
    "esp32_responding": True,
}
ATTRIBUTES = {
    "boot_smoke_version": "2026M1530-nightly",
    "boot_smoke_failed_checks": "dial_home_ready",
}
MACHINE_INFO = {"serial": "000109", "hostname": "meticulous-test", "identity_source": "backend_api"}


def load_smoke_report():
    loader = importlib.machinery.SourceFileLoader(
        "meticulous_smoke_report_sentry_test", str(SMOKE_REPORT)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class StandInSentry:
    """Answers envelopes on 127.0.0.1 with the status set per project."""

    def __init__(self):
        self.received = []
        self.status = {}
        stand_in = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                project = self.path.split("/")[2]
                stand_in.received.append(
                    {"project": project, "path": self.path, "headers": dict(self.headers), "body": body}
                )
                self.send_response(stand_in.status.get(project, 200))
                self.end_headers()
                self.wfile.write(b"{}")

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def dsn(self, project, prefix=""):
        return f"http://public{project}@127.0.0.1:{self.server.server_address[1]}{prefix}/{project}"

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def imported_top_level_modules(path):
    modules = set()
    for node in ast.walk(ast.parse(path.read_text(), str(path))):
        if isinstance(node, ast.Import):
            modules.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            modules.add(node.module.split(".")[0])
    return modules


class StandardLibraryOnlyTests(unittest.TestCase):
    def test_smoke_report_imports_only_the_standard_library(self):
        # Also the imports inside functions: they fail only on the path that
        # runs them, which for the Sentry alert is a boot that already failed.
        outside = imported_top_level_modules(SMOKE_REPORT) - sys.stdlib_module_names
        self.assertEqual(sorted(outside), [])


class DialBootFailureSentryTests(unittest.TestCase):
    def setUp(self):
        self.reporter = load_smoke_report()
        self.sentry = StandInSentry()
        self.addCleanup(self.sentry.close)
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        self.marker = Path(temp_dir.name) / "reported"
        self.reporter.SENTRY_DIAL_BOOT_FAILURE_MARKER = self.marker
        self.reporter.read_machine_info = lambda: dict(MACHINE_INFO)
        environment = mock.patch.dict(
            os.environ,
            {
                "METICULOUS_SMOKE_SENTRY_DSN": self.sentry.dsn("1"),
                "METICULOUS_SMOKE_SELF_HOSTED_SENTRY_DSN": self.sentry.dsn("8"),
            },
        )
        environment.start()
        self.addCleanup(environment.stop)

    def report(self):
        self.reporter.report_dial_boot_failure_to_sentry(FAILED_CHECKS, {}, ATTRIBUTES)

    def envelope(self, request):
        header, item, payload = request["body"].decode("utf-8").rstrip("\n").split("\n")
        return json.loads(header), json.loads(item), json.loads(payload)

    def test_both_sentries_get_the_same_event_as_an_envelope(self):
        self.report()

        self.assertEqual(sorted(r["project"] for r in self.sentry.received), ["1", "8"])
        events = []
        for request in self.sentry.received:
            self.assertEqual(request["path"], f"/api/{request['project']}/envelope/")
            self.assertEqual(request["headers"]["Content-Type"], "application/x-sentry-envelope")
            self.assertIn(f"sentry_key=public{request['project']}", request["headers"]["X-Sentry-Auth"])
            header, item, event = self.envelope(request)
            self.assertEqual(item["type"], "event")
            self.assertEqual(item["length"], len(json.dumps(event).encode("utf-8")))
            self.assertEqual(header["event_id"], event["event_id"])
            events.append(event)
        self.assertEqual(events[0]["event_id"], events[1]["event_id"])

        event = events[0]
        self.assertEqual(
            event["message"]["formatted"],
            "Dial did not reach ready state during boot smoke validation",
        )
        self.assertEqual(event["level"], "error")
        self.assertEqual(
            event["fingerprint"], ["meticulous-smoke-report", "dial-boot-readiness-timeout"]
        )
        self.assertEqual(event["tags"]["dial_home_ready"], "false")
        self.assertEqual(event["tags"]["serial"], "000109")
        self.assertEqual(event["tags"]["image_version"], "2026M1530-nightly")
        self.assertEqual(event["extra"]["failed_dial_checks"], ["dial_home_ready"])
        self.assertEqual(event["contexts"]["boot-checks"], FAILED_CHECKS)
        self.assertEqual(
            self.marker.read_text(),
            f"sentry: {event['event_id']}\nself_hosted_sentry: {event['event_id']}\n",
        )

    def test_a_sentry_that_refuses_does_not_keep_the_event_from_the_other(self):
        self.sentry.status["1"] = 500

        self.report()

        self.assertEqual(sorted(r["project"] for r in self.sentry.received), ["1", "8"])
        self.assertRegex(self.marker.read_text(), r"^self_hosted_sentry: [0-9a-f]{32}\n$")

    def test_no_marker_when_no_sentry_accepts_the_event(self):
        self.sentry.status.update({"1": 403, "8": 500})

        self.report()

        self.assertEqual(len(self.sentry.received), 2)
        self.assertFalse(self.marker.exists())

    def test_nothing_is_sent_again_once_this_boot_was_reported(self):
        self.marker.write_text("sentry: earlier\n")

        self.report()

        self.assertEqual(self.sentry.received, [])

    def test_an_empty_dsn_turns_that_sentry_off(self):
        with mock.patch.dict(os.environ, {"METICULOUS_SMOKE_SELF_HOSTED_SENTRY_DSN": ""}):
            self.report()

        self.assertEqual([r["project"] for r in self.sentry.received], ["1"])

    def test_a_passing_dial_sends_nothing(self):
        self.reporter.report_dial_boot_failure_to_sentry(
            dict(FAILED_CHECKS, dial_home_ready=True), {}, ATTRIBUTES
        )

        self.assertEqual(self.sentry.received, [])

    def test_dsn_with_a_port_and_a_path(self):
        self.assertEqual(
            self.reporter.sentry_envelope_url("https://key@sentry.example.com:9000/sub/path/42"),
            ("https://sentry.example.com:9000/sub/path/api/42/envelope/", "key"),
        )
        with self.assertRaises(ValueError):
            self.reporter.sentry_envelope_url("sentry.example.com/42")


if __name__ == "__main__":
    unittest.main()
