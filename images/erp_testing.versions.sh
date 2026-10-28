#!/bin/bash
export LINUX_REV="9e14e4a6eb19f16722d7cb7e4c1afd635f8dad91" # set the usbotg1 node as host only on meticulous DT
export UBOOT_REV="e0e3843b7d6745d03007baf8b956b71f5b6c1265" # Merge pull request #5 from MeticulousHome/backpropagate-beta-to-nightly-2026-09-29
export ATF_REV="bed39c167c883b335d5fc1046ce16e10a611b4c4" # plat: imx8m: Fix compile errors with active VAR_ENABLE_IMX_UART
export IMX_MKIMAGE_REV="71b8c18af93a5eb972d80fbec290006066cff24f" # Add flash_all_ap target for non-Linux ap image.
export DEBIAN_REV="db279cf0c71d35b1a9930699bca0446414390549" # nxp: remove last bin of NXP / variscite specific firmware
export BACKEND_REV="81ea704d1340a686c9d547c4f8f3a75c16e7c4d9" # Merge pull request #461 from MeticulousHome/feature/rust-backend
export DIAL_REV="2f9bcdc20e79a08068d298af80a775e86f7344f3" # Merge pull request #651 from MeticulousHome/fix/raise-piston
export WEB_APP_REV="c1be0bff59f5e99769e6a04963ff576827de80b5" # Merge pull request #21 from MeticulousHome/feat/plotter-link
export WATCHER_REV="198691006a52489cf308fdc37d047c2f610b2295" # Merge pull request #20 from MeticulousHome/backpropagate-beta-to-nightly-2026-09-29
export FIRMWARE_REV="c4bf8ef56554f0739ee939f68a36720aae7325dd" # Merge pull request #538 from MeticulousHome/backpropagate-beta-to-nightly-2026-10-26
export RAUC_REV="269e1721b3c5f6512f7dfb7fd19f9108515c2a98" # debian: Disable test building for now
export HAWKBIT_REV="60f34c8cdd0dbad3b97373080e642478724bfc30" # fix: Take into account partial download size
export PSPLASH_REV="5b0085b559f1aac09c0a88f85f203ab332bbe1c9" # Replace baseimage with DOT image
export PLOTTER_UI_REV="f2cba24402eb2dc2831db9f12d5a78482fe49cd3" # Merge pull request #112 from MeticulousHome/deps/dependabot-oct26
export CRASH_REPORTER_REV="ebf10c09c463575279f63d8f227e4b29f369f4d0" # Merge pull request #13 from MeticulousHome/backpropagate-beta-to-nightly-2026-09-29
