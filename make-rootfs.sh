#!/bin/bash
set -eo pipefail

source config.sh

if (( $EUID != 0 )); then
    echo "Please run as root"
    exit
fi


if [ ! -f ${DEBIAN_SRC_DIR}/output/rootfs.tar.gz ]; then
	echo "#####################"
	echo "DEBIAN IMAGE DOES NOT EXIST!"
	echo "BUILDING NOW!"
	echo "#####################"
	bash build-components.sh --all
fi


# tagen from debian-var
# make tarball from footfs
# $1 -- packet folder
# $2 -- output tarball file (full name)
function make_tarball()
{
	cd $1

	chown root:root .
	echo "make tarball from folder ${1}"
	echo "Remove old tarball $2"
	rm -f $2

	echo "Create $2"

	RETVAL=0
	tar czf $2 . || {
		RETVAL=1
		rm -f $2
	};

	cd -
	return $RETVAL
}

mkdir -p ${ROOTFS_DIR}
# Unpack the image that includes the packages for Variscite
echo "Unpacking the debian image that includes packages for Variscite"
rm -rf ${ROOTFS_DIR}/*
pv  ${DEBIAN_SRC_DIR}/output/rootfs.tar.gz | tar xz -C ${ROOTFS_DIR}

#Install user pacakges if any

echo "rootfs: install user defined packages (user-stage)"
echo "rootfs: SYSTEM_PACKAGES \"${SYSTEM_PACKAGES}\" "
echo "rootfs: DEVELOPMENT_PACKAGES \"${DEVELOPMENT_PACKAGES}\" "

systemd-nspawn -D ${ROOTFS_DIR} apt install -y  ${SYSTEM_PACKAGES} ${DEVELOPMENT_PACKAGES}

# Install meticulous services
install -m 0644 ${SERVICES_DIR}/meticulous-dial.service \
    ${ROOTFS_DIR}/lib/systemd/system
ln -s /lib/systemd/system/meticulous-dial.service \
    ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-dial.service

install -m 0644 ${SERVICES_DIR}/meticulous-backend.service \
    ${ROOTFS_DIR}/lib/systemd/system
ln -s /lib/systemd/system/meticulous-backend.service \
    ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-backend.service

install -m 0644 ${SERVICES_DIR}/meticulous-watcher.service \
    ${ROOTFS_DIR}/lib/systemd/system
ln -s /lib/systemd/system/meticulous-watcher.service \
    ${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/meticulous-watcher.service

# Install meticulous components
# Install Dial app
systemd-nspawn -D ${ROOTFS_DIR} --bind-ro "${DIAL_SRC_DIR}/out/make/deb/arm64/:/opt/meticulous-ui" bash -c "apt -y install /opt/meticulous-ui/meticulous-ui.deb"

# Install Backend
echo "Installing Backed"
cp -r ${BACKEND_SRC_DIR} ${ROOTFS_DIR}/opt

# Install Dash
echo "Installing Dash"
cp -r ${DASH_SRC_DIR}/build ${ROOTFS_DIR}/opt/meticulous-dashboard

# Install Watcher
echo "Installing Watcher"
cp -r ${WATCHER_SRC_DIR} ${ROOTFS_DIR}/opt

# install python
echo "Installing Python"
tar xf ${DEBIAN_SRC_DIR}/variscite/python/python3.12.tar.gz -C ${ROOTFS_DIR}

## Reinstall pip3.12 as it is usually expecting python at the wrong location
rm -rf ${ROOTFS_DIR}/usr/lib/python3.12/site-packages/pip*
systemd-nspawn -D ${ROOTFS_DIR} bash -c "python3.12 -m ensurepip --upgrade --altinstall"
systemd-nspawn -D ${ROOTFS_DIR} bash -c "python3.12 -m pip install --upgrade pip"

# Install python requirements for meticulous
echo "Installing Backend dependencies"
systemd-nspawn -D ${ROOTFS_DIR} bash -c "python3.12 -m pip install -r /opt/meticulous-backend/requirements.txt"

# Install python requirements for meticulous
echo "Installing Watcher dependencies"
systemd-nspawn -D ${ROOTFS_DIR} bash -c "python3.12 -m pip install -r /opt/meticulous-watcher/requirements.txt"

# echo "Removing qemu"
# rm -f ${ROOTFS_DIR}/usr/bin/qemu-aarch64-static

echo "Packing Tarball"
make_tarball ${ROOTFS_DIR} `pwd`/meticulous-rootfs.tar.gz
