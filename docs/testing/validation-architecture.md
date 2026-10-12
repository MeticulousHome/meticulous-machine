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

1. **Each repository proves itself on every pull request**, with its neighbours
   mocked. The firmware does not need a backend to test a UART command, the
   backend does not need a firmware to test a handler, the Dial does not need a
   backend to test a screen flow.
2. **Mocks come from contracts, never from memory.** The component that serves an
   interface publishes its contract and proves it complies; consumers mock the
   interface from that contract and from recordings of the real component. A
   mock written by hand drifts: both sides stay green while the combination
   breaks.
3. **Components are combined for real only where versions are chosen**: here, per
   image channel. Asking which firmware a backend pull request should run
   against has one correct answer: the one the image it goes into pins.
4. **What the combination finds goes back down.** A defect found in the image
   becomes a test in the repository that owns the fix, so the next pull request
   catches it in seconds.

## Where each check runs

```
Every pull request, in its repository     Image build (this repository)          Release candidate
──────────────────────────────────────    ─────────────────────────────          ─────────────────
unit and component tests                  1. contract compatibility check   ──▶  hil journeys on a
consumer: mocks from the neighbour's  ──▶ 2. simulated journeys                  lab machine
          contract and recordings         3. rootfs journeys
owner: proves its own contract
                   ▲                                        │
                   └─── recordings of the real stack ───────┘
                        (nightly, and on contract changes)
```

| When | What | Where | Blocks |
|---|---|---|---|
| Every PR of a component | Its own tests; consumer contract tests against the neighbour's contract at the version the target channel pins; provider contract verification | That repository's CI | The merge |
| Nightly and on contract changes | The real components of each channel run together to record UART transcripts and Socket.IO sessions; a recording that changes without a contract change is drift | MeticulousHome/meticulous-integration (private, because it builds the firmware) | Nothing; it opens a finding |
| Every image build | Compatibility of the pinned contracts, then the journeys at `simulated` and `rootfs` tier with the components `versions.sh` pins | Asked by this repository's image workflow, run in meticulous-integration | Publishing the image |
| Release candidate | The journeys at `hil` tier on a lab machine | Self-hosted lab runner attached only to the private repository | The release |

## Contracts

The component that serves an interface owns its contract.

| Interface | Owner | Published as | Consumers mock it from | The owner proves it with | Status |
|---|---|---|---|---|---|
| UART protocol and the NVS keys the backend writes | EspressoFirmware | The protocol description and UART transcripts recorded from the real firmware (fika-sil) | Backend tests replay the transcripts | The firmware SIL (`sil/tests/machine_and_backend/`) | To do: backend tests use hand-written lines today |
| HTTP routes, Socket.IO events and payload keys, default settings | meticulous-backend | `tests/contracts/*.json`, and Socket.IO sessions recorded from real journeys | The Dial's fake backend; meticulous-typescript-api | `tests/test_api_contracts.py`; the `client-contract` job checks meticulous-typescript-api | Snapshots done; recordings to do |
| Profile JSON | espresso-profile-schema | `schema.json` | Backend and firmware validate against it | Its own repository | Done |
| Surfaces and journeys across repositories | meticulous-machine | `e2e/contracts/coverage.json` | Every journey test declares its id and tier | `scripts/validate_e2e_contract.py` | Done |

Recordings carry protocol data only: UART lines and Socket.IO payloads, with logs
filtered. They contain no firmware source; the UART line format is already
public through the backend's parser.

## Versions and compatibility

- `images/<channel>.versions.sh` is the source of truth for what is compatible:
  the components it pins ship together.
- A component pull request to a channel runs its consumer contract tests against
  the neighbour's contract at the commit that channel pins. A backend pull
  request to `beta` uses the firmware contract of `FIRMWARE_REV` in
  `images/beta.versions.sh`.
- A breaking contract change (a removed field, a changed command or meaning) is
  marked as such in the owner's pull request, bumps the contract version, and
  lands together with the consumer's change; this repository then pins both
  together.
- The backend flashes the firmware that the image carries, so for a moment after
  an update or a rollback it talks to the previous image's firmware. The backend
  must keep accepting the previous image's firmware contract; its tests replay
  that channel's previous transcripts.
- Before running any journey, the image build checks that the pinned
  components' contracts are compatible. It is cheap and fails first.

## Journeys

The catalog and its rules are in
[`e2e-contract-inventory.md`](e2e-contract-inventory.md) and
`e2e/contracts/coverage.json`. In this architecture:

- Journeys run per image build (and nightly on each channel's pinned versions),
  never per component pull request: a journey needs versions chosen together.
- `simulated`: host processes of the pinned Dial and backend, with the pinned
  firmware running in fika-sil as the simulated ESP32.
- `rootfs`: the assembled ARM64 rootfs, its packages, services and routing, with
  fika-sil in place of the ESP32.
- `hil`: a physical machine in the lab.
- Every journey test declares the journey and tier it covers (in pytest,
  `@pytest.mark.journey("espresso-complete", tier="simulated")`); the runner
  refuses an id or tier the catalog does not list. A journey's status becomes
  `implemented` only when its test exists and passes at that tier.

## Public and private

meticulous-backend, meticulous-dial and meticulous-machine are public; their
Actions logs and artifacts can be read by anyone. EspressoFirmware is private.

- Anything that builds, runs or logs the firmware runs in a private repository
  (EspressoFirmware or meticulous-integration). Public repositories receive a
  commit status whose link only organisation members can open.
- Details of an unfixed vulnerability stay out of public repositories: code,
  tests, commit messages and pull request descriptions.
- Pull requests from forks get no tokens, so no step that needs the private
  repositories runs for them.

## Ownership

| Repository | Owns |
|---|---|
| EspressoFirmware | Its gates (the SIL); the UART and NVS contract and its proof |
| meticulous-backend | Its gates; the HTTP and Socket.IO contract and its proof; replaying the firmware transcripts |
| meticulous-dial | Its gates; its fake backend built from the backend's contract and recordings |
| meticulous-machine | This document; the catalog and inventory; `versions.sh`; asking for the image validation and blocking on it |
| meticulous-integration | Building and running the real stack with the firmware: the recordings, and the image journeys at every tier |

A component's gates move independently. The catalog, the contracts' format and
the image validation change here, through a pull request to this document.

## Roadmap

| Step | Status |
|---|---|
| Firmware gates (SIL) | Done |
| Backend gates | Done in `gates/main`; to `beta` next |
| Dial gates | In progress |
| Catalog and inventory with drift detection | Done |
| Backend HTTP/Socket.IO contract snapshots, checked against meticulous-typescript-api | Done |
| Firmware UART contract and recorded transcripts; backend replays them | Next |
| Recorded Socket.IO sessions; the Dial's fake backend replays them | To do |
| Contract compatibility check in the image build | To do |
| `simulated` journeys per image (backend and firmware prototype exists in meticulous-integration) | To do |
| `rootfs` journeys per image | To do |
| `hil` journeys on a lab runner | To do |

## Open decisions

- **The contract format for the UART protocol**: a machine-readable description
  (messages, fields, commands, NVS keys) plus transcripts, or transcripts alone
  with the description generated from them.
- **How the Dial runs at `simulated` tier**: its web build in a browser (fast) or
  the Tauri binary under a Wayland compositor (closer to the machine). `rootfs`
  gets the real one either way.
- **How the rootfs boots at `rootfs` tier**: systemd-nspawn on an ARM64 runner, or
  QEMU with the image's kernel and RAUC slots.
- **The lab runner's security**: attached only to the private repository.
