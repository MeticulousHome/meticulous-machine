#!/bin/bash

function preserve_uboot() {
    declare -A env_map
    PRESERVE_PARAMS="mmcdev mmcpart BOOT_A_LEFT BOOT_B_LEFT BOOT_ORDER emmc_dev"

    # Preserve what we care about
    for param in $PRESERVE_PARAMS; do
        value=$(fw_printenv $param | awk -F= '{print $2}')
        if [ -n "$value" ]; then
            env_map[$param]="$value"
        fi
    done

    # Clear all uboot variables
    for param in $(fw_printenv | awk -F= '{print $1}'); do
            fw_setenv "$param"
    done

    # Restore preserved variables
    bsp_bootcmd="echo restoring u-boot env variables...;"
    bsp_bootcmd+="env default -a;"
    for param in "${!env_map[@]}"; do
        bsp_bootcmd+="setenv $param ${env_map[$param]};"
        fw_setenv $param ${env_map[$param]}
    done
    bsp_bootcmd+="saveenv; echo Restored uboot env to default with preserved variables; reset;"
    echo "Setting uboot boot script to \"$bsp_bootcmd\""
    fw_setenv bsp_bootcmd "$bsp_bootcmd"
    fw_setenv bootcmd "run bsp_bootcmd"
}

case "$1" in
    slot-post-install)
        #Ensure the hook is for the bootloader slot
        if [ "$RAUC_SLOT_CLASS" = "bootloader" ]; then
            echo "Cleaning Env files after bootloader update"
            preserve_uboot
        fi
        ;;
    *)
        echo "Unknown hook: $1"
        exit 1
        ;;
esac

exit 0