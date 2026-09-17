# Hawkbit device identity

The Hawkbit updater continues to use the existing hostname-based
`target_name`. During the first migration phase, each machine also publishes
the ESP32-owned UUIDv4 as the `next_controller_id` device attribute.

The UUID is stored at:

```text
/meticulous-user/.device-identity/device-uuid
```

The VAR-SOM generates the initial UUIDv4 using the Linux OS entropy source only
when compatible firmware reports that the ESP32 has no valid UUID. It sends the
candidate through a dedicated write-once UART command. The ESP32 validates and
persists the value in NVS, then reports it back through ESPInfo.

After that assignment, the ESP32 NVS value is the source of truth. The backend
updates this VAR-SOM cache only from a valid UUID confirmed through ESPInfo. If
the confirmed ESP32 value differs, it atomically overwrites the cache and
requests a real Hawkbit updater restart, including when the updater was
inactive, so startup regenerates its local configuration with the current
value. The restart is performed outside the UART reader and is bounded.
Restarting the updater does not itself make Hawkbit request or replace the
target's stored device attributes.

The hidden cache directory is on the shared user partition. It therefore
survives RAUC slot updates and rollbacks. The current backend factory reset
removes `/meticulous-user/*`; shell globbing does not include hidden entries,
so the cache also survives that reset. This is guarded by the backend-owned
factory-reset cleanup regression in `tests/test_factory_reset.py`, which runs
the production cleanup helper and verifies that ordinary user data is removed
while the hidden identity cache remains. The directory and file use modes
`0700` and `0600`. The UUID is an opaque identifier, not a credential.

The updater never generates or repairs device identity. If the cache is
missing or invalid, it reports `next_controller_id` as `UNKNOWN` without
changing the active Hawkbit target.

The backend never copies a previously cached VAR-SOM UUID into an empty or
corrupt ESP32. That state may indicate that the ESP32 was replaced. Instead, it
generates a new candidate, assigns it write-once, waits for the ESP32 to confirm
it, and then replaces the VAR-SOM cache. A valid UUID already stored on the
ESP32 always wins.

Before switching `target_name`, fleet validation must confirm:

- every online target reports a valid UUIDv4;
- no two targets report the same UUID;
- the UUID remains unchanged across updater restarts, OTA rollback, and factory
  reset;
- no target reports `UNKNOWN`.

This change depends on coordinated firmware and backend support:

- EspressoFirmware exposes UUID protocol support in ESPInfo and accepts a
  dedicated write-once assignment only while no valid UUID exists in NVS.
- meticulous-backend generates the initial UUIDv4, sends the assignment, waits
  for ESPInfo confirmation, and then synchronizes the VAR-SOM cache.

The updater sends device attributes only when Hawkbit includes the
`configData` link in its DDI response. Hawkbit controls that link through the
target's server-side `requestAttributes` flag; restarting the updater cannot
set it.

After deploying this image, set `requestAttributes` to `true` through the
Hawkbit Management API for every target before auditing `next_controller_id`.
Repeat that refresh for targets whose first upload reported `UNKNOWN`, including
newly provisioned machines that contacted Hawkbit before ESP32 enrollment
completed. A cache update and updater restart alone do not replace a previously
stored `UNKNOWN` attribute. Do not begin the fleet uniqueness and completeness
audit until the refreshed attributes have been received.
