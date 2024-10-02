#!/usr/bin/env bash
set -eo pipefail

source config.sh

function build_debian() {
    echo "Building debian"

    pushd $DEBIAN_SRC_DIR >/dev/null
    sudo ./var_make_debian.sh -c all
    popd >/dev/null
}

function repack_deb() {
    deb_package=$1
    echo "Unpacking package ${deb_package}"
    rm -f meticulous-ui.deb
    ar x ${deb_package}

    # Uncompress zstd files an re-compress them using xz
    echo "Repacking control.tar.zst"
    zstd -d <control.tar.zst | xz >control.tar.xz
    echo "Repacking data.tar.zst"
    du -sh data.tar.zst
    zstd -d <data.tar.zst | xz -0 | pv | cat >data.tar.xz

    # Re-create the Debian package
    echo "Repacking package"
    ar -m -c -a sdsd meticulous-ui.deb debian-binary control.tar.xz data.tar.xz
    # Clean up
    rm debian-binary control.tar.xz data.tar.xz control.tar.zst data.tar.zst
}

function build_dial() {
    echo "Building Dial app"
    pushd $DIAL_SRC_DIR >/dev/null
    export DPKG_DEB_COMPRESSOR_TYPE=xz
    rm -f out/make/deb/arm64/*.deb
    npm install
    npm run make -- --arch=arm64 --platform=linux

    pushd out/make/deb/arm64 >/dev/null
    contents=$(ar t meticulous-ui*_arm64.deb)
    if [[ $contents == *"control.tar.zst"* ]] && [[ $contents == *"data.tar.zst"* ]]; then
        echo "Compression is zstd. Archive needs to be repacked"
        repack_deb meticulous-ui*_arm64.deb
    else
        echo "Compression is xz or gzip. Archive can be used as is"
        cp meticulous-ui*_arm64.deb meticulous-ui.deb
    fi
    popd >/dev/null
    popd >/dev/null
}

function build_dash() {
    if [ -d $DASH_SRC_DIR ]; then
        echo "Building Dashboard app"
        pushd $DASH_SRC_DIR >/dev/null
        npm install
        npm run build
        popd >/dev/null
    else
        echo "Dashboard is not checked out. Skipping"
    fi
}

function build_web() {
    echo "Building WebApp"
    pushd $WEB_APP_SRC_DIR >/dev/null
    npm install
    npm run build
    popd >/dev/null
}

function build_firmware() {
    PLATFORMIO_FRAMEWORK="${HOME}/.platformio/packages/framework-arduinoespressif32"
    if [ -d $FIRMWARE_SRC_DIR ]; then
        echo "Building Firmware for ESP32 || FIKA_V6"
        pushd $FIRMWARE_SRC_DIR >/dev/null
        pio lib install

        pio run -e fika_latest-s1 -e fika_latest-s3
        popd >/dev/null

        mkdir -p ${FIRMWARE_OUT_DIR}/esp32
        cp -v ${PLATFORMIO_FRAMEWORK}/tools/partitions/boot_app0.bin ${FIRMWARE_OUT_DIR}/esp32/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s1/bootloader.bin ${FIRMWARE_OUT_DIR}/esp32/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s1/partitions.bin ${FIRMWARE_OUT_DIR}/esp32/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s1/firmware.bin ${FIRMWARE_OUT_DIR}/esp32/

        mkdir -p ${FIRMWARE_OUT_DIR}/esp32-s3
        cp -v ${PLATFORMIO_FRAMEWORK}/tools/partitions/boot_app0.bin ${FIRMWARE_OUT_DIR}/esp32-s3/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s3/bootloader.bin ${FIRMWARE_OUT_DIR}/esp32-s3/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s3/partitions.bin ${FIRMWARE_OUT_DIR}/esp32-s3/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s3/firmware.bin ${FIRMWARE_OUT_DIR}/esp32-s3/

    else
        echo "Firmware is not checked out. Skipping"
    fi
}


function build_history() {
    if [ -d $HISTORY_UI_SRC_DIR ]; then
        echo "Building HISTORY UI"
        pushd $HISTORY_UI_SRC_DIR >/dev/null
        npm install
        npm run build
        popd >/dev/null
    else
        echo "History UI is not checked out. Skipping"
    fi
}


# Function to display help text
show_help() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Run various build functions for Debian, Dial and Dashboard.

By default --all should be used to build all components.
Specific components can be build by passing their names as options.

Available options:
    --all                     Build all components
    --debian                  Build Debian
    --dial                    Build Dial application
    --dash | --dashboard      Build Dashboard application
    --web  | --webapp         Build WebApp application
    --firmware                Build ESP32 Firmware
    --history                 Build History UI
    --help                    Displays this help and exits

EOF
}

any_selected=0
all_selected=0
declare -A steps
steps=(
    [build_debian]=0
    [build_dial]=0
    [build_dash]=0
    [build_web]=0
    [build_firmware]=0
    [build_history]=0
)

# Parse command line arguments
for arg in "$@"; do
    case $arg in
    --debian) steps[build_debian]=1 ;;
    --dial) steps[build_dial]=1 ;;
    --dash) steps[build_dash]=1 ;;
    --dashboard) steps[build_dash]=1 ;;
    --web) steps[build_web]=1 ;;
    --webapp) steps[build_web]=1 ;;
    --firmware) steps[build_firmware]=1 ;;
    --history) steps[build_history]=1 ;;
    --help)
        show_help
        exit 0
        ;;
    # Enable all steps via special case
    --all) all_selected=1 ;;
    *)
        echo "Invalid option: $arg"
        show_help
        exit 1
        ;;
    esac
done

for key in "${!steps[@]}"; do
    if [ ${steps[$key]} -eq 1 ] ||
        [ $all_selected -eq 1 ]; then
        any_selected=1
        # Execute step
        $key
    fi
done

# print help if no step has been executed
if [ $any_selected -eq 0 ]; then
    show_help
fi
