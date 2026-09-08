#!/bin/bash

set -o pipefail

function preserve_uboot() {
    local -a env_names
    local -a preserved_names
    local -a preserved_values
    local env_output
    local index
    local param
    local preserve_param
    local preserve_params="mmcdev mmcpart BOOT_A_LEFT BOOT_B_LEFT BOOT_ORDER rauc_last_booted emmc_dev"
    local value

    # Take one checked snapshot so a transient per-key read cannot silently
    # discard a value before the environment is cleared. read's final field
    # retains any additional '=' characters in the value.
    if ! env_output=$(fw_printenv); then
        echo "Unable to read U-Boot environment" >&2
        return 1
    fi

    while IFS='=' read -r param value; do
        [ -n "$param" ] || continue
        env_names+=("$param")
        for preserve_param in $preserve_params; do
            if [ "$param" = "$preserve_param" ]; then
                preserved_names+=("$param")
                preserved_values+=("$value")
                break
            fi
        done
    done <<< "$env_output"

    # Clear all uboot variables
    for param in "${env_names[@]}"; do
        fw_setenv "$param" || return 1
    done

    # Restore preserved variables
    bsp_bootcmd="echo restoring u-boot env variables...;"
    bsp_bootcmd+="env default -a;"
    for ((index = 0; index < ${#preserved_names[@]}; index++)); do
        param="${preserved_names[$index]}"
        value="${preserved_values[$index]}"
        bsp_bootcmd+="setenv $param $value;"
        fw_setenv "$param" "$value" || return 1
    done
    bsp_bootcmd+="saveenv; echo Restored uboot env to default with preserved variables; reset;"
    echo "Setting uboot boot script to \"$bsp_bootcmd\""
    fw_setenv bsp_bootcmd "$bsp_bootcmd" || return 1
    fw_setenv bootcmd "run bsp_bootcmd" || return 1
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
    # bsp_script and is activated last, so a staging failure leaves the active
    # boot script untouched.
    cp "$source" "$target_dir/.u-boot.scr.new" || return 1
    cp "$source" "$target_dir/.boot.scr.new" || return 1
    sync || return 1
    mv -f "$target_dir/.u-boot.scr.new" "$target_dir/u-boot.scr" || return 1
    mv -f "$target_dir/.boot.scr.new" "$target_dir/boot.scr" || return 1
    sync || return 1
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
