"""Regression tests for concurrent Hawkbit config publication and reads."""

import fcntl
import importlib.machinery
import importlib.util
import os
import stat
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_WRITER = REPO_ROOT / "config" / "etc" / "hawkbit" / "config_writer.sh"
SMOKE_REPORT = REPO_ROOT / "scripts" / "meticulous-smoke-report"

OLD_CONFIG = """[client]
hawkbit_server = old.example.com
target_name = old-target
gateway_token = old-token
"""
TEMPLATE = """[client]
hawkbit_server = hawkbit.example.com
target_name = __TARGET_NAME__
gateway_token = __GATEWAY_TOKEN__
"""
NEW_CONFIG = """[client]
hawkbit_server = hawkbit.example.com
target_name = new-target
gateway_token = new-token
"""


def load_smoke_report():
    loader = importlib.machinery.SourceFileLoader(
        "meticulous_smoke_report_test", str(SMOKE_REPORT)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class AtomicConfigPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.config = self.root / "config.conf"
        self.template = self.root / "config.conf.template"
        self.config.write_text(OLD_CONFIG, encoding="utf-8")
        self.template.write_text(TEMPLATE, encoding="utf-8")

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_interactive_writer(self, body):
        process = subprocess.Popen(
            [
                "bash",
                "-c",
                body,
                "bash",
                str(CONFIG_WRITER),
                str(self.template),
                str(self.config),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(self.close_process, process)
        return process

    def close_process(self, process):
        if process.poll() is None:
            process.kill()
            process.wait()
        process.stdin.close()
        process.stdout.close()
        process.stderr.close()

    def wait_for_writer(self, process, expected_marker):
        marker = process.stdout.readline().strip()
        self.assertEqual(marker, expected_marker)

    def advance_writer(self, process):
        process.stdin.write("continue\n")
        process.stdin.flush()

    def test_old_in_place_render_exposes_the_template_to_readers(self):
        process = self.run_interactive_writer(
            r"""
            template=$2
            destination=$3
            cp "$template" "$destination"
            echo copied
            read -r _
            sed -i.bak 's/__TARGET_NAME__/new-target/' "$destination"
            rm -f "${destination}.bak"
            echo target-rendered
            read -r _
            sed -i.bak 's/__GATEWAY_TOKEN__/new-token/' "$destination"
            rm -f "${destination}.bak"
            """
        )

        self.wait_for_writer(process, "copied")
        self.assertEqual(self.config.read_text(encoding="utf-8"), TEMPLATE)
        self.advance_writer(process)
        self.wait_for_writer(process, "target-rendered")
        self.assertIn("gateway_token = __GATEWAY_TOKEN__", self.config.read_text())
        self.advance_writer(process)
        self.assertEqual(process.wait(timeout=5), 0, process.stderr.read())

    def test_atomic_writer_exposes_only_complete_old_or_new_config(self):
        original_stat = self.config.stat()
        os.chmod(self.config, 0o640)
        process = self.run_interactive_writer(
            r"""
            source "$1"
            template=$2
            destination=$3
            work_file=$(create_hawkbit_config_work_file "$destination" "$template")
            echo prepared
            read -r _
            sed -i.bak 's/__TARGET_NAME__/new-target/' "$work_file"
            rm -f "${work_file}.bak"
            echo target-rendered
            read -r _
            sed -i.bak 's/__GATEWAY_TOKEN__/new-token/' "$work_file"
            rm -f "${work_file}.bak"
            echo fully-rendered
            read -r _
            publish_hawkbit_config "$work_file" "$destination"
            """
        )

        for marker in ("prepared", "target-rendered", "fully-rendered"):
            self.wait_for_writer(process, marker)
            self.assertEqual(self.config.read_text(encoding="utf-8"), OLD_CONFIG)
            self.advance_writer(process)

        self.assertEqual(process.wait(timeout=5), 0, process.stderr.read())
        self.assertEqual(self.config.read_text(encoding="utf-8"), NEW_CONFIG)

        published_stat = self.config.stat()
        self.assertEqual(stat.S_IMODE(published_stat.st_mode), 0o640)
        self.assertEqual(published_stat.st_uid, original_stat.st_uid)
        self.assertEqual(published_stat.st_gid, original_stat.st_gid)
        self.assertFalse(list(self.root.glob(".config.conf.*")))

    def test_atomic_writer_refuses_to_publish_an_incomplete_render(self):
        result = subprocess.run(
            [
                "bash",
                "-c",
                r"""
                source "$1"
                work_file=$(create_hawkbit_config_work_file "$3" "$2")
                sed -i.bak 's/__TARGET_NAME__/new-target/' "$work_file"
                rm -f "${work_file}.bak"
                publish_hawkbit_config "$work_file" "$3"
                """,
                "bash",
                str(CONFIG_WRITER),
                str(self.template),
                str(self.config),
            ],
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unresolved placeholders", result.stderr)
        self.assertEqual(self.config.read_text(encoding="utf-8"), OLD_CONFIG)


class SmokeReportConfigReadTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.config = self.root / "config.conf"
        self.cache = self.root / "attributes.json"
        self.lock = self.root / "config.lock"
        self.generator = self.root / "missing-generator"
        self.cache.write_text("{}\n", encoding="utf-8")
        self.reporter = load_smoke_report()
        self.reporter.HAWKBIT_CONFIG = self.config
        self.reporter.HAWKBIT_ATTRIBUTE_CACHE = self.cache
        self.reporter.HAWKBIT_CONFIG_LOCK = self.lock
        self.reporter.HAWKBIT_CONFIG_GENERATOR = self.generator

    def tearDown(self):
        self.temp_dir.cleanup()

    def write_config(self, target, gateway_token="token"):
        self.config.write_text(
            "[client]\n"
            "hawkbit_server = hawkbit.example.com\n"
            f"target_name = {target}\n"
            f"gateway_token = {gateway_token}\n",
            encoding="utf-8",
        )

    def test_reader_waits_for_concurrent_writer_and_loads_published_config(self):
        self.write_config("old-target")
        result = []
        finished = threading.Event()

        with self.lock.open("a", encoding="utf-8") as lock_file:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            thread = threading.Thread(
                target=lambda: (
                    result.append(self.reporter.load_hawkbit_config()),
                    finished.set(),
                )
            )
            thread.start()
            self.assertFalse(finished.wait(timeout=0.1))

            replacement = self.root / ".config.conf.new"
            replacement.write_text(
                "[client]\n"
                "hawkbit_server = hawkbit.example.com\n"
                "target_name = new-target\n"
                "gateway_token = token\n",
                encoding="utf-8",
            )
            replacement.replace(self.config)
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

        thread.join(timeout=5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(result[0][3], "new-target")

    def test_reader_rejects_an_unresolved_target_placeholder(self):
        self.write_config("__TARGET_NAME__")

        with self.assertRaisesRegex(RuntimeError, "unresolved client placeholder"):
            self.reporter.load_hawkbit_config()

    def test_reader_accepts_double_underscores_outside_placeholder_syntax(self):
        self.write_config("valid-target", gateway_token="token__suffix")

        config = self.reporter.load_hawkbit_config()

        self.assertEqual(config[3], "valid-target")
        self.assertEqual(config[6], "token__suffix")


if __name__ == "__main__":
    unittest.main()
