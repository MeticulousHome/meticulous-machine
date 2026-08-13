#!/bin/bash

HAWKBIT_DEVICE_IDENTITY_DIR="${HAWKBIT_DEVICE_IDENTITY_DIR:-/meticulous-user/.device-identity}"
HAWKBIT_DEVICE_UUID_FILE="${HAWKBIT_DEVICE_UUID_FILE:-${HAWKBIT_DEVICE_IDENTITY_DIR}/device-uuid}"

is_valid_uuid_v4() {
  local uuid="$1"

  [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

get_cached_device_uuid() {
  local cached_uuid=""
  local cached_lines=()

  if [ ! -r "$HAWKBIT_DEVICE_UUID_FILE" ]; then
    echo "ESP32 device UUID cache is not available" >&2
    return 1
  fi

  mapfile -t cached_lines < "$HAWKBIT_DEVICE_UUID_FILE"
  if [ "${#cached_lines[@]}" -ne 1 ]; then
    echo "ESP32 device UUID cache is invalid" >&2
    return 1
  fi

  cached_uuid="${cached_lines[0]}"
  if ! is_valid_uuid_v4 "$cached_uuid"; then
    echo "ESP32 device UUID cache is invalid" >&2
    return 1
  fi

  printf '%s\n' "$cached_uuid"
}

render_hawkbit_device_identity() {
  local config_file="$1"
  local target_name="$2"
  local device_uuid=""

  device_uuid=$(get_cached_device_uuid) || device_uuid="UNKNOWN"

  sed -i "s/__TARGET_NAME__/${target_name}/" "$config_file"
  sed -i "s/__NEXT_CONTROLLER_ID__/${device_uuid}/" "$config_file"
}
