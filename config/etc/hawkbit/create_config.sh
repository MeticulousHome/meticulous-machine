#!/bin/bash

get_somrev() {
        # Get the raw output
        raw_output=$(i2cget -f -y 0x0 0x52 0x1e)

        # Convert the output to decimal
        decimal_output=$(( $raw_output ))

        # Extract major and minor versions
        major=$(( ($decimal_output & 0xE0) >> 5 ))
        minor=$(( $decimal_output & 0x1F ))

        # Adjust the major version as per the specification
        major=$(( $major + 1 ))

        echo "$major.$minor"
}

get_uboot_rev() {
  device=$1

  # Sanity checks, we dont want the updater to fail to start
  if [ -z $device ]; then echo "DEV_EMPTY"; return 1; fi

  if [ ! -e $device ]; then echo "ENODEV"; return; fi

  rev=$(busybox strings $device | grep "U-Boot" -m1)
  if [ -z "$rev" ]; then
    echo "NULL"
  else
    echo "$rev"
  fi
}

get_mmc_boot_config() {
  if [ ! $(which mmc) ] ; then
    echo "mmc-tool-missing"
    return 1
  fi

  raw_part_config=$(mmc extcsd read /dev/mmcblk2 | grep --only "\[PARTITION_CONFIG: 0x..\]" | grep --only "0x..")
  # part_access=$((${raw_part_config} & 0x3))

  part_boot_active=$(((${raw_part_config} >> 3) & 0x7))
  if [ ${part_boot_active} -eq 0 ] ; then
    echo "p1"
  elif [ ${part_boot_active} -eq 1 ] ; then
    echo "boot0"
  elif [ ${part_boot_active} -eq 2 ] ; then
    echo "boot1"
  else
    echo "unknown-${part_boot_active}"
    return 1
  fi
}

if grep -q "root=/dev/mmcblk1" /proc/cmdline; then
  export boot_mode="sdcard";
  boot_partition="sdcard"  #get boot partition
else
  export boot_mode="emmc";
  boot_partition=$(rauc status --output-format=json-pretty | grep -oP '"booted" : "\K[^"]*' || echo UNKNOWN)  #get boot partition
fi;

echo "Boot mode is ${boot_mode}"
export update_channel=$(cat /etc/hawkbit/channel)
echo "Update Channel is ${update_channel}"

cp  /etc/hawkbit/config.conf.template /etc/hawkbit/config.conf

serial="UNSET"

if [ ! -z "$(which met-config)" ]; then
  serial=$(met-config get .system.serial)
fi

build_date=$(cat /opt/ROOTFS_BUILD_DATE || echo UNKNOWN)                                          #get booted image build date
build_channel=$(cat /opt/image-build-channel || echo UNKNOWN)

memory=$(cat /proc/meminfo | grep MemTotal | grep "[0-9]* [a-zA-Z]B" -o)
som=$(get_somrev)

uboot_disk_rev=$(get_uboot_rev /dev/mmcblk2p1)
uboot_boot0_rev=$(get_uboot_rev /dev/mmcblk2boot0)
uboot_boot1_rev=$(get_uboot_rev /dev/mmcblk2boot1)
uboot_active="/dev/mmcblk2$(get_mmc_boot_config)"
if [ $? -ne 0 ]; then
  uboot_active_ref="ERROR"
else
  uboot_active_ref=$(get_uboot_rev ${uboot_active})
fi
echo "U-Boot booted from ${uboot_active} with version ${uboot_active_ref}"


sed -i "s/__TARGET_NAME__/$(hostname)/" /etc/hawkbit/config.conf
sed -i "s/__BOOT_MODE__/${boot_mode}/" /etc/hawkbit/config.conf
sed -i "s/__UPDATE_CHANNEL__/${update_channel}/" /etc/hawkbit/config.conf
sed -i "s/__SERIAL__/${serial}/" /etc/hawkbit/config.conf
sed -i "s/__BOOTED__/${boot_partition}/" /etc/hawkbit/config.conf
sed -i "s/__BUILD_DATE__/${build_date}/" /etc/hawkbit/config.conf
sed -i "s/__BUILD_CHANNEL__/${build_channel}/" /etc/hawkbit/config.conf
sed -i "s/__SOM__/${som}/" /etc/hawkbit/config.conf
sed -i "s/__MEMORY__/${memory}/" /etc/hawkbit/config.conf

sed -i "s/__UBOOT_DISK_REV__/${uboot_disk_rev}/" /etc/hawkbit/config.conf
sed -i "s/__UBOOT_BOOT0_REV__/${uboot_boot0_rev}/" /etc/hawkbit/config.conf
sed -i "s/__UBOOT_BOOT1_REV__/${uboot_boot1_rev}/" /etc/hawkbit/config.conf
sed -i "s|__UBOOT_ACTIVE__|${uboot_active}|" /etc/hawkbit/config.conf
sed -i "s/__UBOOT_ACTIVE_REV__/${uboot_active_ref}/" /etc/hawkbit/config.conf