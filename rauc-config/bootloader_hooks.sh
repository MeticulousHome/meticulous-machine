#!/bin/sh

case "$1" in
    slot-post-install)
        #Ensure the hook is for the bootloader slot
        if [ "$RAUC_SLOT_CLASS" = "bootloader" ]; then
            echo "Removing environment files from /boot/env..."
            rm -f /boot/env/*.env
            echo "Environment files removed."
        fi
        ;;
    *)
        echo "Unknown hook: $1"
        exit 1
        ;;
esac

exit 0