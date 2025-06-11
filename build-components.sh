#!/usr/bin/env bash
set -eo pipefail

source config.sh

function build_debian() {
    echo "Building debian"

    pushd $DEBIAN_SRC_DIR >/dev/null
    sudo ./create_rootfs.sh
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

function build_web() {
    echo "Building WebApp"
    pushd $WEB_APP_SRC_DIR >/dev/null
    npm install
    npm run build
    popd >/dev/null
}

function build_uboot() {
    if [ ! -d $UBOOT_SRC_DIR ]; then
        echo "uboot is not checked out. Skipping"
        return
    fi

    echo -e "\033[1;32mBuilding Uboot\033[0m"
    if [ ! $(uname -m) == "aarch64" ]; then
        export CROSS_COMPILE="aarch64-linux-gnu-"
        export ARCH="arm64"
        echo -e "\033[1;32mSetting \033[1;34mCROSS_COMPILE=\033[1;35m${CROSS_COMPILE}\033[0m and \033[1;34mARCH=\033[1;35m${ARCH}\033[0m"
    fi
    pushd $UBOOT_SRC_DIR >/dev/null
    make mrproper
    make imx8mn_var_som_meticulous_defconfig
    make -j`nproc`

    popd >/dev/null
    pushd $ATF_SRC_DIR >/dev/null

	sed -i 's|ERRORS := -Werror|ERRORS := -Werror -Wno-error=array-bounds|' Makefile
	sed -i '/TF_LDFLAGS.*--gc-sections/a TF_LDFLAGS        +=      --no-warn-rwx-segment' Makefile

    LDFLAGS="" make PLAT=imx8mn bl31
    popd >/dev/null

    cp -v ${ATF_SRC_DIR}/build/imx8mn/release/bl31.bin ${IMX_MKIMAGE_SRC_DIR}/iMX8M/bl31.bin
	cp -v ${IMX_BOOT_TOOLS_SRC_DIR}/ddr4_imem_1d_201810.bin ${IMX_MKIMAGE_SRC_DIR}/iMX8M/ddr4_imem_1d_201810.bin
	cp -v ${IMX_BOOT_TOOLS_SRC_DIR}/ddr4_dmem_1d_201810.bin ${IMX_MKIMAGE_SRC_DIR}/iMX8M/ddr4_dmem_1d_201810.bin
	cp -v ${IMX_BOOT_TOOLS_SRC_DIR}/ddr4_imem_2d_201810.bin ${IMX_MKIMAGE_SRC_DIR}/iMX8M/ddr4_imem_2d_201810.bin
	cp -v ${IMX_BOOT_TOOLS_SRC_DIR}/ddr4_dmem_2d_201810.bin ${IMX_MKIMAGE_SRC_DIR}/iMX8M/ddr4_dmem_2d_201810.bin
	cp -v ${UBOOT_SRC_DIR}/u-boot.bin                               ${IMX_MKIMAGE_SRC_DIR}/iMX8M/
	cp -v ${UBOOT_SRC_DIR}/u-boot-nodtb.bin                         ${IMX_MKIMAGE_SRC_DIR}/iMX8M/
	cp -v ${UBOOT_SRC_DIR}/spl/u-boot-spl.bin                       ${IMX_MKIMAGE_SRC_DIR}/iMX8M/
	cp -v ${UBOOT_SRC_DIR}/arch/arm/dts/imx8mn-var-som-symphony.dtb ${IMX_MKIMAGE_SRC_DIR}/iMX8M/
    cp -v ${UBOOT_SRC_DIR}/tools/mkimage                            ${IMX_MKIMAGE_SRC_DIR}/iMX8M/mkimage_uboot

    # imx-mkimage needs to be patched for non-evk boards
    cp -v ${IMX_BOOT_TOOLS_SRC_DIR}/imx-boot/imx-mkimage-imx8m-soc.mak-add-var-som-imx8m-nano-support.patch ${IMX_MKIMAGE_SRC_DIR}
    pushd ${IMX_MKIMAGE_SRC_DIR}

    git checkout -f
    git apply imx-mkimage-imx8m-soc.mak-add-var-som-imx8m-nano-support.patch
	make SOC=iMX8MN dtbs=imx8mn-var-som-symphony.dtb flash_ddr4_evk

    popd >/dev/null

    mkdir -p ${BOOTLOADER_BUILD_DIR} || true
	cp -v ${IMX_MKIMAGE_SRC_DIR}/iMX8M/flash.bin ${BOOTLOADER_BUILD_DIR}/imx-boot-sd.bin
}


function build_kernel() {
    if [ ! -d $LINUX_SRC_DIR ]; then
        echo "Linux Kernel is not checked out. Skipping"
        return
    fi

    echo -e "\033[1;32mBuilding Linux Kernel\033[0m"

    mkdir -p ${LINUX_BUILD_DIR}
    rm -rf ${LINUX_BUILD_DIR}/*
    pushd $LINUX_SRC_DIR >/dev/null
    if [ ! $(uname -m) == "aarch64" ]; then
        export CROSS_COMPILE="aarch64-linux-gnu-"
        export ARCH="arm64"
        echo -e "\033[1;32mSetting \033[1;34mCROSS_COMPILE=\033[1;35m${CROSS_COMPILE}\033[0m and \033[1;34mARCH=\033[1;35m${ARCH}\033[0m"
    fi

    export DEBEMAIL="Mimoja <mimoja@meticuloushome.com>"
    export DPKG_DEB_COMPRESSOR_TYPE=xz
    export DEB_BUILD_OPTIONS="parallel=`nproc`"
    make mrproper
    make imx8_var_meticulous_defconfig
    make -j`nproc` Image modules dtbs
    make -j`nproc` bindeb-pkg
    popd >/dev/null

    mv -v ${COMPONENTS_DIR}/linux-*.deb ${LINUX_BUILD_DIR}/
    mv -v ${COMPONENTS_DIR}/linux-*.buildinfo ${LINUX_BUILD_DIR}/
    mv -v ${COMPONENTS_DIR}/linux-*.changes ${LINUX_BUILD_DIR}/

    echo -e "\033[1;32mBuilding out-of-tree mwifiex driver\033[0m"
    export KERNELDIR="$(pwd)/${LINUX_SRC_DIR}"

    pushd $MWIFIEX_SRC_DIR >/dev/null
    if [ ! $(uname -m) == "aarch64" ]; then
        export CROSS_COMPILE="aarch64-linux-gnu-"
        export ARCH="arm64"
        echo -e "\033[1;32mSetting \033[1;34mCROSS_COMPILE=\033[1;35m${CROSS_COMPILE}\033[0m and \033[1;34mARCH=\033[1;35m${ARCH}\033[0m"
    fi
    # patch the Makefile to use all cores
    sed -i 's/$(MAKE) -C/$(MAKE) -j`nproc` -C/' Makefile

    make build
    popd >/dev/null
    mv -v ${MWIFIEX_SRC_DIR}/bin_wlan ${LINUX_BUILD_DIR}/
}

function build_firmware() {
    PLATFORMIO_FRAMEWORK="${HOME}/.platformio/packages/framework-arduinoespressif32"
    if [ -d $FIRMWARE_SRC_DIR ]; then
        echo "Building Firmware for ESP32"
        pushd $FIRMWARE_SRC_DIR >/dev/null
        if [ $(uname -s) == "Darwin" ]; then
            pio pkg update
        fi

        pio run -e fika_latest-s3
        popd >/dev/null

        mkdir -p ${FIRMWARE_OUT_DIR}/esp32-s3
        cp -v ${PLATFORMIO_FRAMEWORK}/tools/partitions/boot_app0.bin ${FIRMWARE_OUT_DIR}/esp32-s3/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s3/bootloader.bin ${FIRMWARE_OUT_DIR}/esp32-s3/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s3/partitions.bin ${FIRMWARE_OUT_DIR}/esp32-s3/
        cp -v ${FIRMWARE_SRC_DIR}/.pio/build/fika_latest-s3/firmware.bin ${FIRMWARE_OUT_DIR}/esp32-s3/

    else
        echo "Firmware is not checked out. Skipping"
    fi
}

function build_plotter() {
    if [ -d $PLOTTER_UI_SRC_DIR ]; then
        echo "Building Plotter"
        pushd $PLOTTER_UI_SRC_DIR >/dev/null
        npm install
        npm run build
        popd >/dev/null
    else
        echo "Plotter is not checked out. Skipping"
    fi
}

function build_rauc() {
    echo "Building RAUC and Hawkbit Updater inside a container"

    # Build the rauc deb package for x86 and arm64
    echo "Building rauc deb package (arm64)..."
    docker run --platform arm64 --rm -v ./${RAUC_BUILD_DIR}:/debs -e CCACHE_DIR=/debs/.ccache -e DEBIAN_FRONTEND=noninteractive -v ./${RAUC_SRC_DIR}:/debs/workspace ${DOCKER_DEB_BUILER_IMAGE}:latest /bin/bash -c "\
        cd /debs/workspace && \
        git config --global --add safe.directory '*' && \
        mk-build-deps -r -i debian/control -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' && \
        dpkg-buildpackage -b -rfakeroot -us -uc"

    echo "Building rauc deb package (amd64)..."
    docker run --platform amd64 --rm -v ./${RAUC_BUILD_DIR}:/debs -e CCACHE_DIR=/debs/.ccache -e DEBIAN_FRONTEND=noninteractive  -v ./${RAUC_SRC_DIR}:/debs/workspace ${DOCKER_DEB_BUILER_IMAGE}:latest /bin/bash -c "\
        cd /debs/workspace && \
        git config --global --add safe.directory '*' && \
        mk-build-deps -r -i debian/control -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' && \
        dpkg-buildpackage -b -rfakeroot -us -uc"

    # Build the rauc-hawkbit-updater deb package for arm64 only
    echo "Building hawkbit updater deb package (arm64)..."
    docker run --platform arm64 --rm -v ./${RAUC_BUILD_DIR}:/debs -e CCACHE_DIR=/debs/.ccache -e DEBIAN_FRONTEND=noninteractive -v ./${HAWKBIT_SRC_DIR}:/debs/workspace ${DOCKER_DEB_BUILER_IMAGE}:latest /bin/bash -c "\
        cd /debs/workspace && \
        git config --global --add safe.directory '*' && \
        mk-build-deps -r -i debian/control -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' && \
        dpkg-buildpackage -b -rfakeroot -us -uc"
}

function build_psplash(){
    echo "Building psplash deb inside a container"

    docker run --platform arm64 --rm -v ./${PSPLASH_BUILD_DIR}:/debs -e CCACHE_DIR=/debs/.ccache -e DEBIAN_FRONTEND=noninteractive -v ./${PSPLASH_SRC_DIR}:/debs/workspace ${DOCKER_DEB_BUILER_IMAGE}:latest /bin/bash -c "\
        cd /debs/workspace && \
        git config --global --add safe.directory '*' && \
        mk-build-deps -r -i debian/control -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' && \
        dpkg-buildpackage -b -rfakeroot -us -uc"
}

function build_docker() {
    if ! docker buildx inspect meticulous-builder 2>&1 1>/dev/null; then
        docker buildx create --name meticulous-builder --driver docker-container --bootstrap
    fi
    # Docker currently does not support multi-platform builds for buildx
    docker buildx build --builder meticulous-builder --platform linux/arm64,linux/amd64 -t ${DOCKER_DEB_BUILER_IMAGE}:latest -f deb-builder.Dockerfile .
    # So we export the images separately
    docker build --platform linux/arm64 -t ${DOCKER_DEB_BUILER_IMAGE}:latest-arm64 -f deb-builder.Dockerfile .
    docker build --platform linux/amd64 -t ${DOCKER_DEB_BUILER_IMAGE}:latest-amd64 -f deb-builder.Dockerfile .
}

function build_crash_reporter() {
    if [ -d $CRASH_REPORTER_SRC_DIR ]; then
        echo "Building Crash Report"
        #build the Docker image
        docker build -t build-reporter "$CRASH_REPORTER_SRC_DIR"
        # run the container to build the binary
        # we must know the absolute path for the crash-reporter component directory to mount the volume
        echo "cwd: $(pwd)"
        sudo docker run --rm -v $(pwd)/$CRASH_REPORTER_SRC_DIR:/systemd-crash-reporter build-reporter
    else
        echo "Crash Reporter is not checked out. Skipping"
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
    --web  | --webapp         Build WebApp application
    --firmware                Build ESP32 Firmware
    --linux | --kernel        Build Linux Kernel
    --uboot | --bootloader    Build U-Boot
    --rauc                    Build RAUC and rauc-hawkbit-updater
    --docker                  Build Docker image for building debian packages (not intcluded in --all)
    --history                 Build History UI
    --psplash | --splash      Build psplash
    --crash                   Build systemd crash reporter for sentry
    --help                    Displays this help and exits

EOF
}

any_selected=0
docker_selected=0
all_selected=0
declare -A steps
steps=(
    [build_debian]=0
    [build_dial]=0
    [build_web]=0
    [build_firmware]=0
    [build_plotter]=0
    [build_kernel]=0
    [build_uboot]=0
    [build_rauc]=0
    [build_psplash]=0
    [build_crash_reporter]=0
)

# Parse command line arguments
for arg in "$@"; do
    case $arg in
    --debian) steps[build_debian]=1 ;;
    --dial) steps[build_dial]=1 ;;
    --web) steps[build_web]=1 ;;
    --webapp) steps[build_web]=1 ;;
    --firmware) steps[build_firmware]=1 ;;
    --plotter) steps[build_plotter]=1 ;;
    --kernel) steps[build_kernel]=1 ;;
    --linux) steps[build_kernel]=1 ;;
    --uboot) steps[build_uboot]=1 ;;
    --bootloader) steps[build_uboot]=1 ;;
    --rauc) steps[build_rauc]=1 ;;
    --docker) docker_selected=1 ;;
    --psplash) steps[build_psplash]=1 ;;
    --splash) steps[build_psplash]=1 ;;
    --crash) steps[build_crash_reporter]=1 ;;
    --crash-reporter) steps[build_crash_reporter]=1 ;;
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

if [ $docker_selected -eq 1 ]; then
    build_docker
    any_selected=1
fi

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
