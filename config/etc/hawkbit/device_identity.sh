#!/bin/bash

HAWKBIT_DEVICE_IDENTITY_DIR="${HAWKBIT_DEVICE_IDENTITY_DIR:-/meticulous-user/.device-identity}"
HAWKBIT_DEVICE_UUID_FILE="${HAWKBIT_DEVICE_UUID_FILE:-${HAWKBIT_DEVICE_IDENTITY_DIR}/device-uuid}"
HAWKBIT_UUID_SOURCE="${HAWKBIT_UUID_SOURCE:-/proc/sys/kernel/random/uuid}"

is_valid_uuid_v4() {
  local uuid="$1"

  [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

generate_uuid_v4() {
  local uuid

  if [ ! -r "$HAWKBIT_UUID_SOURCE" ]; then
    echo "Cannot read UUID source ${HAWKBIT_UUID_SOURCE}" >&2
    return 1
  fi

  IFS= read -r uuid < "$HAWKBIT_UUID_SOURCE"
  if ! is_valid_uuid_v4 "$uuid"; then
    echo "UUID source returned an invalid UUIDv4" >&2
    return 1
  fi

  printf '%s\n' "$uuid"
}

get_or_create_device_uuid() {
  local current_uuid=""
  local generated_uuid
  local temporary_file

  if [ -r "$HAWKBIT_DEVICE_UUID_FILE" ]; then
    IFS= read -r current_uuid < "$HAWKBIT_DEVICE_UUID_FILE"
    if is_valid_uuid_v4 "$current_uuid"; then
      printf '%s\n' "$current_uuid"
      return 0
    fi

    echo "Replacing invalid Hawkbit device UUID at ${HAWKBIT_DEVICE_UUID_FILE}" >&2
  fi

  generated_uuid=$(generate_uuid_v4) || return 1

  # The hidden directory is on the shared user partition so it survives OTA,
  # slot rollback, and the current factory-reset cleanup of /meticulous-user/*.
  if ! mkdir -p "$HAWKBIT_DEVICE_IDENTITY_DIR"; then
    echo "Cannot create Hawkbit device identity directory" >&2
    return 1
  fi
  chmod 700 "$HAWKBIT_DEVICE_IDENTITY_DIR" || return 1

  temporary_file=$(mktemp "${HAWKBIT_DEVICE_UUID_FILE}.tmp.XXXXXX") || return 1
  if ! printf '%s\n' "$generated_uuid" > "$temporary_file"; then
    rm -f "$temporary_file"
    return 1
  fi
  if ! chmod 600 "$temporary_file"; then
    rm -f "$temporary_file"
    return 1
  fi
  if ! mv -f "$temporary_file" "$HAWKBIT_DEVICE_UUID_FILE"; then
    rm -f "$temporary_file"
    return 1
  fi

  printf '%s\n' "$generated_uuid"
}
