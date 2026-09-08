from pathlib import Path
import unittest


SCRIPT = (Path(__file__).parents[1] / "rauc-config" / "u-boot.cmd").read_text()


def switch_block() -> str:
    start = SCRIPT.index('if test "x${rauc_switch_requested}" = "x1"; then')
    end = SCRIPT.index("\nsetenv rauc_active", start)
    return SCRIPT[start:end]


class RearButtonBootSwitchTests(unittest.TestCase):
    def test_request_is_consumed_before_environment_is_saved(self):
        self.assertLess(
            SCRIPT.index("setenv rauc_switch_requested\n"), SCRIPT.index("saveenv")
        )

    def test_slot_order_changes_only_after_kernel_and_device_tree_checks(self):
        block = switch_block()
        load_kernel = block.index("if run loadimage; then")
        load_fdt = block.index("if run loadfdt; then", load_kernel)
        commit = block.index(
            'setenv BOOT_ORDER "${rauc_switch_to} ${rauc_switch_from}"'
        )

        self.assertLess(load_kernel, load_fdt)
        self.assertLess(load_fdt, commit)

    def test_switch_has_a_single_boot_attempt_and_explicit_refusal_paths(self):
        block = switch_block()

        self.assertIn("setenv BOOT_A_LEFT 1", block)
        self.assertIn("setenv BOOT_B_LEFT 1", block)
        self.assertEqual(block.count("Rear-button switch refused:"), 3)
        self.assertIn("alternate slot is marked unbootable", block)
        self.assertIn("alternate slot has no usable kernel", block)
        self.assertIn("alternate slot has no usable device tree", block)


if __name__ == "__main__":
    unittest.main()
