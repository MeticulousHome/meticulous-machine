#!/bin/bash
export LINUX_REV="6f608ff142f57adb913c85e69686b022515215d8" # dtbs/freescale: add support for imx8mn-var-som v2
export UBOOT_REV="2c150b3d75bc249ae523c5995f2246a5a200fe16" # config:_Enable GPIO read command
export ATF_REV="723c01ee4903cbce4b4d43e84ad41fbb6385e578" # [RND-1518] plat: imx8m: Add 1336mts frequency config on imx8m
export IMX_MKIMAGE_REV="6745ccdcf15384891639b7ced3aa6ce938682365" # imx8m: Add script to generate SIT (secondary image table)
export DEBIAN_REV="4b66ca7f66e50de28e85bb4d9a11aadd487153eb" # packages: include e2fsprogs
export BACKEND_REV="a3894cbfcc3b973358e692b3d6da895feaf91cd4" # chore: remove sentry testing leftovers
export DIAL_REV="8cad261db7a5fd627155c77aed316d34a2411531" # feat(tauri): display window decorations when developing
export WEB_APP_REV="f16041429cf38a7dbaf288503a42487e3dee8edf" # fix(api): dont add http in front of https urls
export WATCHER_REV="311cf70eb04273e474769256a0e2a62eb3ffe93b" # logs: fix datetime handling
export FIRMWARE_REV="d41b9b6944ccf2398e68cbe73d0a85d7f43d1c3b" # account for previous flag switch that reduced semi cycles ON by half
export RAUC_REV="269e1721b3c5f6512f7dfb7fd19f9108515c2a98" # debian: Disable test building for now
export HAWKBIT_REV="60f34c8cdd0dbad3b97373080e642478724bfc30" # fix: Take into account partial download size
export PSPLASH_REV="5b0085b559f1aac09c0a88f85f203ab332bbe1c9" # Replace baseimage with DOT image
export PLOTTER_UI_REV="3885ee11275b8e2fdf44b0262430cf33a00f6ad6" # chore: run formatter
export CRASH_REPORTER_REV="9c377cac4a53ecbf8a4345fbaad56060be166ebf" # run cargo fmt
