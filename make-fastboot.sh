#!/usr/bin/env bash
# Parse the command line arguments
source config.sh

set -eo pipefail

ROOT_SIZE=5           # in GiB
BOOTLOADER_ENV_SIZE=8 # in MiB

BOOTLOADER_ENV_IMAGE="uboot_env_fastboot.img"
FASTBOOT_IMAGE="rootfs_fastboot.img"

# Check if $ROOTFS_PATH exists as a file
if [[ ! -f $METIUCULOUS_ROOTFS ]]; then
    echo "Rootfs tarball does not exist: $METIUCULOUS_ROOTFS"
    exit 1
fi

echo "Using qemu-img to create ${IMAGE_TARGET}"
qemu-img create -f raw ${FASTBOOT_IMAGE} ${ROOT_SIZE}G
qemu-img create -f raw ${BOOTLOADER_ENV_IMAGE} ${BOOTLOADER_ENV_SIZE}M


mkfs -t ext4 ${BOOTLOADER_ENV_IMAGE}
mkfs -t ext4 ${FASTBOOT_IMAGE}

mkdir -p meticulous-mount/rootfs
mkdir -p meticulous-mount/uboot-env

mount ${FASTBOOT_IMAGE} meticulous-mount/rootfs
mount ${BOOTLOADER_ENV_IMAGE}       meticulous-mount/uboot-env

echo "Installing OS to ${FASTBOOT_IMAGE} (meticulous-mount/rootfs)"
pv  ${METIUCULOUS_ROOTFS}  | tar -xp -I pigz -C meticulous-mount/rootfs

echo "Patching fstab"
cp -v rauc-config/fstab_emmc meticulous-mount/rootfs/etc/fstab

echo "Installing u-boot script"
mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Meticulous Boot Script" -d rauc-config/u-boot.cmd rauc-config/u-boot.scr
cp -v rauc-config/u-boot.scr meticulous-mount/uboot-env/u-boot.scr
cp -v rauc-config/u-boot.scr meticulous-mount/uboot-env/boot.scr

umount meticulous-mount/rootfs
umount meticulous-mount/uboot-env

rm -r meticulous-mount