#!/bin/bash

if (($EUID != 0)); then
    echo "Please run as root"
    exit
fi


# Function to display help text
show_help() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Run various build functions for Debian, Dial and Dashboard.

By default --all should be used to build all components.
Specific components can be build by passing their names as options.

Available options:
    --inplace                 Don't create a copy of the image
    --help                    Displays this help and exits

EOF
}

image_name="sdcard.img"

copy=1

# Parse command line arguments
for arg in "$@"; do
    case $arg in
    --inplace) copy=0 ;;
    --help)
        show_help; 
        exit 0
        ;;
    *)
        echo "Invalid option: $arg"
        show_help
        exit 1
        ;;
    esac
done

if [ $copy -eq 1 ]; then
    cp -v sdcard.img deployment.img
    image_name="deployment.img"
fi

# Resize the image
qemu-img resize -f raw ${image_name} +16G
echo w | fdisk ${image_name}

LOOP_DEV=$(losetup --find)
losetup -P ${LOOP_DEV} ${image_name}

# Resize the user partition
e2fsck -y -f ${LOOP_DEV}p5
growpart ${LOOP_DEV}  5

mkdir user-partition
mount ${LOOP_DEV}p5 user-partition

cp -v emmc.img user-partition/emmc.img
sync

sleep 1
umount ${LOOP_DEV}p*
losetup --detach ${LOOP_DEV}

rm -r user-partition

echo "Image was created in ${image_name}"