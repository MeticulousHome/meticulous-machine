#!/usr/bin/env bash
# Boot a built rootfs the way the machine does, without the machine.
#
# systemd-nspawn runs the image's own systemd on this ARM64 computer, so the
# image's services start as they do on a machine. What only a machine has is
# replaced, and only in this copy of the rootfs:
#   - no network at all (--private-network): nothing in the image reaches
#     hawkBit, Sentry or anything else;
#   - an empty /meticulous-user, as on a machine leaving the factory (the
#     machine's partitions are not here, so its fstab keeps only the bind of
#     /var/log);
#   - the backend on its built-in ESP32 emulator (BACKEND=EMULATOR), or, with
#     ESP_UART, on that serial device in place of the ESP32's /dev/ttymxc0.
#
# Usage: sudo e2e/image/boot.sh ROOTFS_TARBALL WORKDIR
# Leaves the container "image" running for e2e/image/check_image.py.
set -euo pipefail

tarball=$1
work=$2
rootfs=$work/rootfs
user=$work/meticulous-user

mkdir -p "$rootfs" "$user/syslog"
tar -xzf "$tarball" -C "$rootfs" --numeric-owner

cp "$rootfs/etc/fstab" "$work/fstab.image"
printf '/meticulous-user/syslog /var/log none bind 0 0\n' > "$rootfs/etc/fstab"

dropin=$rootfs/etc/systemd/system/meticulous-backend.service.d
mkdir -p "$dropin"
if [ -n "${ESP_UART:-}" ]; then
    printf '[Service]\nEnvironment=BACKEND=FIKA\n' > "$dropin/validation.conf"
    device=(--bind="$ESP_UART:/dev/ttymxc0")
else
    printf '[Service]\nEnvironment=BACKEND=EMULATOR\n' > "$dropin/validation.conf"
    device=()
fi

systemd-run --unit=image-under-test --collect \
    systemd-nspawn --boot --machine=image --private-network \
        --bind="$user:/meticulous-user" "${device[@]}" -D "$rootfs"

for _ in $(seq 1 60); do
    machinectl show image >/dev/null 2>&1 && exit 0
    sleep 1
done
echo "the image did not start a container" >&2
journalctl -u image-under-test --no-pager | tail -50 >&2
exit 1
