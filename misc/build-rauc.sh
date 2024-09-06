#!/bin/bash

parent_dir=$(dirname "$(readlink -f "$0")")
source $parent_dir/../config.sh

# Check if the user is root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi


rm -rf $parent_dir/rauc-deb
mkdir -p $parent_dir/rauc-deb
rm -rf $parent_dir/rauc-rootfs
mkdir -p $parent_dir/rauc-rootfs

pv $parent_dir/../meticulous-rootfs.tar.gz | tar xz -C rauc-rootfs


function run_in_container() {
    sudo systemd-nspawn -D rauc-rootfs \
        --bind=$parent_dir/rauc-deb:/opt/rauc \
        --bind=$parent_dir/../components/rauc:/opt/rauc/rauc \
        --bind=$parent_dir/../components/rauc-hawkbit-updater:/opt/rauc/rauc-hawkbit-updater \
        --setenv=DEB_BUILD_OPTIONS='nocheck parallel=$(nproc)' \
        $1 $2
}

function run_rauc() {
    echo -e "\e[1;32mexec: $1\e[0m\n"
    run_in_container "--chdir=/opt/rauc/rauc" "$1"
}

function run_hawkbit() {
    echo -e "\e[1;32mexec: $1\e[0m\n"
    run_in_container --chdir=/opt/rauc/rauc-hawkbit-updater "$1"
}

run_in_container "git config --global --add safe.directory /opt/rauc"
run_in_container "git config --global --add safe.directory /opt/rauc/rauc"
run_in_container "git config --global --add safe.directory /opt/rauc/rauc-hawkbit-updater"

run_in_container "apt update"
run_in_container "apt install -y dh-make fdisk libfdisk-dev meson pkg-config libcurl4-openssl-dev libjson-glib-dev libsystemd-dev"
run_in_container "apt build-dep -y rauc"
apt update 
apt install -y dh-make fdisk libfdisk-dev meson pkg-config libcurl4-openssl-dev libjson-glib-dev libsystemd-dev
apt build-dep -y rauc

# Usually the build would be
# meson setup build
# meson compile -C build
# But we are using debconf to do it for us. Sadly that means no caching, but we do get a debian package out of it :3

echo -e "\e[1;33m=== Building x86 rauc ===\e[0m"
pushd $parent_dir/../components/rauc
    git clean -fdx
    dh_make --createorig -p rauc_${RAUC_VERSION} --single --yes
    dh_auto_configure --buildsystem=meson -- -Dtests=false
    echo -e 'override_dh_auto_configure:\n\tdh_auto_configure -- -Dtests=false' >> debian/rules
    dpkg-buildpackage -rfakeroot -us -uc -b
    git clean -fdx
popd


-e "\e[1;33m=== Building rauc ===\e[0m"
run_rauc "git clean -fdx"
run_rauc "dh_make --createorig -p rauc_${RAUC_VERSION} --single --yes"
run_rauc "dh_auto_configure --buildsystem=meson -- -Dtests=false"
run_rauc "echo -e 'override_dh_auto_configure:\n\tdh_auto_configure -- -Dtests=false' >> debian/rules"
run_rauc "dpkg-buildpackage -rfakeroot -us -uc -b"
run_rauc "git clean -fdx"


echo -e "\e[1;33m=== Building rauc-hawkbit-updater ===\e[0m"
run_hawkbit "rm -rf debian"
run_hawkbit "dh_make --createorig -p rauc-hawkbit-updater_${HAWKBIT_VERSION} --single --yes"
run_hawkbit "dh_auto_configure --buildsystem=meson -- -Dsystemd=enabled"
echo -e 'override_dh_auto_configure:\n\tdh_auto_configure -- -Dsystemd=enabled' >> $parent_dir/../components/rauc-hawkbit-updater/debian/rules
run_hawkbit "dpkg-buildpackage -rfakeroot -us -uc -b"
run_hawkbit "git clean -fdx"

rm -rf $parent_dir/rauc-rootfs
mv $parent_dir/../components/rauc*.deb $parent_dir/rauc-deb
chmod +rw $parent_dir/rauc-deb/*.deb
mv $parent_dir/rauc-deb/*.deb $parent_dir
rm -rf $parent_dir/rauc-deb