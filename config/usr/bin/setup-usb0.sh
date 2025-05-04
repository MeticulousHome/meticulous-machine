#!/bin/bash

IFACE="usb0"
CON_NAME="usb0"

# Wait a bit in case usb0 is not ready yet
sleep 2

# Check if interface exists
if ! nmcli device show "$IFACE" &>/dev/null; then
    echo "Interface $IFACE not found."
    exit 1
fi

# Check if connection exists
if ! nmcli connection show "$CON_NAME" &>/dev/null; then
    echo "Creating NetworkManager connection '$CON_NAME'..."
    nmcli connection add type ethernet ifname "$IFACE" con-name "$CON_NAME" ipv4.method shared ipv6.method shared
else
    echo "Connection '$CON_NAME' already exists. Updating settings..."
    nmcli connection modify "$CON_NAME" ipv4.method shared ipv6.method shared connection.autoconnect yes
fi

# Activate the connection
nmcli connection up "$CON_NAME"
