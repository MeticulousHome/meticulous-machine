#!/bin/bash
if [ ! -e /boot/env/uboot.env ]; then
    echo "U-Boot env not found"
    if [ -e /boot/env/uboot-redund.env ] && [ ! -e /boot/env/uboot.env ]; then
        echo "Redundant U-Boot env exists, copying redundant to active"
        cp /boot/env/uboot-redund.env /boot/env/uboot.env
    else
        echo "No redundant U-Boot env found, cannot restore. Meow :C"
        return 1
    fi
else
    echo "U-Boot env exists, no action needed"
fi
