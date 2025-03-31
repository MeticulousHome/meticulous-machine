#!/bin/bash

export DEBIAN_BRANCH="bookworm-mainline"
export DEBIAN_REV="HEAD"
export LINUX_BRANCH="linux-6.12.y"
export LINUX_REV="HEAD"
# export DIAL_REV="57c1ec775983b3b3213991378d106aaadaf3b9f8" # test changing screens to replicate the OOM error
export BACKEND_REV="bd9d83fef4213a407a203b3a68cc397504f52685" # backend working
export FIRMWARE_REV="ba8a4ac6d729fd034382099f848873cd3d28d199" # Added constants for external thermistors