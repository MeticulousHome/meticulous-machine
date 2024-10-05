#!/bin/bash

MOUNT_POINT="/tmp/possible_updater"
DEVICE_KERNEL_NAME="$1"
PARTITION_NUMBER=$2

USB_PATH="/dev/$DEVICE_KERNEL_NAME"

USB_AS_UPDATER=true
rauc_files=""

#if the mount point exists, it is being updated, discard this usb as updater device
if [ -d $MOUNT_POINT ]; then
    USB_AS_UPDATER=false
else

    echo "partition number received: $PARTITION_NUMBER"

    if [ "$PARTITION_NUMBER" == "1" ]; then
        mkdir $MOUNT_POINT
        echo "attempting to mount: $USB_PATH"
        mount $USB_PATH $MOUNT_POINT 1>&2
        error_mounting="$?"
        if [ $error_mounting == "0" ]; then
            echo "device mounted"
        else
            echo "device $USB_PATH could not be mounted: $error_mounting"
            rm -r $MOUNT_POINT
            exit 1
        fi
    rauc_files=$(find "$MOUNT_POINT" -maxdepth 1 -type f -name "*.raucb")
    else
        USB_AS_UPDATER=false
    fi
fi

#mounting usb device
if [ $USB_AS_UPDATER == true ] && [ -n "$rauc_files" ]; then
    echo "Stopping [ rauc-hawkbit-updater.service ] and starting [ rauc_installer.service ]"
    systemctl stop rauc-hawkbit-updater.service
    #export the kernel name of the device to mount it on the rauc_install service
    #FIXME When doing the update from the rauc-hawkbit-client we might not need to export them, but send a signal directly with them as parameters
    mkdir /tmp/rauc_install/
    echo "FD_NAME=$DEVICE_KERNEL_NAME" > /tmp/rauc_install/env_file

    umount $MOUNT_POINT
    systemctl start usb-rauc-install.service
    exit 0

else
    if [ $USB_AS_UPDATER == false ]; then
        echo "updater device already mounted or partition not valid"
    else
        if [ -z "$rauc_files" ]; then
            echo "RAUC file not found in $USB_PATH, notifying backend of new media"
            umount $MOUNT_POINT
            rm -r $MOUNT_POINT
        fi
    fi
    #check if the variable currently updating exists
    if [ -z "$DEVICE_KERNEL_NAME" ]; then
        exit 2
    fi
    #emiting dbus signal for a new mass storage device
    busctl --system emit /handlers/massStorage com.Meticulous.Handler.MassStorage NewUSB s "/dev/$DEVICE_KERNEL_NAME"
    
    exit 0
fi
