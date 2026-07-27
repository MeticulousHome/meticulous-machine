# Hawkbit device identity

The Hawkbit updater continues to use the existing hostname-based
`target_name`. During the first migration phase, each machine also publishes
the ESP32-owned UUIDv4 as the `next_controller_id` device attribute.

The UUID is stored at:

```text
/meticulous-user/.device-identity/device-uuid
```

The ESP32 NVS value is the source of truth. When the backend receives ESPInfo,
it validates the UUID and atomically updates this VAR-SOM cache whenever the
ESP32 value differs. The backend then restarts the Hawkbit updater so its
generated configuration uses the current cache.

The hidden cache directory is on the shared user partition. It therefore
survives RAUC slot updates and rollbacks. The current backend factory reset
removes `/meticulous-user/*`; shell globbing does not include hidden entries,
so the cache also survives that reset. The directory and file use modes `0700`
and `0600`. The UUID is an opaque identifier, not a credential.

The updater never generates or repairs device identity. If the cache is
missing or invalid, it reports `next_controller_id` as `UNKNOWN` without
changing the active Hawkbit target. The backend repairs the cache only from a
valid ESP32 value.

Before switching `target_name`, fleet validation must confirm:

- every online target reports a valid UUIDv4;
- no two targets report the same UUID;
- the UUID remains unchanged across updater restarts, OTA rollback, and factory
  reset;
- no target reports `UNKNOWN`.

This change depends on coordinated firmware and backend support:

- EspressoFirmware generates and stores the UUIDv4 in ESP32 NVS when an info
  request finds no valid value.
- meticulous-backend parses the UUID from ESPInfo and synchronizes the
  VAR-SOM cache with the ESP32 value.

The updater sends device attributes only when Hawkbit includes the
`configData` link in its DDI response. After deploying this image, request
attributes for the existing targets by setting `requestAttributes` to `true`
through the Hawkbit Management API before auditing `next_controller_id`.
