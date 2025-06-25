#!/usr/bin/env bash
set -eo pipefail

source config.sh

if (($EUID != 0)); then
    echo "Please run as root"
    exit
fi

if [ ! -f "meticulous-rootfs.tar.gz" ]; then
    echo "#####################"
    echo "ROOTFS DOES NOT EXIST!"
    echo "BUILDING NOW!"
    echo "#####################"
    bash make-rootfs.sh --all
fi

declare -i TARGET_SIZE=15634267648                   # in Bytes
declare -i IMAGE_SIZE=($((TARGET_SIZE / 1024))*1024) # in Bytes, KiB aligned

# Bootloader
declare -i BOOTLOADER_START=32                                   # in KiB
declare -i BOOTLOADER_SIZE=8192                                  # in KiB
declare -i BOOTLOADER_END=BOOTLOADER_START+BOOTLOADER_SIZE       # in KiB
declare -i BOOTLOADER_ENV_START=BOOTLOADER_END                   # in KiB
declare -i BOOTLOADER_ENV_SIZE=8192                              # in KiB
declare -i BOOTLOADER_ENV_END=BOOTLOADER_END+BOOTLOADER_ENV_SIZE # in KiB

# root disks
declare -i ROOT_ALIGNMENT=1024
declare -i ROOT_SIZE=$((5 * 1024 * 1024 / ROOT_ALIGNMENT))*ROOT_ALIGNMENT # in KiB
declare -i ROOT_A_START=$((BOOTLOADER_ENV_END / ROOT_ALIGNMENT + 1))*ROOT_ALIGNMENT
declare -i ROOT_A_END=ROOT_A_START+ROOT_SIZE
declare -i ROOT_B_START=ROOT_A_END
declare -i ROOT_B_END=ROOT_A_END+ROOT_SIZE

# user data
declare -i USER_ALIGNMENT=ROOT_ALIGNMENT
declare -i USER_START=ROOT_B_END
declare -i USER_END=$((IMAGE_SIZE / 1024))-1-0x10
declare -i USER_SIZE=USER_END-USER_START

function print_partition_scheme() {
    echo -e "## Planned paritioning scheme"

    # Print partition table for checking
    PART_TABLE=$(echo "Number:Name:Start (KiB):Size (KiB):End (KiB):Aling (KiB):Type\n")
    PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x::%s" 1 uboot ${BOOTLOADER_START} ${BOOTLOADER_SIZE} $((${BOOTLOADER_END} - 1)) "raw")\n"
    PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x::%s" 2 uboot_env ${BOOTLOADER_ENV_START} ${BOOTLOADER_ENV_SIZE} $((${BOOTLOADER_ENV_END} - 1)) "fat32")\n"
    PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x:0x%02x:%s" 3 root_a ${ROOT_A_START} ${ROOT_SIZE} $((${ROOT_A_END} - 1)) $ROOT_ALIGNMENT "ext4")\n"
    PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x:0x%02x:%s" 4 root_b ${ROOT_B_START} ${ROOT_SIZE} $((${ROOT_B_END} - 1)) $ROOT_ALIGNMENT "ext4")\n"
    PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x:0x%02x:%s" 5 user ${USER_START} ${USER_SIZE} $((${USER_END} - 1)) $USER_ALIGNMENT "ext4")\n"

    echo -e $PART_TABLE | column -s: -t --table-right 1,3,4,5
}

function create_unaligned_partition() {
    START=$1
    END=$2

    parted ${IMAGE_TARGET} mkpart -a none primary ${START}KiB ${END}KiB
}

declare -g PARTITIONS=0

