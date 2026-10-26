# Validation architecture

How a change is checked between a pull request in any Meticulous repository and
an image on a customer's machine, and who owns each check. Every component
repository's `AGENTS.md` points here. Read it together with
[`e2e-contract-inventory.md`](e2e-contract-inventory.md), which lists the
cross-repository surfaces and the journeys.

This document lives in meticulous-machine because this repository selects the
component versions that ship together (`images/<channel>.versions.sh`), owns
the journey catalog (`e2e/contracts/coverage.json`) and builds the image.

## Principles

1. **Each repository proves itself on every pull request**: its code, its
   endpoints, its data, its packaging, what it publishes.
2. **Components that talk to each other are tested together on every pull
   request, against the real other side of the same branch.** A backend PR to
   `beta` runs against the firmware of `beta`; a firmware PR to `beta` runs
   against the backend of `beta`; a Dial PR runs against both. No hand-written
   mocks of another component to keep in step: the firmware takes part as its
   own simulator (fika-sil), the binary its CI already built and tested.
3. **The branch is the compatibility.** `beta` with `beta`, `nightly` with
   `nightly`, `stable` with `stable`: what each channel's image pins. A change
   made in two repositories at once lives in branches with the same name, and
   each PR is tested against the other's.
4. **The image checks what no component sees**: the whole system with its
   services, updates and real hardware.
5. **What a higher level finds goes back down** as a test in the repository that
   owns the fix, so the next pull request catches it in seconds.

## Kinds of tests

Each kind answers a different question, so none repeats another. Many fast ones
at the bottom, few slow ones at the top.

| Kind | The question it answers | Example |
|---|---|---|
| Static | Is the code well formed, before running it? | lint, format, type checks |
| Unit | Does this piece, alone, do what it should? | the retraction distance is computed right |
| Component / API | Does this program answer correctly at its edges? | loading a profile while brewing answers 409 and sends nothing to the ESP32 |
| Data | Does the user's data survive an update and a rollback? | an old history database migrates without losing shots |
| Contract | Does what this component publishes stay as described? | the backend's API snapshots; the firmware's `contracts/uart/protocol.json` |
| Packaging and boot | Does what we ship install and start? | the backend .deb installs and boots |
| Integration | Do two or three real programs understand each other? | the real backend with the firmware simulator: a shot from load to history |
| End to end | Can a user finish a task, as a user? | from the Dial: choose a profile, brew, see it in history |
| System | Does the whole image work, with every service? | OTA, crash reporter, routing and services in the built image |
| Hardware in the loop | Does it work on a real machine, with real physics and timing? | a candidate image on a lab machine |

## Where each check runs

| Repository | On every pull request |
|---|---|
| EspressoFirmware | Static, unit (C++), the SIL (the whole firmware against a simulated machine), its UART contract checked against itself; and the backend's integration tests against the backend of its branch (status `integration/backend`) |
| meticulous-backend | Static, unit, API, data (migrations, config), contract (API snapshots), packaging and boot; and its integration tests against the firmware of its branch (status `integration/firmware`) |
| meticulous-dial | Static, unit, component (real components in Chromium with a simulated machine), the build, the Tauri side (Rust), its use of the backend checked against the backend's published contract; and the catalog journeys end to end against the backend and the firmware of its branch (status `integration/e2e`) |
| meticulous-machine | On every image: the system tests in the built image (services, OTA, crash reporter) and the catalog journeys at `rootfs` tier; on release candidates, the `hil` tier |

Anything that needs the firmware runs in MeticulousHome/meticulous-integration
(private); each component's pull request asks for it and receives a commit
status. It pairs the components and uses the firmware's prebuilt fika-sil, so
no firmware is compiled on a backend or Dial pull request. The Dial's journeys
also run on backend and firmware pull requests (status `integration/dial`), so a
change to either that breaks the Dial is caught before it merges.

```
backend PR ───┐                                  ┌──▶ integration/firmware, integration/dial on the backend commit
firmware PR ──┼─▶ meticulous-integration ────────┼──▶ integration/backend, integration/dial on the firmware commit
Dial PR ──────┘   pair by branch, real backend,  └──▶ integration/e2e on the Dial commit
                  fika-sil and Dial of that branch
image build ────▶ system tests, rootfs journeys ────▶ hil journeys on release candidates
```

## Contracts

Each component describes what it publishes and proves it against itself. The
descriptions document the interfaces and catch drift on the owner's side;
consumers are tested against the real component, not against the description.

| Interface | Owner | Description | The owner proves it with |
|---|---|---|---|
| UART protocol and NVS keys | EspressoFirmware | `contracts/uart/protocol.json` | `sil/tests/machine_and_backend/test_uart_contract.py` |
| HTTP routes, Socket.IO events and payload keys, default settings | meticulous-backend | `tests/contracts/*.json` | `tests/test_api_contracts.py`; the `client-contract` job checks meticulous-typescript-api |
| Profile JSON | espresso-profile-schema | `schema.json` | its own repository; backend and firmware validate against it |
| Surfaces and journeys across repositories | meticulous-machine | `e2e/contracts/coverage.json` | `scripts/validate_e2e_contract.py` |

## Versions and compatibility

- `images/<channel>.versions.sh` pins what ships together; for each channel it
  pins that channel's branch of every component, which is why pull requests are
  tested branch with branch.
- A change in two repositories at once lives in branches with the same name; the
  integration tests each pull request against the other's branch.
