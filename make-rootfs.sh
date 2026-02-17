#!/usr/bin/env bash
set -eo pipefail

source config.sh

if (($EUID != 0)); then
    echo "Please run as root"
    exit
fi

function a_unpack_base() {
    if [ ! -f ${DEBIAN_SRC_DIR}/rootfs-base.tar.gz ]; then
        echo "#####################"
        echo "DEBIAN IMAGE DOES NOT EXIST!"
        echo "#####################"
        find ${DEBIAN_SRC_DIR} -type f
        exit 1
    fi

    mkdir -p ${ROOTFS_DIR}
    # Unpack the image that includes the packages for Variscite
    echo "Unpacking the debian base image"
    rm -rf ${ROOTFS_DIR}/*
    pv ${DEBIAN_SRC_DIR}/rootfs-base.tar.gz | tar xz -C ${ROOTFS_DIR}
}

function copy_services() {

    rm -f ${ROOTFS_DIR}/lib/systemd/system/rauc-hawkbit-updater.service

    # Install meticulous services
    cp -v ${SERVICES_DIR}/* ${ROOTFS_DIR}/lib/systemd/system
    for service in ${SERVICES_DIR}/*; do
        service_name=$(basename ${service})
        ln -sfv /lib/systemd/system/${service_name} \
            ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/${service_name}
    done
}

function b_copy_components() {

    echo "Copying components into existing rootfs"

    echo "Installing config files"
    cp -Rv config/* ${ROOTFS_DIR}/etc/

    #Install user packages if any
    echo "rootfs: install user defined packages (user-stage)"
    echo "rootfs: SYSTEM_PACKAGES \"${SYSTEM_PACKAGES}\" "
    echo "rootfs: DEVELOPMENT_PACKAGES \"${DEVELOPMENT_PACKAGES}\" "

    systemd-nspawn -D ${ROOTFS_DIR} apt update
    systemd-nspawn -D ${ROOTFS_DIR} -E DEBIAN_FRONTEND=noninteractive apt dist-upgrade -y
    systemd-nspawn -D ${ROOTFS_DIR} -E DEBIAN_FRONTEND=noninteractive apt install -y -o Debug::pkgProblemResolver=yes ${SYSTEM_PACKAGES} ${DEVELOPMENT_PACKAGES}

    echo "Installing scripts"
    cp -Rv scripts/* ${ROOTFS_DIR}/usr/local/bin/

    echo "Installing services"
    copy_services

    echo "Enableing remote journald access"
    systemd-nspawn -D ${ROOTFS_DIR} bash -c "systemctl enable systemd-journal-remote"

    # Install Crash Reporter
    echo "Installing Crash reporter"
    cp -r ${CRASH_REPORTER_SRC_DIR}/target/aarch64-unknown-linux-gnu/release/crash-reporter ${ROOTFS_DIR}/opt/meticulous-crash-reporter
    chmod u+x ${ROOTFS_DIR}/opt/meticulous-crash-reporter

    # Install meticulous components
    # Install Dial app
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro "${DIAL_SRC_DIR}/src-tauri/target/aarch64-unknown-linux-gnu/release/bundle/deb/:/opt/meticulous-dial" bash -c "apt -y install --reinstall --no-install-recommends /opt/meticulous-dial/meticulous-dial.deb"

    # Install Backend
    echo "Installing Backend"
    cp -r ${BACKEND_SRC_DIR} ${ROOTFS_DIR}/opt

    if [ -d ${DASH_SRC_DIR}/build ]; then
        # Install Dash
        echo "Installing Dash"
        cp -r ${DASH_SRC_DIR}/build ${ROOTFS_DIR}/opt/meticulous-dashboard
    fi

    # Install WebApp
    echo "Installing WebApp"
    cp -r ${WEB_APP_SRC_DIR}/out ${ROOTFS_DIR}/opt/meticulous-web-app

    # Install Plotter UI
    if [ -d ${PLOTTER_UI_SRC_DIR}/build ]; then
        echo "Installing Plotter UI"
        cp -r ${PLOTTER_UI_SRC_DIR}/build ${ROOTFS_DIR}/opt/meticulous-plotter-ui
    fi

    # Install Watcher
    echo "Installing Watcher"
    cp -r ${WATCHER_SRC_DIR} ${ROOTFS_DIR}/opt

    echo "Creating python venv"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "apt install -y \
                                                python3 \
                                                python3-bleak \
                                                python3-cairo \
                                                python3-dbus-next \
                                                python3-gi \
                                                python3-setuptools \
                                                python3-parted \
                                                python3-systemd \
                                                python3-venv \
                                                python3-wheel"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "python3 -m venv --system-site-packages /opt/meticulous-venv"

    # Updating pip, wheel and setuptools to latest versions
    echo "Installing python updates for pip, wheel and setuptools"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "/opt/meticulous-venv/bin/pip install --upgrade pip"

    # Install python requirements for meticulous
    echo "Installing Backend dependencies"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "/opt/meticulous-venv/bin/pip install -r /opt/meticulous-backend/requirements.txt"

    # Install python requirements for meticulous
    echo "Installing Watcher dependencies"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "/opt/meticulous-venv/bin/pip install -r /opt/meticulous-watcher/requirements.txt"

    # Install firmware if it exists on disk
    if [ -d $FIRMWARE_OUT_DIR ]; then
        echo "Installing ESP32 Firmware"
        mkdir -p ${ROOTFS_DIR}/opt/meticulous-firmware
        cp -r $FIRMWARE_OUT_DIR/* ${ROOTFS_DIR}/opt/meticulous-firmware
    fi

    chown root:root ${ROOTFS_DIR}/opt/meticulous*

    echo "Installing config files"
    cp -Rv config/* ${ROOTFS_DIR}/

    echo "Installing RAUC config"
    export LATEST_RAUC=$(ls -Art ${RAUC_BUILD_DIR}/rauc_*_arm64.deb | tail -n 1)
    export LATEST_RAUC_SERVICE=$(ls -Art ${RAUC_BUILD_DIR}/rauc-service_*_all.deb | tail -n 1)
    export LATEST_HAWKBIT=$(ls -Art ${RAUC_BUILD_DIR}/rauc-hawkbit-updater_*_arm64.deb | tail -n 1)
    if [ -z ${LATEST_RAUC} ] && [ -z ${LATEST_RAUC_SERVICE} ] && [ -z ${LATEST_HAWKBIT} ]; then
        echo "No rauc, rauc-service, or rauc-hawkbit-updater deb found"
        exit 1
    fi
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${RAUC_BUILD_DIR}:/opt/${RAUC_BUILD_DIR} bash -c "apt install -y /opt/${LATEST_RAUC}"
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${RAUC_BUILD_DIR}:/opt/${RAUC_BUILD_DIR} bash -c "apt install -y /opt/${LATEST_RAUC_SERVICE}"
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${RAUC_BUILD_DIR}:/opt/${RAUC_BUILD_DIR} bash -c "apt install -y /opt/${LATEST_HAWKBIT}"

    sed -i ${ROOTFS_DIR}/etc/rauc/system.conf -e "s/__KEYRING_CERT__/${RAUC_CERT}/g"
    cp -v ${RAUC_CONFIG_DIR}/*.cert.pem ${ROOTFS_DIR}/etc/rauc/

    date -Ru >${ROOTFS_DIR}/opt/ROOTFS_BUILD_DATE

    if [ -f ./image-build-channel ]; then
        cp ./image-build-channel ${ROOTFS_DIR}/opt/
    else
        echo "Warning: image-build-channel not found. Skipping copy."
    fi

    if [ -f ./image-build-version ]; then
        cp ./image-build-version ${ROOTFS_DIR}/opt/
    else
        echo "Warning: image-build-version not found. Skipping copy."
    fi

    if [ -f ./components/repo-info/summary.txt ]; then
        cp ./components/repo-info/summary.txt ${ROOTFS_DIR}/opt/
        echo "summary.txt successfully copied to ${ROOTFS_DIR}/opt/"
    else
        echo "Warning: summary.txt not found. Skipping copy."
    fi

    export LATEST_KERNEL=$(ls -Art ${LINUX_BUILD_DIR}/linux-image*.deb | tail -n 1) || true
    if [ -z ${LATEST_KERNEL} ]; then
        echo "No Kernel found"
        exit 1
    fi

    echo "Installing kernel"
    KERNEL=$(ls ${LINUX_BUILD_DIR} | grep "^linux-image-" | grep --invert-match dbg | tail -n 1)
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro "${LINUX_BUILD_DIR}:/opt/linux" apt -y install --reinstall /opt/linux/${KERNEL}

    echo "Installing mwifiex driver"
    mkdir -p ${ROOTFS_DIR}/lib/modules/LATEST/updates
    cp ${LINUX_BUILD_DIR}/bin_wlan/*.ko ${ROOTFS_DIR}/lib/modules/LATEST
    systemd-nspawn -D ${ROOTFS_DIR}  bash -lc 'pushd /lib/modules/LATEST && depmod -a $(basename $(pwd -P))'

    echo "Installing splash"
    export LATEST_SPLASH=$(ls -Art ${PSPLASH_BUILD_DIR}/psplash_*_arm64.deb | tail -n 1)
    if [ -z ${LATEST_SPLASH} ]; then
        echo "No psplash found"
        exit 1
    fi
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${PSPLASH_BUILD_DIR}:/opt/${PSPLASH_BUILD_DIR} bash -c "apt install -y /opt/${LATEST_SPLASH}"
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${PSPLASH_BUILD_DIR}:/opt/${PSPLASH_BUILD_DIR} bash -c "systemctl enable psplash-start"
    systemd-nspawn -D ${ROOTFS_DIR} --bind-ro ${PSPLASH_BUILD_DIR}:/opt/${PSPLASH_BUILD_DIR} bash -c "systemctl enable psplash-systemd"

    echo "Disabeling framebuffer tty getty"
    systemd-nspawn -D ${ROOTFS_DIR} bash -c "systemctl disable getty@"

    echo "Disabeling dnsmasq"
    systemd-nspawn -D ${ROOTFS_DIR} bash -c "systemctl disable dnsmasq"

    echo "Disableing NetworkManager-wait-online.service"
    rm -vf ${ROOTFS_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service

    echo "Building locales"
    sed -i ${ROOTFS_DIR}/etc/locale.gen -e "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g"
    sed -i ${ROOTFS_DIR}/etc/locale.gen -e "s/# en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/g"
    sed -i ${ROOTFS_DIR}/etc/locale.gen -e "s/# C.UTF-8 UTF-8/C.UTF-8 UTF-8/g"
    systemd-nspawn -D ${ROOTFS_DIR} bash -c "locale-gen"

    echo "Registering regulatory.db"
    systemd-nspawn -D ${ROOTFS_DIR} bash -c "update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream"

    echo "Cleaning"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "rm -rf /root/.cache"
    systemd-nspawn -D ${ROOTFS_DIR} bash -lc "/opt/meticulous-venv/bin/pip cache purge"
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
