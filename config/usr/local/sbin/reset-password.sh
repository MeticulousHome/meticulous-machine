#!/bin/bash
FIRST_BOOT_FLAG="/meticulous-user/first_password_changed"
if [ ! -f "$FIRST_BOOT_FLAG" ]; then
    chage -d 0 root
    touch "$FIRST_BOOT_FLAG"
fi