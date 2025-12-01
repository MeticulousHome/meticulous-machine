#!/bin/sh

echo "Calling rauc-config/hooks.sh: $1"

case "$1" in
        slot-post-install)
                # only rootfs needs to be handled
                test "$RAUC_SLOT_CLASS" = "rootfs" || exit 0

                if [ -e /boot/env/uboot-redund.env ] && [ ! -e /boot/env/uboot.env ]; then
                    echo "U-Boot env not found, only redundant exists, copying redundant to active"
                    cp /boot/env/uboot-redund.env /boot/env/uboot.env
                fi

                echo "Copying config components into existing rootfs"
                # Copy over the config
                cp -rv /etc/hostname              "$RAUC_SLOT_MOUNT_POINT/etc/"
                cp -rv /etc/timezone              "$RAUC_SLOT_MOUNT_POINT/etc/"
                cp -rv /etc/machine-id            "$RAUC_SLOT_MOUNT_POINT/etc/"

                # Keep the SSH host keys stable for this machine
                cp -rv /etc/ssh/ssh_host_*_key*   "$RAUC_SLOT_MOUNT_POINT/etc/ssh"
                cp -rv /etc/passwd /etc/shadow "$RAUC_SLOT_MOUNT_POINT/etc/"

                if [ -e /root/.ssh/authorized_keys ]; then
                        mkdir -p "$RAUC_SLOT_MOUNT_POINT/root/.ssh"
                        cp -rv /root/.ssh/authorized_keys "$RAUC_SLOT_MOUNT_POINT/root/.ssh/"
                fi
                fw_setenv BOOT_A_LEFT 3
                fw_setenv BOOT_B_LEFT 3
                shutdown -r 03:00
                ;;
        *)
                exit 1
                ;;
esac

exit 0
