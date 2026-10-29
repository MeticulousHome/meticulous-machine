"""The ErP standby wake-up sources the image arms around suspend.

The systemd-sleep hook must leave the SoC wakeable by the app (WoWLAN on the
IW612's out-of-band wake line) and by the ESP32 (UART1), and must give the
radio back to NetworkManager's power-save-off setting on resume. The IW612
driver must answer ARP while the host sleeps, or the app's unicast wake packet
never reaches the machine; met-iw612-set-region rewrites the driver's
parameters at every WiFi start, so both copies must carry it.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HOOK = REPO_ROOT / "config" / "usr" / "lib" / "systemd" / "system-sleep" / "meticulous-standby"
MOD_PARA = REPO_ROOT / "config" / "usr" / "lib" / "firmware" / "nxp" / "var_wifi_mod_para.conf"
SET_REGION = REPO_ROOT / "scripts" / "met-iw612-set-region"


class StandbySleepHookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="standby-hook-"))
        self.sysfs = self.tmp / "sys"
        (self.sysfs / "class" / "tty" / "ttymxc0" / "power").mkdir(parents=True)
        (self.sysfs / "class" / "tty" / "ttymxc0" / "power" / "wakeup").write_text("disabled\n")
        phy = self.sysfs / "class" / "net" / "wlan0" / "phy80211"
        phy.mkdir(parents=True)
        (phy / "name").write_text("phy0\n")
        # A reloaded driver takes the next adapter slot.
        self.mwlan_config = self.tmp / "mwlan" / "adapter1" / "config"
        self.mwlan_config.parent.mkdir(parents=True)
        self.mwlan_config.write_text("")
        self.calls = self.tmp / "calls"
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        iw = bin_dir / "iw"
        iw.write_text(f'#!/bin/sh\necho "iw $*" >> "{self.calls}"\n')
        iw.chmod(0o755)
        self.mlanutl = bin_dir / "mlanutl"
        self.mlanutl.write_text(f'#!/bin/sh\necho "mlanutl $*" >> "{self.calls}"\n')
        self.mlanutl.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "MET_STANDBY_SYSFS": str(self.sysfs),
            "MET_STANDBY_MWLAN_PROC": str(self.tmp / "mwlan"),
            "MET_STANDBY_MLANUTL": str(self.mlanutl),
        }

    def run_hook(self, *args):
        result = subprocess.run([str(HOOK), *args], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_suspend_arms_wowlan_out_of_band_and_the_esp32_uart(self):
        calls = self.run_hook("pre", "suspend")
        self.assertEqual((self.sysfs / "class" / "tty" / "ttymxc0" / "power" / "wakeup").read_text(), "enabled\n")
        self.assertEqual(self.mwlan_config.read_text(), "hssetpara=0x7 17 200\n")
        self.assertIn("iw phy phy0 wowlan enable magic-packet", calls)
        self.assertIn("iw dev wlan0 set power_save on", calls)
        self.assertNotIn("mlanutl", "\n".join(calls))

    def test_suspend_without_the_proc_interface_sets_the_wake_signal_with_mlanutl(self):
        self.mwlan_config.unlink()
        calls = self.run_hook("pre", "suspend")
        self.assertIn("mlanutl wlan0 hssetpara 0x7 17 200", calls)

    def test_resume_gives_power_save_back_to_networkmanager(self):
        calls = self.run_hook("post", "suspend")
        self.assertEqual(calls, ["iw dev wlan0 set power_save off"])

    def test_suspend_without_wifi_still_arms_the_esp32_uart(self):
        (self.sysfs / "class" / "net" / "wlan0" / "phy80211" / "name").unlink()
        calls = self.run_hook("pre", "suspend")
        self.assertEqual((self.sysfs / "class" / "tty" / "ttymxc0" / "power" / "wakeup").read_text(), "enabled\n")
        self.assertEqual(calls, [])


class DriverAnswersArpWhileAsleepTest(unittest.TestCase):
    def test_shipped_and_regenerated_driver_parameters_enable_hs_auto_arp(self):
        self.assertIn("\ths_auto_arp=1\n", MOD_PARA.read_text())
        self.assertIn("\ths_auto_arp=1\n", SET_REGION.read_text())


if __name__ == "__main__":
    unittest.main()
