"""The boot smoke result is evaluated once per boot and republished afterwards.

The boot run gets one attempt at hawkBit. When it fails, the hourly resync has
to carry the same result, or hawkBit keeps the one of an earlier boot.
"""

import importlib.machinery
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SMOKE_REPORT = REPO_ROOT / "scripts" / "meticulous-smoke-report"

BOOT_ATTRIBUTES = {
    "boot_smoke_status": "pass",
    "boot_smoke_at": "2026-11-12T08:00:00+00:00",
    "boot_smoke_version": "2026M1530-nightly",
    "boot_smoke_failed_checks": "",
}


def load_smoke_report():
    loader = importlib.machinery.SourceFileLoader(
        "meticulous_smoke_report_boot_resync_test", str(SMOKE_REPORT)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class BootAttributeResyncTests(unittest.TestCase):
    def setUp(self):
        self.reporter = load_smoke_report()
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        self.cache = Path(temp_dir.name) / "boot-smoke-attributes.json"
        self.reporter.BOOT_ATTRIBUTE_CACHE = self.cache
        self.boot_checks = mock.Mock(return_value=dict(BOOT_ATTRIBUTES))
        self.reporter.make_boot_attributes = self.boot_checks
        self.reporter.make_device_attributes = lambda: {"attribute_reporter": "push-v1"}
        self.reporter.make_shot_attributes = lambda: {}
        self.published = []
        self.reporter.publish_attributes = self.published.append

    def run_report(self, *arguments):
        with mock.patch.object(sys, "argv", ["meticulous-smoke-report", *arguments]):
            with mock.patch("builtins.print"):
                return self.reporter.main()

    def test_the_boot_run_keeps_its_result_even_when_the_publish_fails(self):
        self.reporter.publish_attributes = mock.Mock(side_effect=OSError("no network"))

        self.assertEqual(self.run_report("--boot"), 1)

        self.assertEqual(json.loads(self.cache.read_text()), BOOT_ATTRIBUTES)

    def test_the_resync_sends_the_boot_result_without_running_the_checks(self):
        self.cache.write_text(json.dumps(BOOT_ATTRIBUTES))

        self.assertEqual(self.run_report("--attributes"), 0)

        self.boot_checks.assert_not_called()
        self.assertEqual(
            self.published, [dict(BOOT_ATTRIBUTES, attribute_reporter="push-v1")]
        )

    def test_the_shot_publish_sends_the_boot_result_too(self):
        self.cache.write_text(json.dumps(BOOT_ATTRIBUTES))

        self.assertEqual(self.run_report("--shot"), 0)

        self.boot_checks.assert_not_called()
        self.assertEqual(self.published[0]["boot_smoke_version"], "2026M1530-nightly")

    def test_the_resync_sends_no_boot_result_before_the_checks_finished(self):
        self.assertEqual(self.run_report("--attributes"), 0)

        self.assertEqual(self.published, [{"attribute_reporter": "push-v1"}])

    def test_the_resync_ignores_an_unreadable_boot_result(self):
        self.cache.write_text("{not json")

        self.assertEqual(self.run_report("--attributes"), 0)

        self.assertEqual(self.published, [{"attribute_reporter": "push-v1"}])


if __name__ == "__main__":
    unittest.main()
