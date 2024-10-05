#!/bin/bash

MOUNT_POINT="/tmp/possible_updater"
USB_PATH="/dev/$1"
rauc_file=""
ERROR_INSTALLING=true

#protect for usb disconnection
echo "device to mount: $USB_PATH"

if [ ! -b $USB_PATH ]; then
    echo "USB disconnected, aborting"
    exit 1
fi

#mounting usb device
mount $USB_PATH $MOUNT_POINT
if [ $? -eq 0 ]; then
    echo "device mounted"
else
    echo "device could not be mounted"
    exit 2
fi

rauc_file=$(find "$MOUNT_POINT" -maxdepth 1 -type f -name "*.raucb")

if [ -z "$rauc_file" ]; then
    echo "RAUC file not found in the usb media"
    exit 3
else
    #checks the status of the rauc-hawknit-updater is stopped
    rhu_status=$(systemctl status rauc-hawkbit-updater.service | grep inactive)
    if [ -z "$rhu_status" ]; then
        echo "hawkbit updater is alive"
        systemctl stop rauc-hawkbit-updater.service
    else
        echo "hawkbit updater is dead"
    fi
    # call the InstallBundle() method from rauc using d-bus
    echo "Installing from rauc bundle"

    while read -r line; do
        echo "$line"
        if echo "$line" | grep -q "fail"; then
            break
        fi

        if echo "$line" | grep -q "Installing done"; then
            echo "rauc install completed successfully"
            ERROR_INSTALLING=false
            break
        fi

    done < <(rauc install "$rauc_file")

    if [ ! $ERROR_INSTALLING == true ]; then
        echo "restarting machine in 5 seconds"
    fi

    sleep 5
    echo "unmounting usb"
    umount $MOUNT_POINT

    # restart the machine when the update finishes
    if [ $ERROR_INSTALLING == false ]; then
        #TODO add sound?
        reboot now
    else
        echo "Error installing, not rebooting"
    fi
fi
