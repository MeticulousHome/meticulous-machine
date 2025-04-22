#!/bin/bash
export LINUX_GIT="git@github.com:MeticulousHome/linux-fika.git"
export LINUX_BRANCH="linux-6.12.y"
export HISTORY_UI_REV="452f6984333304c914554bf4470d42721a8e696c" # fix(config): conditionally set assetPrefix in Next.js config
export LINUX_REV="1e422ae4d37414bedd6d56c322037a74e34ad41d" # arch/arm64/config/meticulous: Add PSI and checkpoint-restore
export UBOOT_REV="7fdc6b1de1358248e7743069ff335f4168228374" # Enable fastboot recovery on boot via recovery pin
export ATF_REV="7575633e03ff952a18c0a2c0aa543dee793fda5f" # imx: Fix multiple definition of ipc_handle
export IMX_MKIMAGE_REV="6745ccdcf15384891639b7ced3aa6ce938682365" # imx8m: Add script to generate SIT (secondary image table)
export DEBIAN_REV="8823fd19e2016e49023c82ddab8ef9b266313d53" # packages: install mesa from backports
export BACKEND_REV="19b27b6708ee484d463c28e463d0e367e0a87261" # shots: clamp flow and pressure to positive numbers
export DIAL_REV="62f88949139c9c4de6cf6bd91a8227ca2d00f72a" # chore(release): v1.74.0 [skip ci]
export WEB_APP_REV="52a271aefd496b5decf149eb7931d872f77d1cba" # chore(deps): bump the npm_and_yarn group across 1 directory with 9 updates
export WATCHER_REV="5fa1c9a4cbddf86f825f68885f04daee2910840c" # status: properly handle onshot services
export FIRMWARE_REV="f4c62886b6be028de142ec899a65210a3f7eeea7" # Median filter implemented with a window size of 50
export RAUC_REV="269e1721b3c5f6512f7dfb7fd19f9108515c2a98" # debian: Disable test building for now
export HAWKBIT_REV="3e5d03b5ab17784c5d920d8fdeeb05698f9074a1" # Add changes to repor download progress
export PSPLASH_REV="5b0085b559f1aac09c0a88f85f203ab332bbe1c9" # Replace baseimage with DOT image
export PLOTTER_UI_REV="ad394f46889317926ef319df50f7ffe4a790dc99" # Merge pull request #6 from MeticulousHome/feat/sort-and-zoom
