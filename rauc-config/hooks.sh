#!/bin/sh

echo "Calling rauc-config/hooks.sh: $1"

case "$1" in
        slot-post-install)
                # only rootfs needs to be handled
                test "$RAUC_SLOT_CLASS" = "rootfs" || exit 0

                echo "Copying config components into existing rootfs"
                # Copy over the config
                cp -rv /etc/hostname              "$RAUC_SLOT_MOUNT_POINT/etc/"
                cp -rv /etc/timezone              "$RAUC_SLOT_MOUNT_POINT/etc/"

                # Keep the SSH host keys stable for this machine
                cp -rv /etc/ssh/ssh_host_*_key*   "$RAUC_SLOT_MOUNT_POINT/etc/ssh"
                ;;
        *)
                exit 1
                ;;
esac

exit 0