#!/bin/bash

parent_dir=$(dirname "$(readlink -f "$0")")
source $parent_dir/../config.sh

# Check if the user is root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

rm -rf python-build
mkdir python-build
cd python-build

# Get the latest Python 3.12 source tarball
latest_version=$(curl -s https://www.python.org/ftp/python/ | grep -oE 'href="3\.12\.[0-9]+/' | sed 's/href="//' | sed 's/\///' | sort -V | tail -n 1)
wget https://www.python.org/ftp/python/$latest_version/Python-$latest_version.tar.xz
tar xf Python-$latest_version.tar.xz
rm *.tar.xz
cd ..

rm -rf python-install
mkdir -p python-install/install_root

rm -rf python-rootfs
mkdir python-rootfs

pv $parent_dir/../meticulous-rootfs.tar.gz | tar xz -C python-rootfs

function run_in_container() {
    sudo systemd-nspawn -D python-rootfs --bind=./python-build:/opt/python/source --bind=./python-install:/opt/python/install $1 $2
}

echo -e "\e[1;33mInstalling build dependencies\e[0m\n"
run_in_container "apt update"
run_in_container "apt install -y wget libffi-dev libbz2-dev liblzma-dev libsqlite3-dev libncurses5-dev libgdbm-dev zlib1g-dev libreadline-dev libssl-dev tk-dev build-essential libncursesw5-dev libc6-dev openssl git"
run_in_container "apt build-dep -y python3"
run_in_container "apt build-dep -y python3.9"

echo -e "\e[1;33mRunning configure\e[0m\n"
run_in_container --chdir=/opt/python/source/Python-${latest_version} "./configure --prefix=/opt/python/install/install_root/usr \
        --enable-optimizations \
        --enable-loadable-sqlite-extensions"

echo -e "\e[1;33mStarting compilation\e[0m\n"
run_in_container --chdir=/opt/python/source/Python-${latest_version} "make -j`nproc`"

echo -e "\e[1;33mInstalling python to fake root\e[0m\n"
run_in_container --chdir=/opt/python/source/Python-${latest_version} "make -j`nproc` altinstall"

echo -e "\e[1;33mCompressing python\e[0m\n"
run_in_container --chdir=/opt/python/install/install_root "tar --exclude='./usr/lib/python3.12/__pycache__' --exclude='./usr/lib/python3.12/test' --exclude='./usr/lib/python3.12/config-3.12-aarch64-linux-gnu' -zcvf /opt/python/install/python3.12.tar.gz ./usr"

cp python-install/python3.12.tar.gz ./python3.12.tar.gz
rm -rf python-install python-build