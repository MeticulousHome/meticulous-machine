#!/usr/bin/env bash
#
# Print the actions/cache key for one image component.
#
#   scripts/component-cache-key.sh <component> [<image>]
#
# Each component is built from one or more repositories declared in config.sh
# (overlaid by images/<image>.versions.sh). The key is derived from the commit
# checked out in each of those repositories, so a component is rebuilt exactly
# when one of its inputs moves, and a promotion that re-points a branch at the
# same commit keeps hitting the cache. Which repositories make up a component
# mirrors the update_<component> functions in update-sources.sh; where they
# live, and which branch/rev they track, comes only from config.sh.
#
# The debian base tarball additionally keys on the trixie archive version:
# base-files is pinned to trixie for libc and rewrites os-release, so a
# tarball cached across a Debian point release would get its os-release
# clobbered by the next dist-upgrade.
#
# Sources must already be checked out (./update-sources.sh --<component>).
#
set -euo pipefail

component="${1:-}"
image="${2:-}"
if [[ -z "${component}" ]]; then
    echo "Usage: $0 <component> [<image>]" >&2
    exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/image-config.sh
source scripts/image-config.sh
load_image_config "${image}"

# Component -> config.sh repository names, as update-sources.sh groups them.
case "${component}" in
    linux)          repos=(LINUX MWIFIEX MLANUTL) ;;
    bootloader)     repos=(UBOOT ATF IMX_MKIMAGE) ;;
    debian)         repos=(DEBIAN) ;;
    psplash)        repos=(PSPLASH) ;;
    rauc)           repos=(RAUC HAWKBIT) ;;
    dial)           repos=(DIAL) ;;
    web)            repos=(WEB_APP) ;;
    firmware)       repos=(FIRMWARE) ;;
    plotter)        repos=(PLOTTER_UI) ;;
    crash-reporter) repos=(CRASH_REPORTER) ;;
    backend)        repos=(BACKEND) ;;
    watcher)        repos=(WATCHER) ;;
    *)
        echo "Unknown component '${component}'" >&2
        exit 1
        ;;
esac

parts=()
for name in "${repos[@]}"; do
    parts+=("$(repo_head "${name}")")
done

case "${component}" in
    bootloader)
        # The boot image also embeds files kept in this repository.
        parts+=("$(git rev-parse "HEAD:${IMX_BOOT_TOOLS_SRC_DIR}")" "$(git rev-parse HEAD:rauc-config/u-boot.cmd)")
        ;;
    debian)
        trixie_version="$(curl -fsSL --max-time 30 https://deb.debian.org/debian/dists/trixie/InRelease | awk '/^Version:/ && !v {v=$2} END{print v}' || true)"
        if [[ -z "${trixie_version}" ]]; then
            # If the archive is unreachable, fall back to a monthly bucket: worst
            # case one spurious rebuild, never a silently stale key.
            trixie_version="unknown-$(date +%Y%m)"
        fi
        parts+=("trixie${trixie_version}")
        ;;
esac

IFS=- ; echo "${component}-build-${parts[*]}"
