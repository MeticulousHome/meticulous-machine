"""The ErP standby wake-up sources the image arms around suspend.

The systemd-sleep hook must leave the SoC wakeable by the app (WoWLAN on the
IW612's out-of-band wake line, v2 boards) and by the ESP32 (UART1), must leave
the v1 boards' LWB5 alone (no WoWL in its firmware), and must give the
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
        # wlan0 sits on an SDIO function under the usdhc1 host, which can wake the system.
        self.sdio_host = self.sysfs / "devices" / "platform" / "30b40000.mmc"
        (self.sdio_host / "power").mkdir(parents=True)
        (self.sdio_host / "power" / "wakeup").write_text("disabled\n")
        func = self.sdio_host / "mmc_host" / "mmc0" / "mmc0:0001" / "mmc0:0001:1"
        func.mkdir(parents=True)
        (self.sysfs / "class" / "net" / "wlan0" / "device").symlink_to(func)
        self.drivers = self.sysfs / "bus" / "sdio" / "drivers"
        self.use_wifi_driver("wlan_sdio")
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

    def use_wifi_driver(self, name):
        (self.drivers / name).mkdir(parents=True, exist_ok=True)
        link = self.sysfs / "class" / "net" / "wlan0" / "device" / "driver"
        if link.is_symlink():
            link.unlink()
        link.symlink_to(self.drivers / name)

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
        self.assertEqual((self.sdio_host / "power" / "wakeup").read_text(), "disabled\n")

    def test_suspend_on_the_lwb5_leaves_its_sdio_host_alone(self):
        # Its firmware has no WoWL, and an SDIO host left armed as a wake-up
        # source loses the card on resume: WiFi stays down until a reboot.
        self.use_wifi_driver("brcmfmac")
        result = subprocess.run([str(HOOK), "pre", "suspend"], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual((self.sdio_host / "power" / "wakeup").read_text(), "disabled\n")
        self.assertEqual(self.mwlan_config.read_text(), "")
        self.assertEqual(calls, ["iw dev wlan0 set power_save on"])
        self.assertIn("WiFi on brcmfmac: WoWLAN not armed", result.stdout)

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
