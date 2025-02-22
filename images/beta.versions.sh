#!/bin/bash
export LINUX_GIT="git@github.com:MeticulousHome/linux-fika.git"
export LINUX_BRANCH="linux-6.12.y"
export LINUX_REV="2e9d63be6eef51ecfdfa2bbd702a959d621b9a3f" # dts/freescale/meticulous: add sound controller
export UBOOT_REV="7fdc6b1de1358248e7743069ff335f4168228374" # Enable fastboot recovery on boot via recovery pin
export ATF_REV="7575633e03ff952a18c0a2c0aa543dee793fda5f" # imx: Fix multiple definition of ipc_handle
export IMX_MKIMAGE_REV="6745ccdcf15384891639b7ced3aa6ce938682365" # imx8m: Add script to generate SIT (secondary image table)
export DEBIAN_REV="5a8ab75ead8640a3ad513ea1246f07cfae92f64a" # packages: add xwayland to installation base
export BACKEND_REV="e85fdbb147add01639b2faf2d8a21ed96ef3bb8d" # log: Improve logging organization by moving log statements to their source functions
export DIAL_REV="abe3a166a6c579e1706fec353289055d9c072b1e" # chore(release): v1.44.0 [skip ci]
export WEB_APP_REV="52a271aefd496b5decf149eb7931d872f77d1cba" # chore(deps): bump the npm_and_yarn group across 1 directory with 9 updates
export WATCHER_REV="2a8c95768707594c86100fb4bf9fc2527865d077" # Merge pull request #6 from Octavio2121/notify
export FIRMWARE_REV="ee3fa40e39b3227e64223c2f5393b015327c84ba" # Patch Purge Profile
export RAUC_REV="269e1721b3c5f6512f7dfb7fd19f9108515c2a98" # debian: Disable test building for now
export HAWKBIT_REV="dcd2e794d959ae916e39820547babeb597216fab" # Comment translated
export PSPLASH_REV="5b0085b559f1aac09c0a88f85f203ab332bbe1c9" # Replace baseimage with DOT image
export HISTORY_UI_REV="452f6984333304c914554bf4470d42721a8e696c" # fix(config): conditionally set assetPrefix in Next.js config
export PLOTTER_UI_REV="ad394f46889317926ef319df50f7ffe4a790dc99" # Merge pull request #6 from MeticulousHome/feat/sort-and-zoom
