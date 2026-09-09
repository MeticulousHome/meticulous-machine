import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).parents[1]
SCRIPT = (ROOT / "rauc-config" / "u-boot.cmd").read_text()
HOOK = (ROOT / "rauc-config" / "bootloader_hooks.sh").read_text()
OTA_BUILDER = (ROOT / "make-bootloader-ota.sh").read_text()


def switch_block() -> str:
    start = SCRIPT.index('if test "x${rauc_switch_requested}" = "x1"; then')
    end = SCRIPT.index("\nsetenv rauc_active", start)
    return SCRIPT[start:end]


def run_boot_script(**environment):
    """Run the production Hush script with deterministic command stubs."""
    # Bash and Hush differ in quoted for-loop word splitting for this script.
    # Adapt those two loop headers and execute the actual remaining control flow.
    bash_script = SCRIPT.replace(
        'for BOOT_SLOT in "${BOOT_ORDER}"; do', "for BOOT_SLOT in ${BOOT_ORDER}; do"
    )
    bash_script = bash_script.replace("0x${BOOT_A_LEFT}", "${BOOT_A_LEFT}")
    bash_script = bash_script.replace("0x${BOOT_B_LEFT}", "${BOOT_B_LEFT}")
    bash_script = bash_script.replace(
        'if test "x${rauc_active}" != "x"; then\n    # skip remaining slots',
        'if test "x${rauc_active}" != "x"; then\n    : # skip remaining slots',
    )
    harness = r'''
[ "${TRACE_HARNESS-}" != "1" ] || set -x
setenv() {
  if [ "$#" -eq 1 ]; then
    unset "$1"
  else
    printf -v "$1" '%s' "$2"
  fi
}
setexpr() { printf -v "$1" '%s' "$(( $2 - $4 ))"; }
load() {
  part="${2##*:}"
  path="$4"
  LOAD_PARTS="${LOAD_PARTS} ${part}"
  if [ "${part}" = "${MISSING_KERNEL_PART}" ] && [ "${path##*/}" = "${image}" ]; then
    return 1
  fi
  return 0
}
unzip() { UNZIP_PARTS="${UNZIP_PARTS} ${mmcpart}"; return 0; }
run() {
  case "$1" in
    loadimage)
      load mmc "${mmcdev}:${mmcpart}" "${img_addr}" "${bootdir}/${image}" &&
        unzip "${img_addr}" "${loadaddr}"
      ;;
    loadfdt)
      load mmc "${mmcdev}:${mmcpart}" "${fdt_addr_r}" "${bootdir}/board.dtb"
      ;;
    mmcboot) return 0 ;;
    *) return 0 ;;
  esac
}
saveenv() { SAVEENV_CALLS=$((SAVEENV_CALLS + 1)); }
reset() { return 1; }
LOAD_PARTS=""
UNZIP_PARTS=""
SAVEENV_CALLS=0
source "$1"
script_status=$?
[ "$script_status" -eq 0 ] || exit "$script_status"
printf '\n__STATE__\n'
for name in BOOT_ORDER BOOT_A_LEFT BOOT_B_LEFT rauc_last_booted rauc_switch_requested LOAD_PARTS UNZIP_PARTS SAVEENV_CALLS; do
  printf '%s=%s\n' "$name" "${!name-}"
done
'''
    defaults = {
        "mmcdev": "2",
        "img_addr": "0x42000000",
        "loadaddr": "0x40480000",
        "fdt_addr_r": "0x43000000",
        "bootdir": "/boot",
        "image": "Image.gz",
        "MISSING_KERNEL_PART": "none",
    }
    with tempfile.NamedTemporaryFile("w", delete=False) as script_file:
        script_file.write(bash_script)
        script_path = script_file.name
    try:
        result = subprocess.run(
            ["bash", "-c", harness, "harness", script_path],
            env={**os.environ, **defaults, **environment},
            text=True,
            capture_output=True,
            check=True,
        )
    finally:
        os.unlink(script_path)
    output, raw_state = result.stdout.rsplit("\n__STATE__\n", 1)
    state = dict(line.split("=", 1) for line in raw_state.strip().splitlines())
    state["OUTPUT"] = output
    state["STDERR"] = result.stderr
    return state


