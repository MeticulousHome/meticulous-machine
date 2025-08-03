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

sed -i "s/__TARGET_NAME__/$(hostname)/" /etc/hawkbit/config.conf
sed -i "s/__BOOT_MODE__/${boot_mode}/" /etc/hawkbit/config.conf
sed -i "s/__UPDATE_CHANNEL__/${update_channel}/" /etc/hawkbit/config.conf
sed -i "s/__SERIAL__/${serial}/" /etc/hawkbit/config.conf
sed -i "s/__BOOTED__/${boot_partition}/" /etc/hawkbit/config.conf
sed -i "s/__BUILD_DATE__/${build_date}/" /etc/hawkbit/config.conf
sed -i "s/__BUILD_CHANNEL__/${build_channel}/" /etc/hawkbit/config.conf
sed -i "s/__SOM__/${som}/" /etc/hawkbit/config.conf
sed -i "s/__MEMORY__/${memory}/" /etc/hawkbit/config.conf