- The backend flashes the firmware the image carries, so for a moment after an
  update or a rollback it talks to the previous image's firmware. A protocol
  change stays compatible for one step: the backend accepts the old and the new.
- A breaking change to a contract bumps its version and says so in the pull
  request.

## Journeys

The catalog and its rules are in
[`e2e-contract-inventory.md`](e2e-contract-inventory.md) and
`e2e/contracts/coverage.json`.

- `simulated`: real Dial and backend processes with the firmware in fika-sil.
  Runs on the pull requests of the components that take part, with the branch
  pairing above.
- `rootfs`: the assembled ARM64 rootfs, its packages, services and routing, with
  fika-sil in place of the ESP32. Runs per image, in two steps (see "The image
  per build" below).
- `hil`: a physical machine in the lab. Runs on release candidates.
- Every journey test declares the journey and tier it covers (in pytest,
  `@pytest.mark.journey("espresso-complete", tier="simulated")`); the runner
  refuses an id or tier the catalog does not list.
- Each tier of a journey has its own status. A tier is `implemented` once a test
  declaring it runs in that tier's CI; the runner fails when the catalog claims
  a tier no test declares, and warns when a test declares a tier still `planned`.
  So `implemented` at `simulated` never reads as validated on a machine.

## The image per build

Each image a build produces boots on GitHub's ARM64 runners with
systemd-nspawn (`e2e/image/boot.sh`): the image's own systemd and services,
with what only a machine has replaced in that copy, never in the image. No
network beyond the runner, so nothing reaches hawkBit or Sentry; an empty
`/meticulous-user`, as a machine leaving the factory. Both steps are
informative for now: nothing waits for them, and they never fail the build.

1. **The image boots and is what the build says** (`validate-image.yml`, here,
   public; `e2e/image/check_image.py`). The backend runs on its ESP32 emulator.
   It checks that the services start (the ones that need the display, the eMMC,
   the radios or a network are listed in `e2e/image/machine-only-units.txt` with
   what they need), the backend, the web app and the watcher answer through
   nginx, every component and the ESP32 firmware are the ones
   `images/<channel>.versions.sh` pins, a new machine follows its image's update
   channel, and the image's RAUC accepts the build's own bundle.
2. **The image works as a machine** (meticulous-integration's
   `image-journeys.yml`, private, because it runs the firmware). fika-sil is the
   ESP32 on `/dev/ttymxc0`, reporting the version of the firmware the image
   carries so the backend does not flash it; the kernel simulates the I2C bus;
   the GPIO lines are a stand-in, because the runners' kernel lacks the GPIO
   interface v1 the image's gpiod uses. The backend × firmware journeys run
   against the image's backend through its nginx, as the mobile app does:
   identity and version, the status stream, a shot from load to history.

## Public and private

meticulous-backend, meticulous-dial and meticulous-machine are public; their
Actions logs and artifacts can be read by anyone. EspressoFirmware is private.

- Anything that builds, runs or logs the firmware runs in a private repository
  (EspressoFirmware or meticulous-integration). The fika-sil binary is a private
  artifact of the firmware's CI and never leaves the private repositories.
- Public repositories receive a commit status whose link only organisation
  members can open.
- Details of an unfixed vulnerability stay out of public repositories: code,
  tests, commit messages and pull request descriptions.
- Pull requests from forks get no tokens, so no step that needs the private
  repositories runs for them.

## Ownership

| Repository | Owns |
|---|---|
| EspressoFirmware | Its gates (the SIL); the UART contract; publishing fika-sil per branch |
| meticulous-backend | Its gates; the HTTP and Socket.IO contract; its integration tests with the firmware |
| meticulous-dial | Its gates; its journeys with the backend and the firmware |
| meticulous-machine | This document; the catalog and inventory; `versions.sh`; the system tests and image validation |
| meticulous-integration | Pairing the components, running everything that needs the firmware, reporting back |

A component's own gates move independently. The pairing, the reporting and the
catalog change through a pull request to this document.

## Roadmap

| Step | Status |
|---|---|
| Firmware gates (SIL) | Done |
| Backend gates | Done |
| Dial gates | Done in `gates/main`; to `beta` next |
| Catalog and inventory with drift detection | Done; status per tier |
| Firmware UART contract checked against itself | Done |
| fika-sil published per branch by the firmware's CI | Done |
| Backend × firmware on every PR, both directions, paired by branch | Done |
| Dial journeys with the backend and the firmware, on Dial, backend and firmware PRs | Done (11 of 14 journeys at `simulated`); still to cover: every route, backend disconnection, Wi-Fi |
| System tests and `rootfs` journeys per image | Informative on every build: the image boots and is what the build says; the backend × firmware journeys against it. Still to cover: the Dial's journeys, an update over the previous image |
| `hil` journeys on a lab runner | To do |

## Open decisions

- **The Tauri side in the journeys**: at `simulated` the Dial is its web build in
  Chromium, so what only Tauri does (Sentry, the ready markers, Community
  uploads) is not exercised there. Either a Tauri binary under a Wayland
  compositor at `simulated`, or leave it to `rootfs`, which gets the real one.
- **How the rootfs boots at `rootfs` tier**: decided, systemd-nspawn on an ARM64
  runner. QEMU with the image's kernel and RAUC slots stays the option for what
  needs them: the bootloader, the A/B switch, an update over the previous image.
- **Credentials**: one GitHub App for the organisation with the permissions the
  integration needs, instead of separate tokens.
- **The lab runner's security**: attached only to the private repository.