class RearButtonBootSwitchTests(unittest.TestCase):
    def test_request_is_consumed_before_environment_is_saved(self):
        self.assertLess(
            SCRIPT.index("setenv rauc_switch_requested\n"), SCRIPT.index("saveenv")
        )

    def test_slot_order_changes_only_after_kernel_and_device_tree_checks(self):
        block = switch_block()
        load_kernel = block.index(
            "if load mmc ${mmcdev}:${mmcpart} ${img_addr} ${bootdir}/${image}; then"
        )
        decompress_kernel = block.index("if unzip ${img_addr} ${loadaddr}; then")
        load_fdt = block.index("if run loadfdt; then", decompress_kernel)
        commit = block.index(
            'setenv BOOT_ORDER "${rauc_switch_to} ${rauc_switch_from}"'
        )

        self.assertLess(load_kernel, decompress_kernel)
        self.assertLess(decompress_kernel, load_fdt)
        self.assertLess(load_fdt, commit)

    def test_switch_has_a_single_boot_attempt_and_explicit_refusal_paths(self):
        block = switch_block()

        self.assertIn("setenv BOOT_A_LEFT 1", block)
        self.assertIn("setenv BOOT_B_LEFT 1", block)
        self.assertEqual(block.count("Rear-button switch refused:"), 4)
        self.assertIn("alternate slot is marked unbootable", block)
        self.assertIn("alternate slot has no usable kernel", block)
        self.assertIn("alternate slot kernel is corrupt", block)
        self.assertIn("alternate slot has no usable device tree", block)

    def test_missing_kernel_cannot_reuse_stale_compressed_bytes(self):
        state = run_boot_script(
            BOOT_ORDER="A B",
            BOOT_A_LEFT="3",
            BOOT_B_LEFT="3",
            rauc_last_booted="A",
            rauc_switch_requested="1",
            MISSING_KERNEL_PART="4",
        )

        self.assertEqual(state["BOOT_ORDER"], "A B")
        self.assertEqual(state["BOOT_B_LEFT"], "3")
        # The normal A boot decompresses once. The missing B preflight must not
        # call unzip even though the harness models stale compressed RAM.
        self.assertEqual(state["UNZIP_PARTS"].split(), ["3"])
        self.assertIn("no usable kernel", state["OUTPUT"])

    def test_legacy_environment_infers_live_fallback_slot(self):
        state = run_boot_script(
            BOOT_ORDER="B A",
            BOOT_A_LEFT="3",
            BOOT_B_LEFT="0",
            rauc_switch_requested="1",
        )

        self.assertEqual(state["BOOT_ORDER"], "B A")
        self.assertEqual(state["rauc_last_booted"], "A")
        self.assertIn("marked unbootable", state["OUTPUT"])

    def test_successful_switch_commits_one_attempt_and_records_selected_slot(self):
        state = run_boot_script(
            BOOT_ORDER="A B",
            BOOT_A_LEFT="3",
            BOOT_B_LEFT="3",
            rauc_last_booted="A",
            rauc_switch_requested="1",
        )

        self.assertEqual(state["BOOT_ORDER"], "B A")
        self.assertEqual(state["BOOT_B_LEFT"], "0")
        self.assertEqual(state["rauc_last_booted"], "B")
        self.assertEqual(state["UNZIP_PARTS"].split(), ["4", "4"])

    def test_bootloader_ota_carries_and_orders_fail_safe_script_activation(self):
        self.assertIn('cp "$BOOT_SCRIPT_PATH" "$CONTENT_DIR/u-boot.scr"', OTA_BUILDER)
        self.assertIn('${RAUC_BUNDLE_MOUNT_POINT}/u-boot.scr', HOOK)
        stage_u_boot = HOOK.index('cp "$source" "$target_dir/.u-boot.scr.new"')
        stage_boot = HOOK.index('cp "$source" "$target_dir/.boot.scr.new"')
        activate_u_boot = HOOK.index(
            'mv -f "$target_dir/.u-boot.scr.new" "$target_dir/u-boot.scr"'
        )
        activate_boot = HOOK.index(
            'mv -f "$target_dir/.boot.scr.new" "$target_dir/boot.scr"'
        )

        self.assertLess(stage_u_boot, stage_boot)
        self.assertLess(stage_boot, activate_u_boot)
        self.assertLess(activate_u_boot, activate_boot)

    def test_bootloader_hook_installs_matching_script_and_rejects_missing_source(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            bundle = temp / "bundle"
            target = temp / "env"
            stub_bin = temp / "bin"
            fw_setenv_log = temp / "fw_setenv.log"
            bundle.mkdir()
            target.mkdir()
            stub_bin.mkdir()
            (bundle / "u-boot.scr").write_bytes(b"matched-script")
            (target / "boot.scr").write_bytes(b"old-script")
            (target / "u-boot.scr").write_bytes(b"old-script")

            stubs = {
                "fw_printenv": """#!/bin/sh
printf 'BOOT_ORDER=A B\\nBOOT_A_LEFT=3\\nBOOT_B_LEFT=3\\nemmc_dev=2=legacy\\n'
""",
                "fw_setenv": """#!/bin/sh
printf '%s\\t%s\\n' "$1" "${2-}" >> "$FW_SETENV_LOG"
exit 0
""",
                "sync": "#!/bin/sh\nexit 0\n",
            }
            for name, contents in stubs.items():
                path = stub_bin / name
                path.write_text(contents)
                path.chmod(0o755)

            hook_environment = {
                **os.environ,
                "PATH": f"{stub_bin}:{os.environ['PATH']}",
                "RAUC_SLOT_CLASS": "bootloader",
                "RAUC_BUNDLE_MOUNT_POINT": str(bundle),
                "BOOT_SCRIPT_TARGET_DIR": str(target),
                "FW_SETENV_LOG": str(fw_setenv_log),
            }
            subprocess.run(
                ["bash", str(ROOT / "rauc-config" / "bootloader_hooks.sh"), "slot-post-install"],
                env=hook_environment,
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertEqual((target / "boot.scr").read_bytes(), b"matched-script")
            self.assertEqual((target / "u-boot.scr").read_bytes(), b"matched-script")
            self.assertFalse((target / ".boot.scr.new").exists())
            self.assertFalse((target / ".u-boot.scr.new").exists())
            self.assertIn("emmc_dev\t2=legacy", fw_setenv_log.read_text().splitlines())

            (bundle / "u-boot.scr").unlink()
            (target / "boot.scr").write_bytes(b"known-good")
            (target / "u-boot.scr").write_bytes(b"known-good")
            failed = subprocess.run(
                ["bash", str(ROOT / "rauc-config" / "bootloader_hooks.sh"), "slot-post-install"],
                env=hook_environment,
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual((target / "boot.scr").read_bytes(), b"known-good")
            self.assertEqual((target / "u-boot.scr").read_bytes(), b"known-good")

    def test_bootloader_hook_propagates_staging_and_activation_failures(self):
        scenarios = {
            "first staging copy": {"FAIL_CP_CALL": "1"},
            "second staging copy": {"FAIL_CP_CALL": "2"},
            "authoritative activation": {"FAIL_MV_CALL": "2"},
            "pre-activation sync": {"FAIL_SYNC_CALL": "1"},
            "post-activation sync": {"FAIL_SYNC_CALL": "2"},
        }
        for scenario, injected_environment in scenarios.items():
            with (
                self.subTest(scenario=scenario),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                temp = Path(temp_dir)
                bundle = temp / "bundle"
                target = temp / "env"
                stub_bin = temp / "bin"
                bundle.mkdir()
                target.mkdir()
                stub_bin.mkdir()
                (bundle / "u-boot.scr").write_bytes(b"matched-script")
                (target / "boot.scr").write_bytes(b"known-good")
                (target / "u-boot.scr").write_bytes(b"known-good")

                stubs = {
                    "cp": """#!/bin/sh
count_file="$STUB_STATE/cp"
count=$(($(cat "$count_file" 2>/dev/null || printf 0) + 1))
printf '%s' "$count" > "$count_file"
[ "${FAIL_CP_CALL-}" != "$count" ] || exit 71
exec /bin/cp "$@"
""",
                    "mv": """#!/bin/sh
count_file="$STUB_STATE/mv"
count=$(($(cat "$count_file" 2>/dev/null || printf 0) + 1))
printf '%s' "$count" > "$count_file"
[ "${FAIL_MV_CALL-}" != "$count" ] || exit 72
exec /bin/mv "$@"
""",
                    "sync": """#!/bin/sh
count_file="$STUB_STATE/sync"
count=$(($(cat "$count_file" 2>/dev/null || printf 0) + 1))
printf '%s' "$count" > "$count_file"
[ "${FAIL_SYNC_CALL-}" != "$count" ] || exit 73
exec /bin/sync "$@"
""",
                    "fw_printenv": "#!/bin/sh\nprintf 'BOOT_ORDER=A B\\n'\n",
                    "fw_setenv": "#!/bin/sh\nexit 0\n",
                }
                for name, contents in stubs.items():
                    path = stub_bin / name
                    path.write_text(contents)
                    path.chmod(0o755)

                hook_environment = {
                    **os.environ,
                    **injected_environment,
                    "PATH": f"{stub_bin}:{os.environ['PATH']}",
                    "RAUC_SLOT_CLASS": "bootloader",
                    "RAUC_BUNDLE_MOUNT_POINT": str(bundle),
                    "BOOT_SCRIPT_TARGET_DIR": str(target),
                    "STUB_STATE": str(temp),
                }
                failed = subprocess.run(
                    [
                        "bash",
                        str(ROOT / "rauc-config" / "bootloader_hooks.sh"),
                        "slot-post-install",
                    ],
                    env=hook_environment,
                    text=True,
                    capture_output=True,
                )
                self.assertNotEqual(failed.returncode, 0)
                if scenario in {
                    "first staging copy",
                    "second staging copy",
                    "authoritative activation",
                    "pre-activation sync",
                }:
                    self.assertEqual(
                        (target / "boot.scr").read_bytes(), b"known-good"
                    )

    def test_bootloader_hook_propagates_fw_setenv_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            bundle = temp / "bundle"
            target = temp / "env"
            stub_bin = temp / "bin"
            bundle.mkdir()
            target.mkdir()
            stub_bin.mkdir()
            (bundle / "u-boot.scr").write_bytes(b"matched-script")
            (target / "boot.scr").write_bytes(b"known-good")
            (target / "u-boot.scr").write_bytes(b"known-good")

            stubs = {
                "fw_printenv": "#!/bin/sh\nprintf 'BOOT_ORDER=A B\\n'\n",
                "fw_setenv": "#!/bin/sh\nexit 74\n",
                "sync": "#!/bin/sh\nexit 0\n",
            }
            for name, contents in stubs.items():
                path = stub_bin / name
                path.write_text(contents)
                path.chmod(0o755)

            failed = subprocess.run(
                [
                    "bash",
                    str(ROOT / "rauc-config" / "bootloader_hooks.sh"),
                    "slot-post-install",
                ],
                env={
                    **os.environ,
                    "PATH": f"{stub_bin}:{os.environ['PATH']}",
                    "RAUC_SLOT_CLASS": "bootloader",
                    "RAUC_BUNDLE_MOUNT_POINT": str(bundle),
                    "BOOT_SCRIPT_TARGET_DIR": str(target),
                },
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(failed.returncode, 0)

    def test_bootloader_ota_builder_passes_matched_artifacts_to_rauc(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            build = temp / "components" / "bootloader" / "build"
            rauc_config = temp / "rauc-config"
            stub_bin = temp / "bin"
            build.mkdir(parents=True)
            rauc_config.mkdir()
            stub_bin.mkdir()
            (build / "imx-boot-sd.bin").write_bytes(b"bootloader")
            (build / "u-boot.scr").write_bytes(b"matched-script")
            shutil.copy(ROOT / "make-bootloader-ota.sh", temp)
            shutil.copy(ROOT / "rauc-config" / "bootloader_hooks.sh", rauc_config)
            (temp / "test.cert").write_text("certificate")
            (temp / "test.key").write_text("key")
            rauc_stub = stub_bin / "rauc"
            rauc_stub.write_text(
                """#!/bin/sh
set -eu
[ "$1" = bundle ]
[ -f "$4/bootloader.img" ]
[ -f "$4/u-boot.scr" ]
[ -f "$4/bootloader_hooks.sh" ]
printf 'bundle' > "$5"
"""
            )
            rauc_stub.chmod(0o755)

            subprocess.run(
                [
                    "bash",
                    "make-bootloader-ota.sh",
                    "--variant",
                    "sw122-test",
                    "--cert",
                    "test.cert",
                    "--key",
                    "test.key",
                ],
                cwd=temp,
                env={**os.environ, "PATH": f"{stub_bin}:{os.environ['PATH']}"},
                text=True,
                capture_output=True,
                check=True,
            )
            bundles = list(temp.glob("rauc_meticulous_boot_sw122-test-*.raucb"))
            self.assertEqual(len(bundles), 1)
            self.assertEqual(bundles[0].read_bytes(), b"bundle")


if __name__ == "__main__":
    unittest.main()
