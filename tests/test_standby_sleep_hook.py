"""The ErP standby wake-up sources the image arms around suspend.

The systemd-sleep hook must leave the SoC wakeable by the app (WoWLAN on the
IW612's out-of-band wake line, v2 boards) and by the ESP32 (UART1), must leave
the v1 boards' LWB5 alone (no WoWL in its firmware), and must give the
radio back to NetworkManager's power-save-off setting on resume. The IW612
driver must run with hs_auto_arp=0, because with it on moal wakes the host on any
mDNS frame instead of the magic packet; met-iw612-set-region rewrites the
driver's parameters at every WiFi start, so both copies must carry it. The hook
then programs the magic packet filter itself, along with the ARP response the
app's unicast wake packet depends on.
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
        self.mef_conf = self.tmp / "mef.conf"
        self.mlanutl.write_text(
            f'#!/bin/sh\necho "mlanutl $*" >> "{self.calls}"\n'
            f'[ "$2" = mefcfg ] && cp "$3" "{self.mef_conf}"\nexit 0\n'
        )
        self.mlanutl.chmod(0o755)
        (self.sysfs / "class" / "net" / "wlan0" / "address").write_text("b0:65:3a:87:b7:ea\n")
        ip_tool = bin_dir / "ip"
        ip_tool.write_text('#!/bin/sh\n[ -n "$FAKE_IPV4" ] && echo "2: wlan0    inet $FAKE_IPV4/20 brd 10.10.15.255 scope global wlan0"\nexit 0\n')
        ip_tool.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "MET_STANDBY_SYSFS": str(self.sysfs),
            "MET_STANDBY_MWLAN_PROC": str(self.tmp / "mwlan"),
            "MET_STANDBY_MLANUTL": str(self.mlanutl),
            "FAKE_IPV4": "10.10.0.55",
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
        self.assertEqual((self.sdio_host / "power" / "wakeup").read_text(), "disabled\n")

    def test_suspend_programs_the_magic_packet_and_arp_filters(self):
        calls = self.run_hook("pre", "suspend")
        self.assertIn('mlanutl wlan0 ipaddr 3;10.10.0.55', calls)
        conf = self.mef_conf.read_text()
        self.assertTrue(conf.startswith("mefcfg={\n    Criteria=0x0b\n    NumEntries=2\n"), conf)
        self.assertIn("byte=0a:0a:00:37", conf)
        self.assertEqual(conf.count("repeat=16\n            byte=b0:65:3a:87:b7:ea\n"), 2)
        self.assertIn("offset=56", conf)
        self.assertIn("offset=28", conf)
        # Nothing but the magic packet wakes the host: mDNS must not.
        self.assertEqual(conf.count("action=3\n"), 1)
        self.assertNotIn("5353", conf)

    def test_suspend_without_an_address_still_programs_the_magic_packet_filter(self):
        self.env["FAKE_IPV4"] = ""
        calls = self.run_hook("pre", "suspend")
        self.assertNotIn("ipaddr", "\n".join(calls))
        conf = self.mef_conf.read_text()
        self.assertIn("NumEntries=1\n    mef_entry_0={", conf)
        self.assertNotIn("action=16", conf)

    def test_suspend_reports_a_failed_filter(self):
        self.mlanutl.write_text("#!/bin/sh\nexit 1\n")
        result = subprocess.run([str(HOOK), "pre", "suspend"], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mlanutl mefcfg failed: the app cannot wake the SoC", result.stdout)

    def test_suspend_without_wowlan_keeps_the_wake_line_quiet(self):
        # The magic packet filter replaces the host sleep conditions at suspend:
        # without it, any broadcast on the wake line would wake the SoC.
        iw = self.tmp / "bin" / "iw"
        iw.write_text(
            f'#!/bin/sh\necho "iw $*" >> "{self.calls}"\n'
            'case "$*" in *wowlan*) echo "command failed: Invalid argument (-22)" >&2; exit 1 ;; esac\n'
        )
        result = subprocess.run([str(HOOK), "pre", "suspend"], env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mwlan_config.read_text(), "hssetpara=0x7 0xff 200\n")
        self.assertIn("iw wowlan enable failed: the app cannot wake the SoC", result.stdout)
        self.assertFalse(self.mef_conf.exists())
        self.assertIn("iw dev wlan0 set power_save on", self.calls.read_text().splitlines())

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
        self.assertEqual(calls, ["iw dev wlan0 set power_save off", "mlanutl wlan0 ipaddr 0;10.10.0.55"])

    def test_resume_on_the_lwb5_leaves_mlanutl_alone(self):
        self.use_wifi_driver("brcmfmac")
        calls = self.run_hook("post", "suspend")
        self.assertEqual(calls, ["iw dev wlan0 set power_save off"])

    def test_suspend_without_wifi_still_arms_the_esp32_uart(self):
        (self.sysfs / "class" / "net" / "wlan0" / "phy80211" / "name").unlink()
        calls = self.run_hook("pre", "suspend")
        self.assertEqual((self.sysfs / "class" / "tty" / "ttymxc0" / "power" / "wakeup").read_text(), "enabled\n")
        self.assertEqual(calls, [])


class DriverLeavesTheWakeFiltersToTheHookTest(unittest.TestCase):
    def test_shipped_and_regenerated_driver_parameters_disable_hs_auto_arp(self):
        self.assertIn("\ths_auto_arp=0\n", MOD_PARA.read_text())
        self.assertIn("\ths_auto_arp=0\n", SET_REGION.read_text())


if __name__ == "__main__":
    unittest.main()
