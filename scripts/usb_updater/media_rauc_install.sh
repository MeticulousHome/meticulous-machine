#!/bin/bash

MOUNT_POINT="/mnt/possible_updater"
UPDATING_FLAG_FILE="/tmp/updating"
USB_PATH=""
rauc_files=""
ERROR_INSTALLING=""
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

declare -A devices
devices=$(ls /dev/ | grep -E "$USB_PATH([1-9]+)?")
for PARTITION_NAME in $devices; do

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
    mapfile -d '' -t rauc_candidates < <(find "$MOUNT_POINT" -maxdepth 1 -type f -name "*.raucb" ! -name "._*" -print0 | sort -z)
    if [ "${#rauc_candidates[@]}" == "1" ]; then
        rauc_files="${rauc_candidates[0]}"

        echo "starting recovery update service"
        touch $UPDATING_FLAG_FILE
        systemctl stop rauc-hawkbit-updater.service
        busctl --system emit /handlers/MassStorage com.Meticulous.Handler.MassStorage RecoveryUpdate
        break
    elif [ "${#rauc_candidates[@]}" -gt "1" ]; then
        ERROR_INSTALLING="multiple RAUC bundles found on /dev/$PARTITION_NAME; keep exactly one .raucb file in the USB partition root"
        echo "$ERROR_INSTALLING"
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
    systemctl stop rauc-hawkbit-updater
    rauc_output="$(rauc install "$rauc_files" 2>&1)"
    rauc_result="$?"
    echo "$rauc_output"
    if [ "$rauc_result" == "0" ]; then
        echo "rauc install completed successfully"
        ERROR_INSTALLING=""
    else
        ERROR_INSTALLING="$(echo "$rauc_output" | tail -n 1)"
        if [ -z "$ERROR_INSTALLING" ]; then
            ERROR_INSTALLING="rauc install failed with exit code $rauc_result"
        fi
    fi
fi

if [ -n "$rauc_files" ] || [ -n "$ERROR_INSTALLING" ]; then
    if [ -z "$ERROR_INSTALLING" ]; then
        echo "restarting machine in 5 seconds"
    fi

    sleep 2
    echo "unmounting usb"
    umount $MOUNT_POINT
    rm -r $MOUNT_POINT

    # restart the machine when the update finishes
    if [ -n "$ERROR_INSTALLING" ]; then
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
