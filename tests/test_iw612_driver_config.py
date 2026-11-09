"""The IW612 driver configuration that met-iw612-set-region writes at each Wi-Fi start.

Regression a user would see without it: after a Wi-Fi firmware hang the
driver's in-band reset reloads the combo firmware instead of the Wi-Fi-only
one. The download times out ("Firmware Init Failed"), wlan0 disappears and
Bluetooth breaks, and only a reboot brings them back.

Where the expected values come from: the NXP mwifiex driver the machine runs
(MM6X18505.p14, NXP release lf-6.12.3-1.0.0).
woal_update_firmware_name() uses fw_name for every load and every reset when
it is set. Without it, the in-band reset (woal_do_sdiommc_flr, "Load wlan only
binary") clears fw_serial and loads the Wi-Fi-only firmware,
nxp/sd_w61x_v1.bin.se, while a load with fw_serial on loads the combo
firmware the chip strap selects, nxp/sduart_nw61x_v1.bin.se. indrstcfg's low
byte 2 enables the in-band reset (NXP AN14213, section 3). Drivers from
540.p33 (lf-6.12.49-2.2.0) check wifi_fw_name first on a reset; with neither
key set they pick the same firmware, so the expectations hold for both.

Bug it catches: fw_name copied back from the vendor's wifi_mod_para.conf
(every reset fails again), or fw_serial=0 without fw_name (the boot would
load the Wi-Fi-only firmware and leave Bluetooth without firmware).
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "met-iw612-set-region"
STATIC_CONFIG = ROOT / "config" / "usr" / "lib" / "firmware" / "nxp" / "var_wifi_mod_para.conf"
REGIONS = {"US": "US", "CA": "CA", "JP": "JP", "DE": "EU"}


def parse_block(text: str) -> dict:
    """The key=value lines of the SDIW612 block."""
    lines = [line.strip() for line in text.splitlines()]
    start = lines.index("SDIW612 = {")
    end = lines.index("}", start)
    return dict(line.split("=", 1) for line in lines[start + 1 : end] if line)


def write_config(country: str = "", profile: str = "") -> dict:
    """Run the script as variscite-wifi's start does and parse what it wrote."""
    with tempfile.TemporaryDirectory() as tmp:
        firmware = Path(tmp) / "firmware"
        state = Path(tmp) / "state"
        firmware.mkdir()
        state.mkdir()
        for name in REGIONS.values():
            (firmware / f"rutxpower_{name}.bin").touch()
            (firmware / f"txpower_{name}.bin").touch()
        if country:
            (state / "iw612-region.conf").write_text(
                f"IW612_COUNTRY={country}\nIW612_POWER_PROFILE={profile}\n"
            )
        env = dict(
            os.environ,
            MET_IW612_FIRMWARE_DIR=str(firmware),
            MET_IW612_STATE_DIR=str(state),
            MET_IW612_LEGACY_STATE_FILE=str(Path(tmp) / "no-legacy-state"),
        )
        subprocess.run(
            ["bash", str(SCRIPT), "--apply-current", "--no-iw", "--no-reload-driver"],
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        return parse_block((firmware / "var_wifi_mod_para.conf").read_text())


class Iw612DriverConfigTest(unittest.TestCase):
    def assert_resets_load_wifi_only_firmware(self, block: dict) -> None:
        self.assertNotIn("fw_name", block)
        self.assertEqual(block.get("fw_serial"), "1")
        self.assertEqual(block.get("indrstcfg"), "0xFF02")

    def test_unconfigured_region(self):
        self.assert_resets_load_wifi_only_firmware(write_config())

    def test_every_region(self):
        for country, profile in REGIONS.items():
            with self.subTest(country=country):
                block = write_config(country, profile)
                self.assert_resets_load_wifi_only_firmware(block)
                self.assertEqual(block["init_hostcmd_cfg"], f"nxp/rutxpower_{profile}.bin")
                self.assertEqual(block["txpwrlimit_cfg"], f"nxp/txpower_{profile}.bin")

    def test_static_copy_matches_the_template(self):
        """The image's own var_wifi_mod_para.conf is what an unconfigured start writes."""
        self.assertEqual(parse_block(STATIC_CONFIG.read_text()), write_config())


if __name__ == "__main__":
    unittest.main()
