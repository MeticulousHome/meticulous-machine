#!/bin/bash
set -eo pipefail

check_bash_version() {
    # Get the version of Bash
    local version=$(bash --version | awk '{print $4}')
    # Compare the version
    if [[ "$version" < "5.2" ]]; then
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

readonly COMPONENTS_DIR="components"
readonly ROOTFS_DIR="rootfs"
readonly SERVICES_DIR="system-services"
readonly RAUC_CONFIG_DIR="rauc-config"
readonly MISC_DIR="misc"

readonly RAUC_CERT="beta.rsa4096.cert.pem"

readonly LINUX_SRC_DIR=${COMPONENTS_DIR}/"linux"
readonly LINUX_BUILD_DIR=${COMPONENTS_DIR}/"linux-build"
readonly LINUX_GIT="git@github.com:MeticulousHome/linux-variscite-fika.git"
readonly LINUX_BRANCH="debian-5.15.60"
readonly LINUX_REV="HEAD"

readonly UBOOT_SRC_DIR=${COMPONENTS_DIR}/"bootloader/uboot"
readonly UBOOT_GIT="git@github.com:MeticulousHome/uboot-variscite-fika.git"
readonly UBOOT_BRANCH="v2022.04-imx-debian-5.15"
readonly UBOOT_REV="HEAD"

readonly ATF_SRC_DIR=${COMPONENTS_DIR}/"bootloader/imx-atf"
readonly ATF_GIT="https://github.com/varigit/imx-atf.git"
readonly ATF_BRANCH="imx_5.4.24_2.1.0_var01"
readonly ATF_REV="7575633e03ff952a18c0a2c0aa543dee793fda5f"

readonly IMX_MKIMAGE_SRC_DIR=${COMPONENTS_DIR}/"bootloader/imx-mkimage"
readonly IMX_MKIMAGE_GIT="https://github.com/nxp-imx/imx-mkimage.git"
readonly IMX_MKIMAGE_BRANCH="imx_5.4.24_2.1.0"
readonly IMX_MKIMAGE_REV="6745ccdcf15384891639b7ced3aa6ce938682365"

readonly IMX_BOOT_TOOLS_SRC_DIR=${COMPONENTS_DIR}/"bootloader/imx-boot-tools"
readonly BOOTLOADER_BUILD_DIR=${COMPONENTS_DIR}/"bootloader/build"

readonly DEBIAN_SRC_DIR=${COMPONENTS_DIR}/"debian"
readonly DEBIAN_GIT="git@github.com:MeticulousHome/debian-variscite-fika"
readonly DEBIAN_BRANCH="debian-bullseye"
readonly DEBIAN_REV="HEAD"

readonly BACKEND_SRC_DIR="${COMPONENTS_DIR}/meticulous-backend"
readonly BACKEND_GIT="git@github.com:MeticulousHome/backend_for_esp32/"
readonly BACKEND_BRANCH="mimoja_dev"
readonly BACKEND_REV="HEAD"

readonly DIAL_SRC_DIR="${COMPONENTS_DIR}/meticulous-dial"
readonly DIAL_GIT="git@github.com:MeticulousHome/meticulous-dial"
readonly DIAL_BRANCH="beta"
readonly DIAL_REV="HEAD"

readonly DASH_SRC_DIR="${COMPONENTS_DIR}/meticulous-dashboard"
readonly DASH_GIT="git@github.com:MeticulousHome/meticulous-frontend"
readonly DASH_BRANCH="mimoja_wip"
readonly DASH_REV="HEAD"

readonly WEB_APP_SRC_DIR="${COMPONENTS_DIR}/meticulous-web-app"
readonly WEB_APP_GIT="git@github.com:MeticulousHome/meticulous-web-app"
readonly WEB_APP_BRANCH="main"
readonly WEB_APP_REV="HEAD"

readonly WATCHER_SRC_DIR="${COMPONENTS_DIR}/meticulous-watcher"
readonly WATCHER_GIT="git@github.com:MeticulousHome/meticulous-watcher"
readonly WATCHER_BRANCH="main"
readonly WATCHER_REV="HEAD"

readonly FIRMWARE_SRC_DIR="${COMPONENTS_DIR}/meticulous-firmware"
readonly FIRMWARE_OUT_DIR="${COMPONENTS_DIR}/meticulous-firmware-build"
readonly FIRMWARE_GIT="git@github.com:MeticulousHome/flow_machine_firmware"
readonly FIRMWARE_BRANCH="dev"
readonly FIRMWARE_REV="HEAD"

readonly RAUC_SRC_DIR="${COMPONENTS_DIR}/rauc"
readonly RAUC_GIT="https://github.com/rauc/rauc.git"
readonly RAUC_BRANCH="master"
readonly RAUC_VERSION="1.12"
readonly RAUC_REV="v${RAUC_VERSION}"

readonly HAWKBIT_SRC_DIR="${COMPONENTS_DIR}/rauc-hawkbit-updater"
readonly HAWKBIT_GIT="https://github.com/MeticulousHome/rauc-hawkbit-updater.git"
readonly HAWKBIT_BRANCH="main"
readonly HAWKBIT_REV="HEAD"
# Manually set to the latest version, should be updated when the commit is updated
readonly HAWKBIT_VERSION="1.4-devel-${HAWKBIT_REV:0:8}"

readonly PIPER_VERSION="1.2.0"
readonly PIPER_URL="https://github.com/rhasspy/piper/releases/download/${PIPER_VERSION}/piper_arm64.tar.gz"
# For browsing use https://huggingface.co/rhasspy/piper-voices/tree/v1.0.0
readonly PIPER_VOICE_BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/"
readonly PIPER_SEMAINE="en/en_GB/semaine/medium/en_GB-semaine-medium.onnx"

readonly HISTORY_UI_SRC_DIR="${COMPONENTS_DIR}/meticulous-history-ui"
readonly HISTORY_UI_GIT="git@github.com:MeticulousHome/REL-Infinite-Shot-Test-UI"
readonly HISTORY_UI_BRANCH="main"
readonly HISTORY_UI_REV="HEAD"

readonly PLOTTER_UI_SRC_DIR="${COMPONENTS_DIR}/meticulous-plotter-ui"
readonly PLOTTER_UI_GIT="git@github.com:MeticulousHome/ProfilePlotter.git"
readonly PLOTTER_UI_BRANCH="main"
readonly PLOTTER_UI_REV="HEAD"

readonly SYSTEM_PACKAGES="parted avahi-daemon libgirepository1.0-dev libgstreamer-plugins-base1.0-dev gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 libsystemd-dev zstd nginx ssl-cert exfatprogs"
readonly DEVELOPMENT_PACKAGES="git rsync bash-completion"
readonly HOST_PACKAGES="\
    binfmt-support pv qemu-user-static debootstrap kpartx lvm2 dosfstools gpart\
    binutils git libncurses-dev python3-m2crypto gawk wget git-core diffstat unzip\
    texinfo gcc-aarch64-linux-gnu build-essential chrpath socat libsdl1.2-dev autoconf libtool\
    libglib2.0-dev libarchive-dev python3-git xterm sed cvs subversion coreutils\
    texi2html docbook-utils help2man make gcc g++ desktop-file-utils libgl1-mesa-dev\
    libglu1-mesa-dev mercurial automake groff curl lzop asciidoc u-boot-tools mtd-utils\
    libgnutls28-dev flex bison libssl-dev systemd-container pigz libcurl4-openssl-dev libgirepository1.0-dev
    bc python3 python3-venv wget curl"

readonly METIUCULOUS_ROOTFS=meticulous-rootfs.tar.gz
