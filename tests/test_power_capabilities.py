"""Missing sysfs support must not be reported as a working sleep/wake mode.

Fixtures model the Linux ABI files read by met-power-capabilities. Test both a
board with declared modes and a target with missing controls. A false default of
"deep" or a claimed wake/power validation would otherwise hide the lab blocker.
"""

import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/met-power-capabilities"
loader = importlib.machinery.SourceFileLoader("power_capabilities", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class PowerCapabilitiesTests(unittest.TestCase):
    def test_missing_controls_remain_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            result = module.inventory(Path(directory))
        self.assertEqual(result["suspend_states"], {"unavailable": 2})
        self.assertEqual(result["mem_sleep"], {"unavailable": 2})
        self.assertEqual(result["uart_wakeup"], [])
        self.assertFalse(result["wake_validated"])
        self.assertFalse(result["power_measured"])

    def test_inventory_reports_observed_abi_values_without_modifying_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                "sys/firmware/devicetree/base/model": "Test board\x00",
                "sys/power/state": "freeze mem\n",
                "sys/power/mem_sleep": "s2idle [deep]\n",
                "sys/devices/system/cpu/cpufreq/policy0/scaling_governor": "schedutil\n",
                "sys/class/backlight/backlight/brightness": "0\n",
                "sys/class/tty/ttymxc0/power/wakeup": "disabled\n",
            }
            for path, value in files.items():
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(value)
            before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
            result = module.inventory(root)
            after = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(result["board_model"], {"value": "Test board"})
        self.assertEqual(result["mem_sleep"], {"value": "s2idle [deep]"})
        self.assertEqual(result["cpu_policies"][0]["scaling_governor"], {"value": "schedutil"})
        self.assertEqual(result["backlights"][0]["brightness"], {"value": "0"})
        self.assertEqual(result["uart_wakeup"][0]["wakeup"], {"value": "disabled"})
        self.assertFalse(result["wake_validated"])


if __name__ == "__main__":
    unittest.main()
