#!/bin/bash

MOUNT_POINT="/mnt/possible_updater"
UPDATING_FLAG_FILE="/tmp/updating"
USB_PATH=""
rauc_files=""
ERROR_INSTALLING="unknown"
PARTITION_NAME=""

#wait for the name of the device that has the update bundle
USB_PATH=$(timeout 6 bash -c '
while read -r line ; do
    if [ -n "$(echo $line | grep -E sd. )" ]; then
        busctl --system emit /handlers/Updater com.Meticulous.Handler.Updater Alive
        echo "$line"
        break
    fi
done < <(dbus-monitor --system "interface=com.Meticulous.Handler.MassStorage, member=Updater")')

USB_PATH=$(echo $USB_PATH | awk '{print $2}' | tr -d '\n\r" ' )

if [ -z $USB_PATH ]; then
    echo "did not receive the name of the device, exiting"
    exit 4
fi

#protect for usb disconnection
if [ ! -b "/dev/$USB_PATH" ]; then
    echo "USB disconnected, aborting"
    exit 1
fi

#find the rauc file in any partition of the plugged in device
mkdir $MOUNT_POINT
for PARTITION_NAME in $(ls /dev/ | grep -E $USB_PATH[1-9]+); do

    FILE_DESCRIPTOR="/dev/$PARTITION_NAME"
    umount $FILE_DESCRIPTOR #if automount mounted it, later maybe make use of automount
    mount $FILE_DESCRIPTOR $MOUNT_POINT 1>&2
    error_mounting="$?"
    if [ $error_mounting == "0" ]; then
        echo "device mounted"
    else
        echo "device $FILE_DESCRIPTOR could not be mounted: $error_mounting"
        continue
    fi
    rauc_files="$(find "$MOUNT_POINT" -maxdepth 1 -type f -name "*.raucb")"
    if [ -n "$rauc_files" ]; then

        echo "starting recovery update service"
        touch $UPDATING_FLAG_FILE
        systemctl stop rauc-hawkbit-updater.service
        busctl --system emit /handlers/MassStorage com.Meticulous.Handler.MassStorage RecoveryUpdate
        break
    else
        #notify backend of new media
        echo "Notifying backend of new media"
        busctl --system emit /handlers/massStorage com.Meticulous.Handler.MassStorage NewUSB s "/dev/$PARTITION_NAME"
    fi
    umount $MOUNT_POINT
done 

if [ -n "$rauc_files" ]; then
    while read -r line; do
        echo "$line"
        if echo "$line" | grep -q "fail"; then
            ERROR_INSTALLING="$line"
            break
        fi
        if echo "$line" | grep -q "Installing done"; then
            echo "rauc install completed successfully"
            ERROR_INSTALLING=""
            break
        fi

    done < <(rauc install "$rauc_files")

    if [ -z "$ERROR_INSTALLING" ]; then
        echo "restarting machine in 5 seconds"
    fi

    sleep 2
    echo "unmounting usb"
    umount $MOUNT_POINT
    rm -r $MOUNT_POINT

    # restart the machine when the update finishes
    if [ -z "$ERROR_INSTALLING" ]; then
        sleep 3
        reboot now
    else
        echo "Error while installing, not rebooting"
        busctl --system emit /handlers/Updater com.Meticulous.Handler.Updater UpdateFailed s "$ERROR_INSTALLING"
        systemctl restart rauc-hawkbit-updater.service
        rm $UPDATING_FLAG_FILE
    fi
else
    if [ -d $MOUNT_POINT ]; then
        rm -r $MOUNT_POINT
    fi
fi
