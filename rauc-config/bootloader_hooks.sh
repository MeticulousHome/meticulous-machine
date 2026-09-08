#!/bin/bash

function preserve_uboot() {
    declare -A env_map
    PRESERVE_PARAMS="mmcdev mmcpart BOOT_A_LEFT BOOT_B_LEFT BOOT_ORDER rauc_last_booted emmc_dev"

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

function install_boot_script() {
    local source="${RAUC_BUNDLE_MOUNT_POINT}/u-boot.scr"
    local target_dir="${BOOT_SCRIPT_TARGET_DIR:-/boot/env}"

    if [ ! -f "$source" ]; then
        echo "Matching u-boot.scr is missing from bootloader bundle" >&2
        return 1
    fi
    if [ ! -d "$target_dir" ]; then
        echo "U-Boot environment partition is not mounted at $target_dir" >&2
        return 1
    fi

    # Stage both copies before replacing either. boot.scr is the authoritative
    # bsp_script and is renamed last, so an interrupted copy keeps the old pair
    # bootable rather than activating a partial update.
    cp "$source" "$target_dir/.u-boot.scr.new"
    cp "$source" "$target_dir/.boot.scr.new"
    sync
    mv -f "$target_dir/.u-boot.scr.new" "$target_dir/u-boot.scr"
    mv -f "$target_dir/.boot.scr.new" "$target_dir/boot.scr"
    sync
}

case "$1" in
    slot-post-install)
        #Ensure the hook is for the bootloader slot
        if [ "$RAUC_SLOT_CLASS" = "bootloader" ]; then
            echo "Installing matching boot script and cleaning Env files after bootloader update"
            install_boot_script || exit 1
            preserve_uboot || exit 1
        fi
        ;;
    *)
        echo "Unknown hook: $1"
        exit 1
        ;;
esac

exit 0
