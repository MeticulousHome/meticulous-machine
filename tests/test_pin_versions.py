import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


REQUIRED_COMPONENTS = [
    ("LINUX", "linux"),
    ("UBOOT", "uboot"),
    ("ATF", "atf"),
    ("IMX_MKIMAGE", "imx-mkimage"),
    ("DEBIAN", "debian"),
    ("BACKEND", "backend"),
    ("DIAL", "dial"),
    ("WEB_APP", "web-app"),
    ("WATCHER", "watcher"),
    ("FIRMWARE", "firmware"),
    ("RAUC", "rauc"),
    ("HAWKBIT", "hawkbit"),
    ("PSPLASH", "psplash"),
    ("CRASH_REPORTER", "crash-reporter"),
]


def run(cmd, cwd):
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=True,
    )


def create_component_repo(path, name):
    path.mkdir(parents=True)
    run(["git", "init"], path)
    run(["git", "config", "user.name", "Test User"], path)
    run(["git", "config", "user.email", "test@example.com"], path)
    (path / "README.md").write_text(f"# {name}\n")
    run(["git", "add", "README.md"], path)
    run(["git", "commit", "-m", f"test commit for {name}"], path)
    return run(["git", "rev-parse", "HEAD"], path).stdout.strip()


def write_config(tmp_path):
    components_dir = tmp_path / "components"
    commits = {}
    lines = [f'COMPONENTS_DIR="{components_dir}"']

    for prefix, name in REQUIRED_COMPONENTS:
        repo_dir = components_dir / name
        commits[prefix] = create_component_repo(repo_dir, name)
        lines.extend(
            [
                f'readonly {prefix}_SRC_DIR="{repo_dir}"',
                f'export {prefix}_GIT="https://example.com/{name}.git"',
                f'export {prefix}_BRANCH="nightly"',
                f'export {prefix}_REV="HEAD"',
            ]
        )

    lines.extend(
        [
            'readonly HISTORY_UI_SRC_DIR=""',
            'export HISTORY_UI_GIT="https://example.com/history-ui.git"',
            'readonly PLOTTER_UI_SRC_DIR=""',
            'export PLOTTER_UI_GIT="https://example.com/plotter-ui.git"',
        ]
    )
    (tmp_path / "config.sh").write_text("\n".join(lines) + "\n")
    return commits


class PinVersionsTests(unittest.TestCase):
    def test_factory_full_pin_preserves_existing_factory_overrides(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            tmp_path = Path(temp_dir)
            commits = write_config(tmp_path)
            images_dir = tmp_path / "images"
            images_dir.mkdir()
            factory_versions = images_dir / "factory.versions.sh"
            factory_versions.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/bash
                    export LINUX_GIT="git@github.com:MeticulousHome/linux-fika.git"
                    export LINUX_BRANCH="linux-6.12.y"
                    export BACKEND_BRANCH="main-factory"
                    export BACKEND_REV="old-backend-rev" # factory backend
                    export DIAL_BRANCH="beta-factory"
                    export DIAL_REV="old-dial-rev" # factory dial
                    export UBOOT_REV="old-uboot-rev" # stale uboot
                    """
                )
            )

            run(
                [str(REPO_ROOT / "pin-versions.sh"), "--promote", "stable", "factory"],
                tmp_path,
            )

            contents = factory_versions.read_text()
            self.assertIn(
                'export LINUX_GIT="git@github.com:MeticulousHome/linux-fika.git"',
                contents,
            )
            self.assertIn('export LINUX_BRANCH="linux-6.12.y"', contents)
            self.assertIn('export BACKEND_BRANCH="main-factory"', contents)
            self.assertIn(
                'export BACKEND_REV="old-backend-rev" # factory backend',
                contents,
            )
            self.assertIn('export DIAL_BRANCH="beta-factory"', contents)
            self.assertIn(
                'export DIAL_REV="old-dial-rev" # factory dial',
                contents,
            )
            self.assertNotIn("old-uboot-rev", contents)
            self.assertIn(f'export UBOOT_REV="{commits["UBOOT"]}"', contents)


if __name__ == "__main__":
    unittest.main()
