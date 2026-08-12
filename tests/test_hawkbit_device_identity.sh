#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

export HAWKBIT_DEVICE_IDENTITY_DIR="${test_root}/meticulous-user/.device-identity"
export HAWKBIT_DEVICE_UUID_FILE="${HAWKBIT_DEVICE_IDENTITY_DIR}/device-uuid"

source "${repo_root}/config/etc/hawkbit/device_identity.sh"

first_uuid="123e4567-e89b-42d3-a456-426614174000"
second_uuid="987e6543-e21b-45d3-b654-426614174999"

if get_cached_device_uuid; then
  echo "Expected a missing ESP32 device UUID cache to fail" >&2
  exit 1
fi

mkdir -p "$HAWKBIT_DEVICE_IDENTITY_DIR"
printf '%s\n' "$first_uuid" > "$HAWKBIT_DEVICE_UUID_FILE"
test "$(get_cached_device_uuid)" = "$first_uuid"

printf '%s\n' "invalid" > "$HAWKBIT_DEVICE_UUID_FILE"
if get_cached_device_uuid; then
  echo "Expected an invalid ESP32 device UUID cache to fail" >&2
  exit 1
fi

# The backend treats the ESP32 as the source of truth and replaces a different
# VAR-SOM cache value with the UUID reported by the ESP32.
printf '%s\n' "$second_uuid" > "$HAWKBIT_DEVICE_UUID_FILE"
test "$(get_cached_device_uuid)" = "$second_uuid"

mkdir -p "${test_root}/meticulous-user/config"
printf '%s\n' "user data" > "${test_root}/meticulous-user/config/settings"
rm -rf "${test_root}/meticulous-user/"*

test ! -e "${test_root}/meticulous-user/config"
test -f "$HAWKBIT_DEVICE_UUID_FILE"
test "$(get_cached_device_uuid)" = "$second_uuid"

echo "Hawkbit device identity tests passed"
