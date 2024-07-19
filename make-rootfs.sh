#!/bin/bash
set -eo pipefail

source config.sh

if (($EUID != 0)); then
    echo "Please run as root"
    exit
fi

function a_unpack_base() {
    if [ ! -f ${DEBIAN_SRC_DIR}/output/rootfs.tar.gz ]; then
        echo "#####################"
        echo "DEBIAN IMAGE DOES NOT EXIST!"
        echo "BUILDING NOW!"
        echo "#####################"
        bash build-components.sh --all
    fi

    mkdir -p ${ROOTFS_DIR}
    # Unpack the image that includes the packages for Variscite
    echo "Unpacking the debian image that includes packages for Variscite"
    rm -rf ${ROOTFS_DIR}/*
    pv ${DEBIAN_SRC_DIR}/output/rootfs.tar.gz | tar xz -C ${ROOTFS_DIR}

    #Install user packages if any
    echo "rootfs: install user defined packages (user-stage)"
    echo "rootfs: SYSTEM_PACKAGES \"${SYSTEM_PACKAGES}\" "
    echo "rootfs: DEVELOPMENT_PACKAGES \"${DEVELOPMENT_PACKAGES}\" "

    systemd-nspawn -D ${ROOTFS_DIR} apt update
    systemd-nspawn -D ${ROOTFS_DIR} apt install -y ${SYSTEM_PACKAGES} ${DEVELOPMENT_PACKAGES}

    echo "SystemMaxUse=1G" >>${ROOTFS_DIR}/etc/systemd/journald.conf
}

function copy_services() {

    # # Install meticulous services
    # install -m 0644 ${SERVICES_DIR}/meticulous-dial.service \
    #     ${ROOTFS_DIR}/lib/systemd/system
    # ln -s /lib/systemd/system/meticulous-dial.service \
    #     ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-dial.service

    # install -m 0644 ${SERVICES_DIR}/meticulous-backend.service \
    #     ${ROOTFS_DIR}/lib/systemd/system
    # ln -s /lib/systemd/system/meticulous-backend.service \
    #     ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-backend.service

    install -m 0644 ${SERVICES_DIR}/meticulous-watcher.service \
        ${ROOTFS_DIR}/lib/systemd/system
    ln -sf /lib/systemd/system/meticulous-watcher.service \
        ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-watcher.service

    install -m 0644 ${SERVICES_DIR}/meticulous-rauc.service \
        ${ROOTFS_DIR}/lib/systemd/system
    ln -sf /lib/systemd/system/meticulous-rauc.service \
        ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-rauc.service

    install -m 0644 ${SERVICES_DIR}/meticulous-brightness.service \
        ${ROOTFS_DIR}/lib/systemd/system
    ln -sf /lib/systemd/system/meticulous-brightness.service \
        ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-brightness.service

    install -m 0644 ${SERVICES_DIR}/meticulous-usb-current.service \
        ${ROOTFS_DIR}/lib/systemd/system
    ln -sf /lib/systemd/system/meticulous-usb-current.service \
        ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-usb-current.service

    install -m 0644 ${SERVICES_DIR}/rauc-hawkbit-updater.service \
        ${ROOTFS_DIR}/lib/systemd/system

    ln -sf /lib/systemd/system/rauc-hawkbit-updater.service \
        ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/rauc-hawkbit-updater.service

    ln -sf /lib/systemd/system/rauc.service \
        ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/rauc.service

}

function b_copy_components() {
    echo "Installing services"
    copy_services

    echo "Copying components into existing rootfs"
    # Install meticulous components
    # # Install Dial app
    # systemd-nspawn -D ${ROOTFS_DIR} --bind-ro "${DIAL_SRC_DIR}/out/make/deb/arm64/:/opt/meticulous-ui" bash -c "apt -y install --reinstall /opt/meticulous-ui/meticulous-ui.deb"

    # # Install Backend
    # echo "Installing Backend"
    # cp -r ${BACKEND_SRC_DIR} ${ROOTFS_DIR}/opt

    if [ -d $DASH_SRC_DIR ]; then
        # Install Dash
        echo "Installing Dash"
        cp -r ${DASH_SRC_DIR}/build ${ROOTFS_DIR}/opt/meticulous-dashboard
    fi
    # Install WebApp
    echo "Installing WebApp"
    cp -r ${WEB_APP_SRC_DIR}/out ${ROOTFS_DIR}/opt/meticulous-web-app

    # Install Watcher
    echo "Installing Watcher"
    cp -r ${WATCHER_SRC_DIR} ${ROOTFS_DIR}/opt

    # install python
    echo "Installing Python"
    tar xf misc/python3.12.tar.gz -C ${ROOTFS_DIR}

    # Reinstall pip3.12 as it is usually expecting python at the wrong location
    rm -rf ${ROOTFS_DIR}/usr/lib/python3.12/site-packages/pip*
    systemd-nspawn -D ${ROOTFS_DIR} bash -c "python3.12 -m ensurepip --upgrade --altinstall"
    systemd-nspawn -D ${ROOTFS_DIR} bash -c "python3.12 -m pip install --upgrade pip"

    echo "Creating python venv"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "python3.12 -m venv /opt/meticulous-venv"

    # Updating python3.12 pip, wheel and setuptools to latest versions
    echo "Installing python updates for pip, wheel and setuptools"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "/opt/meticulous-venv/bin/pip install --upgrade pip wheel setuptools"

    # # Install python requirements for meticulous
    # echo "Installing Backend dependencies"
    # systemd-nspawn -D ${ROOTFS_DIR} bash -lc "PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/vivante/pkgconfig /opt/meticulous-venv/bin/python3.12 -m pip install -r /opt/meticulous-backend/requirements.txt"

    # Install python requirements for meticulous
    echo "Installing Watcher dependencies"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "/opt/meticulous-venv/bin/python3.12 -m pip install -r /opt/meticulous-watcher/requirements.txt"

    # Install firmware if it exists on disk
    if [ -d $FIRMWARE_OUT_DIR ]; then
        echo "Installing Firmware"
        mkdir -p ${ROOTFS_DIR}/opt/meticulous-firmware
        cp -r $FIRMWARE_OUT_DIR/* ${ROOTFS_DIR}/opt/meticulous-firmware
    fi

    chown root:root ${ROOTFS_DIR}/opt/meticulous*

    echo "Installing RAUC config"

    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${MISC_DIR}:/opt/misc bash -c "apt install -y /opt/misc/rauc_${RAUC_VERSION}*.deb"
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${MISC_DIR}:/opt/misc bash -c "apt install -y /opt/misc/rauc-hawkbit-updater_${HAWKBIT_VERSION}*.deb"

    mkdir -p ${ROOTFS_DIR}/etc/rauc/
    cp -v ${RAUC_CONFIG_DIR}/system.conf ${ROOTFS_DIR}/etc/rauc/
    sed -i ${ROOTFS_DIR}/etc/rauc/system.conf -e "s/__KEYRING_CERT__/${RAUC_CERT}/g"
    cp -v ${RAUC_CONFIG_DIR}/*.cert.pem ${ROOTFS_DIR}/etc/rauc/
    cp -v ${RAUC_CONFIG_DIR}/update_OS.sh ${ROOTFS_DIR}/opt
    chmod +rx ${ROOTFS_DIR}/opt/update_OS.sh
    mkdir -p ${ROOTFS_DIR}/etc/hawkbit
    cp -v ${RAUC_CONFIG_DIR}/hawkbit-config.conf.template ${ROOTFS_DIR}/etc/hawkbit/config.conf.template
    echo "stable" >${ROOTFS_DIR}/etc/hawkbit/channel

    echo "Installing EMMC fstab"
    cp -v ${RAUC_CONFIG_DIR}/fstab_emmc ${ROOTFS_DIR}/etc/fstab

    echo "Cleaning"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "rm -rf /root/.cache"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "python3.12 -m pip cache purge"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "apt purge imx-gpu-sdk-gles2 imx-gpu-sdk-gles3 -y"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "apt autoclean -y"
}

function c_pack_tar() {

    echo "Packing tarball from folder ${ROOTFS_DIR}"
    chown root:root ${ROOTFS_DIR}
    OUTPUT_TARBAL=$(pwd)/meticulous-rootfs.tar.gz
    echo "Remove old tarball ${OUTPUT_TARBAL}"
    rm -f ${OUTPUT_TARBAL}
    pushd ${ROOTFS_DIR} >/dev/null
    echo "Compressing image"
    tar cf ${OUTPUT_TARBAL} . -I pigz
    popd >/dev/null

}

# Function to display help text
show_help() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Run various build functions for Debian, Dial and Dashboard.

By default --all should be used to build all components.
Specific components can be build by passing their names as options.

Available options:
    --all                     Execute all of the following steps
    --clean                   Clean the rootfs folder and start with a cleaned debian image
    --components              Update all components
    --tar                     Compress rootfs into a tarbal
    --help                    Displays this help and exits

EOF
}

any_selected=0
all_selected=0

declare -A steps
steps=(
    [a_unpack_base]=0
    [b_copy_components]=0
    [c_pack_tar]=0
)

# Parse command line arguments
for arg in "$@"; do
    case $arg in
    --clean) steps[a_unpack_base]=1 ;;
    --components) steps[b_copy_components]=1 ;;
    --tar) steps[c_pack_tar]=1 ;;
    --help)
        show_help
        exit 0
        ;;
    # Enable all steps via special case
    --all)
        all_selected=1
        steps[a_unpack_base]=1
        steps[b_copy_components]=1
        steps[c_pack_tar]=1
        ;;
    *)
        echo "Invalid option: $arg"
        show_help
        exit 1
        ;;
    esac
done

for key in a_unpack_base b_copy_components c_pack_tar; do
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
