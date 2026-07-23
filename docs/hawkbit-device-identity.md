# Hawkbit device identity

The Hawkbit updater continues to use the existing hostname-based
`target_name`. During the first migration phase, each machine also publishes a
random UUIDv4 as the `next_controller_id` device attribute.

The UUID is stored at:

```text
/meticulous-user/.device-identity/device-uuid
```

The hidden directory is on the shared user partition. It therefore survives
RAUC slot updates and rollbacks. The current backend factory reset removes
`/meticulous-user/*`; shell globbing does not include hidden entries, so the
identity also survives that reset.

The generated directory and file use modes `0700` and `0600`. The UUID is an
opaque identifier, not a credential.

If the file is missing, the updater generates a UUIDv4 from
`/proc/sys/kernel/random/uuid` and writes it atomically. If the stored value is
not a lowercase RFC 4122 UUIDv4, it is replaced while the UUID is still only a
migration candidate. A source or filesystem failure leaves
`next_controller_id` as `UNKNOWN` without changing the active Hawkbit target.

Before switching `target_name`, fleet validation must confirm:

- every online target reports a valid UUIDv4;
- no two targets report the same UUID;
- the UUID remains unchanged across updater restarts, OTA rollback, and factory
  reset;
- no target reports `UNKNOWN`.

The updater sends device attributes only when Hawkbit includes the
`configData` link in its DDI response. After deploying this image, request
attributes for the existing targets by setting `requestAttributes` to `true`
through the Hawkbit Management API before auditing `next_controller_id`.
