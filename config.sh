#!/bin/bash
set -eo pipefail

readonly COMPONENTS_DIR="components"
readonly ROOTFS_DIR="rootfs"
readonly SERVICES_DIR="system-services"

readonly DEBIAN_SRC_DIR=${COMPONENTS_DIR}/"debian"
readonly DEBIAN_GIT="git@github.com:FFFuego/debian-variscite-fika"
readonly DEBIAN_BRANCH="debian-bullseye"
readonly DEBIAN_REV="HEAD"

readonly BACKEND_SRC_DIR="${COMPONENTS_DIR}/meticulous-backend"
readonly BACKEND_GIT="git@github.com:FFFuego/backend_for_esp32/"
readonly BACKEND_BRANCH="dev"
readonly BACKEND_REV="HEAD"

readonly DIAL_SRC_DIR="${COMPONENTS_DIR}/meticulous-dial"
readonly DIAL_GIT="git@github.com:FFFuego/meticulous-dial"
readonly DIAL_BRANCH="beta"
readonly DIAL_REV="HEAD"

readonly DASH_SRC_DIR="${COMPONENTS_DIR}/meticulous-dashboard"
readonly DASH_GIT="git@github.com:FFFuego/meticulous-frontend"
readonly DASH_BRANCH="main"
readonly DASH_REV="HEAD"

readonly WATCHER_SRC_DIR="${COMPONENTS_DIR}/meticulous-watcher"
readonly WATCHER_GIT="git@github.com:FFFuego/meticulous-watcher"
readonly WATCHER_BRANCH="mimoja_dev"
readonly WATCHER_REV="HEAD"


readonly SYSTEM_PACKAGES="avahi-daemon rauc rauc-service"
readonly DEVELOPMENT_PACKAGES="git rsync bash-completion"
readonly HOST_PACKAGES="\
    binfmt-support pv qemu-user-static debootstrap kpartx lvm2 dosfstools gpart\
    binutils git libncurses-dev python3-m2crypto gawk wget git-core diffstat unzip\
    texinfo gcc-multilib build-essential chrpath socat libsdl1.2-dev autoconf libtool\
    libglib2.0-dev libarchive-dev python3-git xterm sed cvs subversion coreutils\
    texi2html docbook-utils help2man make gcc g++ desktop-file-utils libgl1-mesa-dev\
    libglu1-mesa-dev mercurial automake groff curl lzop asciidoc u-boot-tools mtd-utils\
    libgnutls28-dev flex bison libssl-dev systemd-container"
