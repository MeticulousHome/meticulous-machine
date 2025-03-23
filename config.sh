#!/bin/bash

readonly PINNING_FILE="config_versions.sh"

if [ -f ${PINNING_FILE} ]; then
    echo "Using pinned versions from ${PINNING_FILE}"
    source ${PINNING_FILE}
fi

check_bash_version() {
    # Get the version of Bash
    local version=$(bash --version | awk '{print $4}')
    # Compare the version
    if [[ "$version" < "5.0" ]]; then
        echo "Error: Bash version $version is less than 5.2."
        echo "Please update Bash or change your PATH to point to a newer version."
        echo "For macOS, you can install a newer version using Homebrew:"
        echo "  brew install bash"
        echo "Then add the following to your ~/.profile or run manually"
        echo '  export PATH=/opt/homebrew/bin/:$PATH'
        exit 1
    fi
}

check_bash_version

old_flags=$-

set +e

readonly DOCKER_DEB_BUILER_IMAGE="ghcr.io/meticuloushome/meticulous-deb-builder"

readonly COMPONENTS_DIR="components"
readonly ROOTFS_DIR="rootfs"
readonly SERVICES_DIR="system-services"
readonly RAUC_CONFIG_DIR="rauc-config"
readonly MISC_DIR="misc"

readonly RAUC_CERT="beta.rsa4096.cert.pem"

readonly LINUX_SRC_DIR=${COMPONENTS_DIR}/"linux"
readonly LINUX_BUILD_DIR=${COMPONENTS_DIR}/"linux-build"
export   LINUX_GIT="git@github.com:MeticulousHome/linux-fika.git"
export   LINUX_BRANCH="linux-6.12.y"
export   LINUX_REV="HEAD"

readonly UBOOT_SRC_DIR=${COMPONENTS_DIR}/"bootloader/uboot"
readonly UBOOT_GIT="git@github.com:MeticulousHome/uboot-variscite-fika.git"
export   UBOOT_BRANCH="v2022.04-imx-debian-5.15"
export   UBOOT_REV="HEAD"

readonly ATF_SRC_DIR=${COMPONENTS_DIR}/"bootloader/imx-atf"
readonly ATF_GIT="https://github.com/varigit/imx-atf.git"

export ATF_BRANCH="imx_5.4.24_2.1.0_var01"
export ATF_REV="7575633e03ff952a18c0a2c0aa543dee793fda5f"

readonly IMX_MKIMAGE_SRC_DIR=${COMPONENTS_DIR}/"bootloader/imx-mkimage"
readonly IMX_MKIMAGE_GIT="https://github.com/nxp-imx/imx-mkimage.git"
export   IMX_MKIMAGE_BRANCH="imx_5.4.24_2.1.0"
export   IMX_MKIMAGE_REV="6745ccdcf15384891639b7ced3aa6ce938682365"

readonly IMX_BOOT_TOOLS_SRC_DIR=${COMPONENTS_DIR}/"bootloader/imx-boot-tools"
readonly BOOTLOADER_BUILD_DIR=${COMPONENTS_DIR}/"bootloader/build"

readonly DEBIAN_SRC_DIR=${COMPONENTS_DIR}/"debian-base"
export   DEBIAN_GIT="git@github.com:MeticulousHome/debian-fika"
export   DEBIAN_BRANCH="bookworm-mainline"
export   DEBIAN_REV="HEAD"

readonly BACKEND_SRC_DIR="${COMPONENTS_DIR}/meticulous-backend"
export   BACKEND_GIT="git@github.com:MeticulousHome/meticulous-backend.git"
export   BACKEND_BRANCH="main"
export   BACKEND_REV="HEAD"

readonly DIAL_SRC_DIR="${COMPONENTS_DIR}/meticulous-dial"
readonly DIAL_GIT="git@github.com:MeticulousHome/meticulous-dial"
export   DIAL_BRANCH="beta"
export   DIAL_REV="HEAD"

readonly DASH_SRC_DIR="${COMPONENTS_DIR}/meticulous-dashboard"
readonly DASH_GIT="git@github.com:MeticulousHome/meticulous-frontend"
export   DASH_BRANCH="mimoja_wip"
export   DASH_REV="HEAD"

