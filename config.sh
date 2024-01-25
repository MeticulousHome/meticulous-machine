#!/bin/bash

readonly COMPONENTS_DIR="components"
readonly ROOTFS_DIR="rootfs"
readonly SERVICES_DIR="system-services"

readonly DEBIAN_SRC_DIR=${COMPONENTS_DIR}/"debian"
readonly DEBIAN_GIT="https://github.com/FFFuego/debian-variscite-fika"
readonly DEBIAN_BRANCH="debian-bullseye"
readonly DEBIAN_REV="HEAD"

readonly BACKEND_SRC_DIR="${COMPONENTS_DIR}/meticulous-backend"
readonly BACKEND_GIT="https://github.com/FFFuego/backend_for_esp32/"
readonly BACKEND_BRANCH="dev"
readonly BACKEND_REV="HEAD"

readonly DIAL_SRC_DIR=${COMPONENTS_DIR}/"meticulous-dial"
readonly DIAL_GIT="https://github.com/FFFuego/meticulous-dial"
readonly DIAL_BRANCH="beta"
readonly DIAL_REV="HEAD"

readonly DASH_SRC_DIR=${COMPONENTS_DIR}/"meticulous-dashboard"
readonly DASH_GIT="https://github.com/ffFuego/meticulous-frontend"
readonly DASH_BRANCH="main"
readonly DASH_REV="HEAD"

readonly SYSTEM_PACKAGES="avahi-daemon"
readonly DEVELOPMENT_PACKAGES="git"
