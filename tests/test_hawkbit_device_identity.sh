#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

export HAWKBIT_DEVICE_IDENTITY_DIR="${test_root}/meticulous-user/.device-identity"
export HAWKBIT_DEVICE_UUID_FILE="${HAWKBIT_DEVICE_IDENTITY_DIR}/device-uuid"
export HAWKBIT_UUID_SOURCE="${test_root}/uuid-source"

source "${repo_root}/config/etc/hawkbit/device_identity.sh"

first_uuid="123e4567-e89b-42d3-a456-426614174000"
second_uuid="987e6543-e21b-45d3-b654-426614174999"
printf '%s\n' "$first_uuid" > "$HAWKBIT_UUID_SOURCE"

generated_uuid=$(get_or_create_device_uuid)
test "$generated_uuid" = "$first_uuid"
is_valid_uuid_v4 "$generated_uuid"
test "$(stat -c '%a' "$HAWKBIT_DEVICE_IDENTITY_DIR")" = "700"
test "$(stat -c '%a' "$HAWKBIT_DEVICE_UUID_FILE")" = "600"

printf '%s\n' "$second_uuid" > "$HAWKBIT_UUID_SOURCE"
reused_uuid=$(get_or_create_device_uuid)
test "$reused_uuid" = "$first_uuid"

printf '%s\n' "invalid" > "$HAWKBIT_DEVICE_UUID_FILE"
replacement_uuid=$(get_or_create_device_uuid)
test "$replacement_uuid" = "$second_uuid"

mkdir -p "${test_root}/meticulous-user/config"
printf '%s\n' "user data" > "${test_root}/meticulous-user/config/settings"
rm -rf "${test_root}/meticulous-user/"*

test ! -e "${test_root}/meticulous-user/config"
test -f "$HAWKBIT_DEVICE_UUID_FILE"
test "$(get_or_create_device_uuid)" = "$second_uuid"

printf '%s\n' "not-a-uuid" > "$HAWKBIT_UUID_SOURCE"
rm -f "$HAWKBIT_DEVICE_UUID_FILE"
if get_or_create_device_uuid; then
  echo "Expected invalid UUID source to fail" >&2
  exit 1
fi

echo "Hawkbit device identity tests passed"