readonly WEB_APP_SRC_DIR="${COMPONENTS_DIR}/meticulous-web-app"
readonly WEB_APP_GIT="git@github.com:MeticulousHome/meticulous-web-app"
export   WEB_APP_BRANCH="main"
export   WEB_APP_REV="HEAD"

readonly WATCHER_SRC_DIR="${COMPONENTS_DIR}/meticulous-watcher"
readonly WATCHER_GIT="git@github.com:MeticulousHome/meticulous-watcher"
export   WATCHER_BRANCH="main"
export   WATCHER_REV="HEAD"

readonly FIRMWARE_SRC_DIR="${COMPONENTS_DIR}/meticulous-firmware"
readonly FIRMWARE_OUT_DIR="${COMPONENTS_DIR}/meticulous-firmware-build"
readonly FIRMWARE_GIT="git@github.com:MeticulousHome/flow_machine_firmware"
export   FIRMWARE_BRANCH="dev"
export   FIRMWARE_REV="HEAD"

readonly RAUC_SRC_DIR="${COMPONENTS_DIR}/rauc/rauc"
readonly RAUC_GIT="https://github.com/MeticulousHome/rauc-deb"
export   RAUC_BRANCH="bookworm-1.12"
export   RAUC_VERSION="1.12"
export   RAUC_REV="HEAD"

readonly HAWKBIT_SRC_DIR="${COMPONENTS_DIR}/rauc/rauc-hawkbit-updater"
readonly HAWKBIT_GIT="https://github.com/MeticulousHome/rauc-hawkbit-updater.git"
export   HAWKBIT_BRANCH="main"
export   HAWKBIT_REV="HEAD"
# Manually set to the latest version, should be updated when the commit is updated
export   HAWKBIT_VERSION="1.4-devel-meticulous-$(date +'%Y-%m-%d_%H-%M-%S')"

readonly RAUC_BUILD_DIR="${COMPONENTS_DIR}/rauc/build"

readonly PSPLASH_SRC_DIR="${COMPONENTS_DIR}/psplash"
readonly PSPLASH_GIT="https://github.com/MeticulousHome/psplash"
readonly PSPLASH_BUILD_DIR="${COMPONENTS_DIR}/psplash-build"
export   PSPLASH_BRANCH="main"
export   PSPLASH_REV="HEAD"

readonly PIPER_VERSION="1.2.0"
readonly PIPER_URL="https://github.com/rhasspy/piper/releases/download/${PIPER_VERSION}/piper_arm64.tar.gz"
# For browsing use https://huggingface.co/rhasspy/piper-voices/tree/v1.0.0
readonly PIPER_VOICE_BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/"
readonly PIPER_SEMAINE="en/en_GB/semaine/medium/en_GB-semaine-medium.onnx"

readonly PLOTTER_UI_SRC_DIR="${COMPONENTS_DIR}/meticulous-plotter-ui"
readonly PLOTTER_UI_GIT="git@github.com:MeticulousHome/ProfilePlotter.git"
export   PLOTTER_UI_BRANCH="main"
export   PLOTTER_UI_REV="HEAD"

readonly SYSTEM_PACKAGES="parted avahi-daemon gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 zstd nginx ssl-cert exfatprogs dnsmasq iptables-persistent gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good alembic chrony"
readonly DEVELOPMENT_PACKAGES="git rsync bash-completion"
readonly HOST_PACKAGES="\
    binfmt-support pv qemu-user-static debootstrap kpartx lvm2 dosfstools gpart\
    binutils git libncurses-dev python3-m2crypto gawk wget git-core diffstat unzip\
    texinfo gcc-aarch64-linux-gnu build-essential chrpath socat libsdl1.2-dev autoconf libtool\
    libglib2.0-dev libarchive-dev python3-git xterm sed cvs subversion coreutils\
    texi2html docbook-utils help2man make gcc g++ desktop-file-utils libgl1-mesa-dev\
    libglu1-mesa-dev mercurial automake groff curl lzop asciidoc u-boot-tools mtd-utils\
    libgnutls28-dev flex bison libssl-dev systemd-container pigz libcurl4-openssl-dev libgirepository1.0-dev
    bc python3 python3-venv wget curl debhelper-compat libelf-dev"

readonly METIUCULOUS_ROOTFS=meticulous-rootfs.tar.gz

[[ $old_flags == *e* ]] && set -e
