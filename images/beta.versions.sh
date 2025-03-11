#!/bin/bash
export LINUX_GIT="git@github.com:MeticulousHome/linux-fika.git"
export LINUX_BRANCH="linux-6.12.y"
export HISTORY_UI_REV="452f6984333304c914554bf4470d42721a8e696c" # fix(config): conditionally set assetPrefix in Next.js config
export LINUX_REV="72eddaae8e07cd2d81b5140968072799092fed3b" # dts/freescale/meticulous: create proper rtc aliases
export UBOOT_REV="7fdc6b1de1358248e7743069ff335f4168228374" # Enable fastboot recovery on boot via recovery pin
export ATF_REV="7575633e03ff952a18c0a2c0aa543dee793fda5f" # imx: Fix multiple definition of ipc_handle
export IMX_MKIMAGE_REV="6745ccdcf15384891639b7ced3aa6ce938682365" # imx8m: Add script to generate SIT (secondary image table)
export DEBIAN_REV="465b6795ed771f1c79e0df9186e82db92dba7c43" # add xwayland
export BACKEND_REV="f2d2725b5092ed0f167cc27a4e944bf38d5b692a" # telemetry: use meticulous file upload service
export DIAL_REV="187c2a9ec0d275b27fe08b7180d46f41d2eba275" # chore(release): v1.59.0 [skip ci]
export WEB_APP_REV="52a271aefd496b5decf149eb7931d872f77d1cba" # chore(deps): bump the npm_and_yarn group across 1 directory with 9 updates
export WATCHER_REV="5fa1c9a4cbddf86f825f68885f04daee2910840c" # status: properly handle onshot services
export FIRMWARE_REV="d8a8e2c0cf03505472942b50193e5e70bdaac350" # fix: ACAIA master calibration start and exit
export RAUC_REV="269e1721b3c5f6512f7dfb7fd19f9108515c2a98" # debian: Disable test building for now
export HAWKBIT_REV="8ff265cba3334c8822a01bcff493dc5820486c86" # client: fix error printing statement
export PSPLASH_REV="5b0085b559f1aac09c0a88f85f203ab332bbe1c9" # Replace baseimage with DOT image
export PLOTTER_UI_REV="ad394f46889317926ef319df50f7ffe4a790dc99" # Merge pull request #6 from MeticulousHome/feat/sort-and-zoom