function create_partition() {
    NAME=$1
    START=$2
    END=$3
    FS_TYPE=$4
    declare -i PARTITION_NUMBER=${PARTITIONS}+1

    if [ ! -z $END ]; then
        declare -i SIZE=END-START
    fi

    # Everything below 100M is probably not worth optimizing
    if [ -n "$SIZE" ] && [ $SIZE -lt $((100 * 1024)) ]; then
        printf "%-09s: Creating        unaligned parition (${PARTITION_NUMBER}) from 0x%06x to 0x%06x\n" "$NAME" "${START}" "${END}"
        create_unaligned_partition ${START} ${END}
    else
        if [ -z "$END" ]; then
            printf "%-09s: Creating properly aligned parition (${PARTITION_NUMBER}) from 0x%06x to the end\n" "$NAME" "${START}"
            parted ${IMAGE_TARGET} -f mkpart primary ${START}KiB 100%
        else
            printf "%-09s: Creating properly aligned parition (${PARTITION_NUMBER}) from 0x%06x to 0x%06x\n" "$NAME" "${START}" "${END}"
            parted ${IMAGE_TARGET} -f mkpart primary ${START}KiB ${END}KiB
        fi
    fi

    parted ${IMAGE_TARGET} name $PARTITION_NUMBER $NAME
    declare -ig PARTITIONS=PARTITIONS+1
}

function create_image() {
    echo -e "\n## Creating parition scheme"

    if [ -b ${IMAGE_TARGET} ]; then
        IS_BLOCK=y
        declare -i DD_BLOCK_SIZE=1024
        bash -c "umount ${IMAGE_TARGET}* -v || true"
        echo "${IMAGE_TARGET} is a block device, nuking partition table"
        dd if=/dev/zero of=${IMAGE_TARGET} bs=${DD_BLOCK_SIZE} count=32 status=noxfer status=progress
    else
        IS_BLOCK=n
        if command -v qemu-img >/dev/null; then
            echo "Using qemu-img to create ${IMAGE_TARGET}"
            qemu-img create -f raw ${IMAGE_TARGET} ${IMAGE_SIZE}
        else
            echo "qemu-img is not installed, falling back to dd"
            declare -i DD_BLOCK_SIZE=1024*1024
            declare -i IMAGE_BLOCKS=IMAGE_SIZE*1024/DD_BLOCK_SIZE
            dd if=/dev/zero of=${IMAGE_TARGET} bs=${DD_BLOCK_SIZE} count=${IMAGE_BLOCKS} status=noxfer status=progress 2>/dev/null
        fi
    fi

    # Create GPT partition scheme
    parted ${IMAGE_TARGET} mklabel gpt

    # Create uboot partition
    create_partition uboot ${BOOTLOADER_START} ${BOOTLOADER_END}
    create_partition uboot_env ${BOOTLOADER_ENV_START} ${BOOTLOADER_ENV_END}
    create_partition root_a ${ROOT_A_START} ${ROOT_A_END}
    parted ${IMAGE_TARGET} -f set ${PARTITIONS} boot on
    create_partition root_b ${ROOT_B_START} ${ROOT_B_END}
    parted ${IMAGE_TARGET} -f set ${PARTITIONS} boot on
    # SDCards will be filled to the end
    if [ ${IS_BLOCK} = "y" ]; then
        create_partition user ${USER_START}
    else
        create_partition user ${USER_START} ${USER_END}
    fi

    if [ ${IS_BLOCK} = "y" ]; then
        echo "${IMAGE_TARGET} is a block device, rescanning partitions"
        partprobe ${IMAGE_TARGET}
        PARTITION=${IMAGE_TARGET}
        sleep 3
    else
        LOOP_DEV=$(losetup --find)
        PARTITION=${LOOP_DEV}p
        losetup -P ${LOOP_DEV} ${IMAGE_TARGET}
    fi

    echo -e "\n## Formating"

    echo "Creating fat32 for u-boot env on ${PARTITION}2"
    mkfs.fat ${PARTITION}2 >/dev/null

    echo "Creating ext4  for   root_a   on ${PARTITION}3"
    mkfs.ext4 ${PARTITION}3 -F -L root_a -q

    echo "Creating ext4  for   root_b   on ${PARTITION}4"
    mkfs.ext4 ${PARTITION}4 -F -L root_b -q

    echo "Creating ext4  for    user    on ${PARTITION}5"
    mkfs.ext4 ${PARTITION}5 -F -L user -q

    mkdir -p sdcard_a
    mkdir -p sdcard_b

    mount ${PARTITION}3 sdcard_a
    mount ${PARTITION}4 sdcard_b

    echo -e "\n## Installing"

    echo "Installing u-boot             to ${PARTITION}1"
    dd if=${BOOTLOADER_BUILD_DIR}/imx-boot-sd.bin of=${PARTITION}1 bs=1K status=noxfer status=progress 2>/dev/null

    echo "Installing OS A               to ${PARTITION}3"
    pv meticulous-rootfs.tar.gz | tar -xp -I pigz -C sdcard_a
    cp -v rauc-config/fstab_sdcard sdcard_a/etc/fstab

    echo "Installing OS B               to ${PARTITION}4"
    pv meticulous-rootfs.tar.gz | tar -xp -I pigz -C sdcard_b
    cp -v rauc-config/fstab_sdcard sdcard_b/etc/fstab

    echo "Installing u-boot script"
    mkdir -p sdcard-uboot
    mount ${PARTITION}2 sdcard-uboot
    cp -v ${BOOTLOADER_BUILD_DIR}/u-boot.scr sdcard-uboot/u-boot.scr
    cp -v ${BOOTLOADER_BUILD_DIR}/u-boot.scr sdcard-uboot/boot.scr

    mkdir -p sdcard-user
    mount ${PARTITION}5 sdcard-user
    mkdir -p sdcard-user/syslog

    echo "Syncing disks..."
    sync &

    SYNC_PID=$!
    while ps -p $SYNC_PID >/dev/null; do
        echo "\r"
        echo -n "$(grep -e Dirty /proc/meminfo)"
        sleep 0.2
    done
    echo "\n"

    umount sdcard_a
    umount sdcard_b
    umount sdcard-uboot
    umount sdcard-user

    if ! [ -b ${IMAGE_TARGET} ]; then
        losetup --detach ${LOOP_DEV}

        echo -e "\n## Creating emmc image"

        cp ${IMAGE_TARGET} emmc.img
        LOOP_DEV=$(losetup --find)
        PARTITION=${LOOP_DEV}p
        losetup -P ${LOOP_DEV} emmc.img
        mount ${PARTITION}3 sdcard_a
        mount ${PARTITION}4 sdcard_b
        cp -v rauc-config/fstab_emmc sdcard_a/etc/fstab
        cp -v rauc-config/fstab_emmc sdcard_b/etc/fstab
        sync
        sync
        sleep 1
        umount sdcard_a
        umount sdcard_b
        losetup --detach ${LOOP_DEV}

        echo -e "Image can be installed from ${IMAGE_TARGET}"
        echo -e "Machine can be imaged with emmc.img"
    fi

    rm -r sdcard_a sdcard_b sdcard-uboot sdcard-user


    echo -e "\n## Done"

}

