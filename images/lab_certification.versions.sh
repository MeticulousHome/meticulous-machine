#!/bin/bash

# Preserve the component sources recorded by 2026M1418-lab_certification.
# Rebuilding the NAT fix must not pull unrelated changes from nightly branches.
# Baseline: https://github.com/MeticulousHome/meticulous-machine/actions/runs/35049430671

export LINUX_REV="9e14e4a6eb19f16722d7cb7e4c1afd635f8dad91"
export UBOOT_REV="00ba0da24a8b4a5b5d5e9ec56ebf92c8d1b055d0"
export ATF_REV="bed39c167c883b335d5fc1046ce16e10a611b4c4"
export IMX_MKIMAGE_REV="71b8c18af93a5eb972d80fbec290006066cff24f"
export DEBIAN_REV="db279cf0c71d35b1a9930699bca0446414390549"

export BACKEND_BRANCH="lab-certification-controls"
export BACKEND_REV="5f6bd076c51321b88a12aa6565e4fb87ac9f7849"

export DIAL_BRANCH="lab-certification-controls"
export DIAL_REV="c595bcdaaf80cf0104ac4bef5ad8b6b3f79c1559"

export WEB_APP_REV="260b14a68d3e8c6c4c2546a5b54d759b93138091"
export WATCHER_REV="72a7129e89b65d93a1072ec35b0a11f0b4077201"
export FIRMWARE_REV="b4c20ef8227a930041c00fedf803a0731d614785"
export RAUC_REV="269e1721b3c5f6512f7dfb7fd19f9108515c2a98"
export HAWKBIT_REV="60f34c8cdd0dbad3b97373080e642478724bfc30"
export PSPLASH_REV="5b0085b559f1aac09c0a88f85f203ab332bbe1c9"
export PLOTTER_UI_REV="202629e4d8b0a8692e31bbf483e4ed626c45e825"
export CRASH_REPORTER_REV="7f6a2a6be04e75c4ff163363117330886a32e8f4"
