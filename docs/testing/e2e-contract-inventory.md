# Espresso end-to-end test contract inventory

## Purpose

This document defines the scope that the Espresso end-to-end program must
cover before individual test runners are implemented. The machine-readable
source of truth is [`e2e/contracts/coverage.json`](../../e2e/contracts/coverage.json).

The inventory is owned by `meticulous-machine` because that repository selects
the exact component sources used by an image. Component repositories remain
responsible for their local test implementations; this inventory defines the
cross-repository contract and complete-machine journeys.

## Captured baseline

The first baseline was captured from the `nightly` branches on 2026-08-10:

| Repository | Captured commit | Authority inspected |
| --- | --- | --- |
| meticulous-machine | `220dbcbc41d64069c85f98f46b7c2808c86ee20d` | `config.sh`, image channel manifests, Nginx and systemd units |
| meticulous-dial | `7f4482871d4feb73a5518f26954f33256c3c3d19` | `ScreenType`, route registry, API calls and Socket.IO usage |
| meticulous-backend | `69086ade492fffdb4d304b47281239ca560bb485` | API registration, Socket.IO, allowed actions and emulator traces |
| EspressoFirmware | `f201fbbd4a85cc7c47127f900268700e21468a03` | `FikaUart` incoming keys/actions and backend-consumed messages |

The validator intentionally compares discovered source surfaces with the
manifest. Adding or removing an API, route, screen, event, action or image
component requires an explicit inventory update.

## Current inventory

The captured contract contains:

- 60 registered Dial screens, grouped by brew lifecycle, profile authoring,
  settings, Wi-Fi, advanced settings and diagnostics.
- 36 API-client methods called by Dial.
- 9 Socket.IO events consumed by Dial and 3 emitted by Dial.
- 57 backend API route patterns, 4 inbound Socket.IO events and 9 outbound
  Socket.IO events.
- 4 existing backend emulation scenarios: idle, home, purge and espresso.
- 6 firmware UART command families, 13 actions and 11 outbound message
  families.
- 19 component repositories declared by the image integrator.
- 10 product journeys targeted for future automated execution.

Counts are descriptive, not a quality metric. A passing inventory validation
means the documented contract matches source; it does not yet mean the product
journeys execute successfully.

## Planned journeys

`P0` journeys are release-critical:

1. Reach every registered Dial route through production navigation.
2. Boot the software stack and reach a usable ready/profile state.
3. Select, edit, save and reload a profile.
4. Run a complete simulated espresso lifecycle and record history.
5. Abort a shot and recover safely.
6. Exercise home, purge, tare and calibration at the appropriate test tier.
7. Recover from backend REST/Socket disconnection.

`P1` journeys cover settings persistence, Wi-Fi lifecycle, update state and
privacy-safe diagnostics.

Each journey declares one or more execution tiers:

- `simulated`: host runner with real Dial/backend processes and simulated ESP.
- `rootfs`: packages, services and routing from the assembled ARM64 rootfs.
- `hil`: physical i.MX8/Variscite and/or ESP32-S3 fixture with safe hardware
  controls.

All journeys are marked `planned`. Their status must only change to
`implemented` when an executable test exists and passes in its declared tier.

## Known gaps found during inventory

- Dial subscribes to `water_status`, but no literal backend emitter exists in
  the captured source. Confirm whether the consolidated `status` event replaced
  it before encoding expected behavior.
- Backend emulation contains useful recorded scenarios but lacks a deterministic
  test-only reset/scenario control API.
- The image workflow builds and uploads artifacts without booting the produced
  system or checking runtime service health.

These are evidence-backed gaps, not assumed defects.

## Validation

Validate manifest structure only:

```bash
python scripts/validate_e2e_contract.py --self-check
```

Validate against four clean source checkouts:

```bash
python scripts/validate_e2e_contract.py \
  --machine /path/to/meticulous-machine \
  --dial /path/to/meticulous-dial \
  --backend /path/to/meticulous-backend \
  --firmware /path/to/EspressoFirmware
```

Run the repository tests:

```bash
python -m unittest discover -s tests -p 'test_e2e_contract.py' -v
```

When validation reports `not inventoried`, inspect the source change and add it
to the correct group or contract. When it reports `missing from source`, remove
the item only after confirming that the product surface was intentionally
deleted or renamed. Do not blindly regenerate the manifest, because review of
contract changes is the purpose of this gate.

## What this milestone does not prove

This milestone does not open Dial, run an espresso, boot an image or actuate
hardware. It establishes the audited coverage contract and drift detection
needed to implement those tests without silently omitting screens or protocol
surfaces. Executable Dial/backend journeys are the next milestone.