function list_removable_devices() {
    echo "Available removable devices:"
    lsblk -d -o NAME,MODEL,SIZE,TYPE | grep -E 'disk$' | grep --invert -e 'nvme' -e '0B' | awk '{print "/dev/"$1, $2, $3}'
}

function show_help() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Create a bootable SD card or image for the Meticulous project.

OPTIONS:
    --image                Create an image file named 'sdcard.img'
    --dev <device_name>    Specify the device (e.g., /dev/sdb) to write to
    --help                 Display this help text and exits

If no options are provided, the script will list all available removable
devices and prompt for a selection.
EOF
}

# Check for command line arguments
if [ "$#" -eq 0 ]; then
    list_removable_devices
    read -p "Enter the device to use (e.g. /dev/sdb) or enter an image filename (e.g. sdcard.img): " IMAGE_TARGET
elif [ "$1" = "--image" ]; then
    IMAGE_TARGET="sdcard.img"
elif [ "$1" = "--dev" ]; then
    if [ -z "$2" ]; then
        echo "No device specified. Exiting."
        exit 1
    fi
    IMAGE_TARGET=$2
elif [ "$1" = "--help" ]; then
    show_help
    exit 0
else
    echo "Invalid argument '$1'"
    show_help
    exit 1
fi

echo "Using target: $IMAGE_TARGET to create image"
print_partition_scheme
create_image
