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

assert_invalid_cache() {
  local value="$1"
  local description="$2"

  printf '%b' "$value" > "$HAWKBIT_DEVICE_UUID_FILE"
  if get_cached_device_uuid; then
    echo "Expected ${description} ESP32 device UUID cache to fail" >&2
    exit 1
  fi
}

if get_cached_device_uuid; then
  echo "Expected a missing ESP32 device UUID cache to fail" >&2
  exit 1
fi

mkdir -p "$HAWKBIT_DEVICE_IDENTITY_DIR"
printf '%s\n' "$first_uuid" > "$HAWKBIT_DEVICE_UUID_FILE"
test "$(get_cached_device_uuid)" = "$first_uuid"

assert_invalid_cache "invalid\n" "malformed"
assert_invalid_cache "123e4567-e89b-42d3-a456-42661417400\n" "short"
assert_invalid_cache "123e4567-e89b-42d3-a456-4266141740000\n" "long"
assert_invalid_cache "123E4567-E89B-42D3-A456-426614174000\n" "uppercase"
assert_invalid_cache "123e4567-e89b-12d3-a456-426614174000\n" "non-v4"
assert_invalid_cache "123e4567-e89b-42d3-7456-426614174000\n" "non-RFC-variant"
assert_invalid_cache "" "empty"
assert_invalid_cache "${first_uuid} trailing-content\n" "trailing-content"
assert_invalid_cache "${first_uuid}\nunexpected-line\n" "multi-line"
assert_invalid_cache "${first_uuid}\n\n" "extra-empty-line"

printf '%s\n' "$second_uuid" > "$HAWKBIT_DEVICE_UUID_FILE"
test "$(get_cached_device_uuid)" = "$second_uuid"

render_config() {
  local output_file="$1"
  cp "${repo_root}/config/etc/hawkbit/config.conf.template" "$output_file"
  render_hawkbit_device_identity "$output_file" "machine-hostname-SERIAL"
}

assert_rendered_identity() {
  local expected_uuid="$1"
  local output_file="${test_root}/config.conf"

  render_config "$output_file"

  grep -Eq '^[[:space:]]*target_name[[:space:]]*=[[:space:]]*machine-hostname-SERIAL$' "$output_file"
  grep -Eq "^[[:space:]]*next_controller_id[[:space:]]*=[[:space:]]*${expected_uuid}$" "$output_file"
  if grep -q '__NEXT_CONTROLLER_ID__' "$output_file"; then
    echo "Rendered config retained the next-controller-id placeholder" >&2
    exit 1
  fi
}

assert_rendered_identity "$second_uuid"

rm "$HAWKBIT_DEVICE_UUID_FILE"
assert_rendered_identity "UNKNOWN"

printf '%s\n' "invalid" > "$HAWKBIT_DEVICE_UUID_FILE"
assert_rendered_identity "UNKNOWN"

echo "Hawkbit device identity tests passed"
