#!/bin/bash
# Light mode POC: the components with a feat/light-mode-poc branch follow its head,
# everything else keeps the nightly defaults of config.sh.
export LINUX_BRANCH="feat/light-mode-poc"
export LINUX_REV="HEAD" # drivers/video/logo: light Meticulous logo for meticulous.theme=light
export BACKEND_BRANCH="feat/light-mode-poc"
export BACKEND_REV="HEAD" # feat(settings): add the Dial's theme setting
export DIAL_BRANCH="feat/light-mode-poc"
export DIAL_REV="HEAD" # feat(qt): keep the boot splash's theme equal to the Dial's
export PSPLASH_BRANCH="feat/light-mode-poc"
export PSPLASH_REV="HEAD" # psplash: light theme, picked from the Dial's boot theme file
