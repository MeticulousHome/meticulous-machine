#!/bin/bash

if grep -q "root=/dev/mmcblk1" /proc/cmdline; then
  export boot_mode="sdcard";
else
  export boot_mode="emmc";
fi;

echo "Boot mode is ${boot_mode}"
export update_channel=$(cat /etc/hawkbit/channel)
echo "Update Channel is ${update_channel}"

cp  /etc/hawkbit/config.conf.template /etc/hawkbit/config.conf

serial="UNSET"

if [ ! -z "$(which met-config)" ]; then
  serial=$(met-config get .system.serial)
fi

sed -i "s/__TARGET_NAME__/$(hostname)/" /etc/hawkbit/config.conf
sed -i "s/__BOOT_MODE__/${boot_mode}/" /etc/hawkbit/config.conf
sed -i "s/__UPDATE_CHANNEL__/${update_channel}/" /etc/hawkbit/config.conf
sed -i "s/__SERIAL__/${serial}/" /etc/hawkbit/config.conf
