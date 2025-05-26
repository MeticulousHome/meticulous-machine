#!/bin/bash

UPDATING_FLAG_FILE="/tmp/updating"
DEVICE_KERNEL_NAME="$1"

#if a partition is mounted
if [ -f $UPDATING_FLAG_FILE ]; then
    echo "machine is updating"
    exit 1
fi

echo "device to analyze: $DEVICE_KERNEL_NAME"

systemctl start usb-rauc-install.service

#wait for the service to be up, and send the data through a dbus signal
sleep 1
busctl --system emit /handlers/massStorage com.Meticulous.Handler.MassStorage Updater s "$DEVICE_KERNEL_NAME"

#wait for the service to respond
timeout --foreground 5 bash -c '
while read -r line ; do
    echo $line
    if [ -n "$(echo $line | grep /handlers/Updater)" ]; then
        echo "usb-rauc-install.service is up"
        break
    fi
done < <(dbus-monitor --system "interface=com.Meticulous.Handler.Updater, member=Alive")
'

if [ $? -eq 124 ]; then
    echo "usb-rauc-install.service didnt respond"
    exit 2
else
    echo "usb-rauc-install.service started"
    exit 0
fi