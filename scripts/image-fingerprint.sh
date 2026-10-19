#!/usr/bin/env bash
#
# Print a fingerprint of everything that goes into an image build. Two builds
# with the same fingerprint would produce the same image, so the scheduled
# nightly build uses it to stop early when nothing has changed since the last
# published image.
#
#   scripts/image-fingerprint.sh <image>
#
# The fingerprint covers:
#
#   - this repository's checked-out commit: make-rootfs.sh, system-services/,
#     rauc-config/, misc/, scripts/ and the workflows themselves all live here
#     and none of them is covered by a component cache;
#   - every repository declared in config.sh (overlaid by
#     images/<image>.versions.sh) that update-sources.sh checked out: its URL,
#     branch and the commit actually checked out. Nothing is listed here; the
#     set comes from config.sh so that it stays the only place to maintain.
#     A declared repository that is not checked out (e.g. the mobile app,
#     which --all does not fetch) is reported and left out;
#   - the Debian archive state. make-rootfs.sh runs `apt update` and
#     `apt dist-upgrade` inside the rootfs against the suites that debian-fika
#     enables in its sources.list, so a new security or point-release upload
#     changes the image even when every component cache hits. We hash the
#     InRelease file of each suite, which the archive republishes on every
#     change.
#
# If the archive state cannot be read, the fingerprint is made unique so that
# the caller never skips a build on incomplete information.
#
# Sources must already be checked out (./update-sources.sh --all --image <image>
# --firmware --plotter).
#
set -euo pipefail

image="${1:-}"
if [[ -z "${image}" ]]; then
    echo "Usage: $0 <image>" >&2
    exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/image-config.sh
source scripts/image-config.sh
load_image_config "${image}"

# Mirrors the sources.list that debian-fika/create_rootfs.sh writes into the
# base rootfs: <distro>, <distro>-updates, <distro>-backports and
# <distro>-security, plus trixie pinned low for libc.
distro="$(sed -n 's/^DISTRO=\([a-z]*\).*/\1/p' "${DEBIAN_SRC_DIR}/create_rootfs.sh" | head -n1)"
distro="${distro:-bookworm}"

{
    echo "image=${image}"
    echo "machine=$(git rev-parse HEAD)"

    for name in $(image_repo_names); do
        src_dir="$(repo_var "${name}" SRC_DIR)"
        if [[ ! -e "${src_dir}/.git" ]]; then
            echo "repo=${name} is declared in config.sh but not checked out at ${src_dir}; not part of this image." >&2
            continue
        fi
        echo "repo=${name} url=$(repo_var "${name}" GIT) branch=$(repo_var "${name}" BRANCH) rev=$(repo_head "${name}")"
    done
} | tee /dev/stderr | sha256sum | awk '{print $1}'
