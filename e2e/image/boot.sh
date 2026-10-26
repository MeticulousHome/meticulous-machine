#!/usr/bin/env bash
# Boot a built rootfs the way the machine does, without the machine.
#
# systemd-nspawn runs the image's own systemd on this ARM64 computer, so the
# image's services start as they do on a machine. What only a machine has is
# replaced, and only in this copy of the rootfs:
#   - an empty /meticulous-user, as on a machine leaving the factory (the
#     machine's partitions are not here, so its fstab keeps only the bind of
#     /var/log);
#   - no network at all (--private-network): nothing in the image reaches
#     hawkBit, Sentry or anything else. With NETWORK=link, a link to this
#     computer only (it is 10.88.0.1, the image 10.88.0.2) and no route
#     beyond, for tests that talk to the image as the app does, through its
#     nginx;
#   - the ESP32: the backend's built-in emulator (BACKEND=EMULATOR), or, with
#     ESP_UART, that serial device in place of the ESP32's /dev/ttymxc0;
#   - DEVICES: more device nodes for the image, as SOURCE[:DESTINATION], such
#     as a simulated I2C bus;
#   - PREPARE: a script run with the rootfs copy's path before it boots, for
#     what a caller simulates inside the image (it says what, and why).
#
# Usage: sudo [NETWORK=link] [ESP_UART=DEVICE] [DEVICES="..."] [PREPARE=SCRIPT] \
#            e2e/image/boot.sh ROOTFS_TARBALL WORKDIR
# Leaves the container "image" running.
set -euo pipefail

tarball=$1
work=$2
rootfs=$work/rootfs
user=$work/meticulous-user

mkdir -p "$rootfs" "$user/syslog"
tar -xzf "$tarball" -C "$rootfs" --numeric-owner

cp "$rootfs/etc/fstab" "$work/fstab.image"
printf '/meticulous-user/syslog /var/log none bind 0 0\n' > "$rootfs/etc/fstab"
if [ -n "${PREPARE:-}" ]; then
    "$PREPARE" "$rootfs"
fi

options=(--boot --machine=image --bind="$user:/meticulous-user" -D "$rootfs")

dropin=$rootfs/etc/systemd/system/meticulous-backend.service.d
mkdir -p "$dropin"
if [ -n "${ESP_UART:-}" ]; then
    printf '[Service]\nEnvironment=BACKEND=FIKA\n' > "$dropin/validation.conf"
    options+=(--bind="$ESP_UART:/dev/ttymxc0")
else
    printf '[Service]\nEnvironment=BACKEND=EMULATOR\n' > "$dropin/validation.conf"
fi
for device in ${DEVICES:-}; do
    options+=(--bind="$device")
done
# The serial ports, GPIO chips and I2C buses passed in, by device class.
options+=(--property="DeviceAllow=char-pts rw" --property="DeviceAllow=char-gpiochip rw"
          --property="DeviceAllow=char-i2c rw")

if [ "${NETWORK:-none}" = link ]; then
    options+=(--network-veth)
    # NetworkManager would ask DHCP for an address on it.
    printf '[keyfile]\nunmanaged-devices=interface-name:host0\n' \
        > "$rootfs/etc/NetworkManager/conf.d/99-image-validation.conf"
else
    options+=(--private-network)
fi

systemd-run --unit=image-under-test --collect systemd-nspawn "${options[@]}"

for _ in $(seq 1 60); do
    machinectl show image >/dev/null 2>&1 && break
    sleep 1
done
if ! machinectl show image >/dev/null 2>&1; then
    echo "the image did not start a container" >&2
    journalctl -u image-under-test --no-pager | tail -50 >&2
    exit 1
fi

if [ "${NETWORK:-none}" = link ]; then
    leader=$(machinectl show image -p Leader --value)
    ip addr add 10.88.0.1/30 dev ve-image
    ip link set ve-image up
    nsenter --target "$leader" --net -- ip addr add 10.88.0.2/30 dev host0
    nsenter --target "$leader" --net -- ip link set host0 up
fi
