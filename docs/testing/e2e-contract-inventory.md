# Espresso end-to-end test contract inventory

## Purpose

How these journeys fit the checks from pull request to image is described in
[`validation-architecture.md`](validation-architecture.md).

This document defines the scope that the Espresso end-to-end program must
cover before individual test runners are implemented. The machine-readable
source of truth is [`e2e/contracts/coverage.json`](../../e2e/contracts/coverage.json).

The inventory is owned by `meticulous-machine` because that repository selects
the exact component sources used by an image. Component repositories remain
responsible for their local test implementations; this inventory defines the
cross-repository contract and complete-machine journeys.

## Captured baseline

The first baseline was captured from the `nightly` branches on 2026-08-10 and
last refreshed from the `beta` branches on 2026-09-30:

| Repository | Captured commit | Authority inspected |
| --- | --- | --- |
| meticulous-machine | `84b1ae63f0956896e3e25f37e9bfa46cf5141946` | `config.sh`, image channel manifests, Nginx and systemd units |
| meticulous-dial | `74ca42cb33a64e7ee5df377a06a21453699fd885` | `ScreenType`, route registry, API calls and Socket.IO usage |
| meticulous-backend | `e37dcf3539eef2bf43f0e83e62a7e5b8f982d8bc` | API registration, Socket.IO, allowed actions and emulator traces |
| EspressoFirmware | `63a967c8269650791f17bdc88bdcc1ccd717eda9` | `FikaUart` incoming keys/actions and backend-consumed messages |

The validator intentionally compares discovered source surfaces with the
manifest. Adding or removing an API, route, screen, event, action or image
component requires an explicit inventory update.

## Current inventory

The captured contract was extended for the beta integration on 2026-09-10 and
refreshed on 2026-09-30 (manual mode setup, experimental settings, machine
unlock, report preflight and the `finish` action). It now contains:

- 65 registered Dial screens, grouped by brew lifecycle, profile authoring,
  settings, Wi-Fi, advanced settings and diagnostics.
- 40 API-client methods called by Dial.
- 10 Socket.IO events consumed by Dial and 3 emitted by Dial.
- 70 backend API route patterns, 4 inbound Socket.IO events and 9 outbound
  Socket.IO events.
- 4 existing backend emulation scenarios: idle, home, purge and espresso.
- 6 firmware UART command families, 14 actions and 11 outbound message
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
8. Act on a running shot: skip a stage, end it early and keep it.

`P1` journeys cover settings persistence, Wi-Fi lifecycle, update state and
privacy-safe diagnostics (device information and bug reports also at the
`simulated` tier), creating and deleting profiles, manual mode and the guided
Free Pour.

Each journey declares one or more execution tiers:

- `simulated`: host runner with real Dial/backend processes and simulated ESP.
- `rootfs`: packages, services and routing from the assembled ARM64 rootfs.
- `hil`: physical i.MX8/Variscite and/or ESP32-S3 fixture with safe hardware
  controls.

Each tier has its own status (`"tiers": {"simulated": "implemented",
"rootfs": "planned", "hil": "planned"}`): a journey that passes in the
simulated stack says nothing yet about the built image or a machine. A tier is
`implemented` when a test declaring that journey and tier runs in that tier's CI;
what each test checks is in its docstring. `blocked` marks a tier that cannot be
tested yet, with the reason in `known_gaps`.

Each journey names its `owner`, the repository whose tests back its
`implemented` tiers: `meticulous-integration` for the journeys that need the
firmware, `meticulous-mobile` for the app's journeys its own gates run against
the emulated backend.

The runner keeps it true: meticulous-integration fails when the catalog says
`simulated` is `implemented` for a journey it owns and no test there declares
it, and warns when a test declares a tier the catalog still has as `planned`
(mark it in the same change as the test, or right after). It reads the catalog
of the branch its run pairs with (`stable` for a pull request to `stable`), so
each channel's runs answer to that channel's catalog.
`scripts/validate_e2e_contract.py` prints how many journeys are implemented at
each tier.

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
