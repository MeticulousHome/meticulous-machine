# Coordinated suspend: executable design proposal

Status: offline research/prototype, 2026-10-19. `protocol_model.py` models two
peers and their messages; it is not installed in the image, imported by the
backend, or compiled into firmware. It never accesses a machine. No UART command,
HTTP endpoint, firmware capability or power mode is advertised by this change.

The supported candidate is Linux deep suspend with a powered ESP and a verified
UART wake path. SoM power removal is a separate hardware design. Carrier revision,
local physical wake, reliable UART resume and measured consumption remain open.
The earlier A/B-slot confound and failed SDMA hypothesis remain in
[the investigation](../../docs/energy-modes-investigation.md).

## Observed constraints

The reviewed source snapshots remain backend `32ddb73`, firmware `f8064c0c` and
Dial product `b9093ea1`:

- Firmware's `FikaUart::update()` emits sensor/status data every 100 ms. Other
  paths emit event, notification, log, mileage and configuration messages.
  `std::cout`, C stdio and Arduino Serial have callers outside that loop.
- Heater output can be written by a timer/zero-cross ISR, and motor output by a
  worker that ramps a stored setpoint. Stopping a profile or assigning zero once
  is not a persistent actuator inhibit. Boot also performs hardware initialization
  that must be included in the reset-safety analysis.
- Backend `Machine.write()` is the common normal command boundary. The UART
  parser separately has update/reset/enrollment paths; these need the same
  transition ownership. `ESPObservability` reports a valid-message timeout after
  0.5 seconds in its normal phase. Intentional silence needs an explicit phase,
  not fabricated valid-message timestamps or globally disabled diagnostics.
- A live stock-B trial woke immediately on ESP traffic. Fresh UART RX was lost
  in one earlier resume. Kernel counters and repeated cached Socket.IO packets
  do not demonstrate recovery.

The [Linux power ABI](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-power)
provides a wakeup-count handshake to reject a sleep transition when a registered
wake event intervenes. The installed UART driver still needs verification that
events in each entry phase are registered. This mechanism alone must not be
assumed to cover a byte received before the UART's wake detector is armed.
Retried wake messages and a bounded RTC fallback are independent safeguards for
the experimental path, not a measured production sleep policy.

## Transition and ownership

The model below uses symbolic fields. The separate offline integration now owns
a versioned experimental wire grammar in firmware `contracts/uart/experimental`;
it is not an advertised product capability.
Use a fresh transaction identifier and recovery challenge, plus a firmware boot
identifier. They establish freshness/correlation, not cryptographic authentication.

1. **Prepare.** Backend obtains exclusive transition ownership and blocks normal
   commands before sending PREPARE. Both peers reject active brew, preheat,
   update, faults or nonzero outputs. Old firmware without a freshly negotiated
   capability remains unsupported. No guessed idle fallback is allowed.
2. **Inhibit and acknowledge.** Firmware latches the actuator gate below control
   tasks and ISRs, clears motor ramp/setpoints, disarms heater timer output,
   verifies output state, durably records the transaction, closes all ordinary
   TX producers and drains existing TX. READY is a final control frame only after
   every barrier succeeds. If anything fails, stay inhibited and report/wake;
   do not acknowledge readiness.
3. **Suspend.** Backend accepts only the matching READY, arms the verified wake
   source and bounded RTC fallback, completes the kernel wakeup-count handshake,
   then requests the supported sleep state. A wake already received cancels entry.
   An aborted or failed suspend still enters protocol recovery; it never directly
   releases command ownership. Restore temporary OS settings after recovery.
4. **Wake.** Firmware consumes the wake gesture, including its release/click tail;
   it must not become a brew/preheat command. Only bounded control frames may pass
   the TX gate. Retry until the bounded budget expires or recovery is acknowledged.
   On expiry remain inhibited in a fault state. A lease prevents a crashed host
   from leaving the firmware silently armed forever. Lease duration and retries
   require measurement; the model deliberately supplies no production defaults.
5. **Recover.** Backend sends a fresh RESUME challenge, requires matching AWAKE
   and a newly produced UART sample newer than the acknowledgement's baseline,
   then sends RELEASE. Cached telemetry, old boot/session IDs and an out-of-order
   sample cannot satisfy this sequence. Normal commands remain blocked until
   RELEASED. RELEASE is idempotent so a lost acknowledgement can be retried.
   Firmware output remains zero; old setpoints and the wake gesture are not replayed.
6. **Failure.** Absolute recovery deadlines and retry counts cap the exchange.
   Timeout never enables actuators. A restarted backend begins unsynchronized,
   with commands blocked; a fresh status showing an inhibited peer cannot clear
   that gate. Reconciliation of a persisted session is required before recovery.

The model distinguishes the peer states because RELEASED can be lost after the
firmware has accepted RELEASE. In that interval the backend remains blocked,
while firmware has accepted the explicit release and holds zero output. This is
not simultaneous distributed state: the real integration must ensure local input
and background controllers cannot revive stale work after that explicit release.

## Required wake interactions

Wake must support encoder rotation/press, context, tare and scale interaction.
The ESP must keep their acquisition paths active during Linux deep suspend.
Suppressing all acquisition together with UART telemetry would make these wake
sources unavailable. Only a bounded wake/control frame may pass the host TX gate.

Button suppression must happen before the firmware callbacks modify driver
flags, append encoder steps, tare or calibrate. It must consume the initial input
and the full release/click/double/long tail, including a button held throughout
recovery. The UART parser, backend forwarding and Dial must not replay old queued
events after resume. Test all three buttons and both rotation directions before,
during and after the transition, including same-turn/batched delivery.

The Acaia interface currently provides weight and stability, not a touch signal.
The scale needs power, fresh samples and a valid communication state throughout
sleep. A load-change detector requires measured idle noise, thermal drift and
representative touch/place/remove-cup traces before selecting its criterion; no
numerical threshold is chosen by this proposal. Do not reuse the Dial overlay's
2 g visibility rule as evidence. Mere touch producing no measurable load change
is not presently observable. Reconnects, stale samples and tare/baseline resets
must not be misclassified as user interaction.

SoM-off still requires a verified always-powered detection and hardware power-on
path from these sources. A UART wake that works in deep suspend does not establish
that capability, and the laboratory carrier revision remains unconfirmed.

## Required adapters and unresolved risks

The following are integration requirements, not capabilities proven by the model:

| Boundary | Required implementation and evidence |
| --- | --- |
| Actuation | Shared inhibit checked at every final motor/heater write and enable path, including ISR, calibration, startup and control-worker races. Prove with SIL fault injection and hardware outputs; a Python boolean is not evidence. |
| UART TX | One per-link gate for normal producers, with a separate bounded control-frame path. Drain pending library/driver/FIFO buffers before READY; discard stale buffered application output on recovery. Test interleaved writers, lock ordering, backpressure and RX continuity. |
| Reset | Persist armed intent before READY; restore inhibit before any actuator initialization after ESP reset. ROM/panic output is a fault wake source, not normal quiet operation. Prove watchdog/brownout/partial NVS-write behavior and flash-wear policy. |
| Backend | Serialize writes, API/actions, firmware update/reset and automatic settings sync against the transition. Add an explicit observability phase and distinguish freshly parsed UART data from cached status. |
| OS | Validate driver wake registration, supported deep state, syscall/abort handling, wakeup-count races, RTC fallback ownership and post-resume UART freshness. Use a clock including suspended time for deadlines; handle ESP tick rollover. |
| Rollback | Old firmware never receives a sleep request. Define safe recovery if userspace or firmware rolls back with an outstanding transaction; never erase the intent merely to make the old software boot. |

### Offline implementation candidates

- [Firmware PR #536](https://github.com/MeticulousHome/EspressoFirmware/pull/536)
  adds the separate `energy-runtime-experiment-s3` full-source build, alongside
  the earlier actuator primitives and isolated SDK UART probe. The runtime begins
  inhibited before actuator initialization, persists armed/released records in a
  separate NVS namespace, refuses mileage partition formatting after init errors,
  and reconciles boot/session/sequence identities. A fresh
  single-use negotiation nonce rejects delayed PREPARE frames. Recovery requires
  a strictly newer completed pressure conversion before a zero-output release.
  Counted work ownership and generation checks cover controllers, ordinary UART
  commands/output, and raw/decoded inputs before driver or calibration effects.
  Held buttons remain consumed until both physical release and decoder completion.
  Its normal product build does not enable this protocol; neither experimental
  build is a release artifact. Source snapshot:
  `063a170b10b68dd2ae534460008eae23068f7bed`.
- [Backend PR #458](https://github.com/MeticulousHome/meticulous-backend/pull/458)
  adds an unused durable session owner around the actual one-way command writer.
  It serializes complete multipart transactions and closes admission before a
  transition waits for ownership. Requests capture one immutable admission
  snapshot before any lock wait, binding open state, generation and writer.
  Closed requests are refused immediately; delayed multipart input and lock
  waiters cannot cross a complete close/recover cycle. A later transition also
  prevents an earlier recovery from publishing a writer, even
  when the later request times out. Host intent uses file and directory fsync;
  uncertain normal writes remain recorded across process restart and poison the
  owner. Recovery retains pending intent until a fresh matching RELEASED and a
  durable completion, then creates a new writer lease. It is not connected to
  `Machine.write()` or API/settings/reset/update producers. Source snapshot:
  `dbcec9782505de8921503aaa62633f722be836d5`.
- [Dial PR #644](https://github.com/MeticulousHome/meticulous-dial/pull/644)
  consumes encoder/context/tare wake gestures at the UI event boundary, including
  a held context button that produces no decoded click. It does not suppress
  actions performed directly by firmware or implement scale wake.
  Source snapshot: `3e15add16753c13b509665b82eeeab8bc8dff7fc`.

The private firmware integration imports the actual pinned backend candidate
and exercises both motor configurations through real firmware parsing, journals,
GPIO/PWM and button callbacks. Tests include SIGKILL without graceful/periodic
journal saving, lost acknowledgements, failed/corrupt persistence, stale samples,
and held-button/calibration effects. SIL proves these paths under its simulated
scheduler and devices; it does not prove ESP32 flash power-loss behavior, SDK
FIFO drain, physical output continuity or hardware wake.

Product integration remains open: all backend producers and observability must
share ownership; Linux suspend/wakeup-count/RTC and bounded wake retransmission
are absent. An uncertain partial legacy write needs external transport/reset
reconciliation. Cold-reset release also needs position/homing and scale-state
readiness before product commands may be enabled. NVS capacity/endurance, host
per-transaction fsync cost, old-software rollback, physical scale criteria and
hardware validation remain gates. No candidate was deployed during this offline
phase; the earlier installed screen preview predates the new input gate.

A candidate TX design is to route console stdio through the installed UART driver
and intercept the common UART0 write boundary, including Arduino's write entry
points, while reserving a serialized control-frame path. The installed Arduino
2.0.17 source sends `uartWrite` and `uartWriteBuf` through `uart_write_bytes`.
[ESP-IDF 4.4 VFS documentation](https://docs.espressif.com/projects/esp-idf/en/v4.4/esp32/api-reference/storage/vfs.html)
describes different default FIFO and driver-backed console paths. Merely wrapping
`uart_write_bytes` without routing and auditing the console is insufficient.
Changing VFS routing also affects blocking behavior and RX ownership, so this
candidate must be tested before activation. SDK/ROM direct writes need separate
classification as normal producers or fault wake sources.

The local framework audit found an additional bypass: Arduino's `log_printfv`
uses `ets_printf`; `uart_install_putc` can route that to a callback writing the
UART FIFO directly. The installed `libvfs.a` also references `uart_write_bytes`,
confirming a driver path exists but not that all console calls currently use it.
A valid transport experiment must exercise both paths and inspect the linked
binary/captured UART; the model's single TX gate does not prove that coverage.

Carrier confirmation is required before claiming local wake or SoM-off support.
It does not prevent offline transport/actuator development, but neither a passing
model nor a successful compile authorizes a physical deployment. Ada coordinates
the next exclusive lab window and USB/UART identity confirmation.

## Model verification

Run from the repository root:

```sh
python3 -m unittest -v tests/test_energy_mode_protocol.py
```

Thirteen tests cover independent preflight rejection, every readiness barrier,
ordinary TX sources, kernel/fallback gating, wake at three entry stages, stale or
out-of-order replies, lost READY/WAKE/RELEASED, lease expiry, host crash, persisted
intent after ESP reboot, and absolute recovery deadlines. Injected virtual-time
budgets exist to exercise ordering; they are not acceptance thresholds for hardware.

Three planted model regressions are rejected: accepting commands on READY,
treating a sample equal to the recovery baseline as fresh, and enabling firmware
outputs when retries expire. All mutations were removed and the thirteen tests
rerun successfully, together with the two read-only inventory tests.

Before a product transition is enabled, the same cases must be run through the
real backend UART parser, firmware SIL and real transport/actuator adapters, then
repeated on the identified lab with physical controls. No compliance or wattage
claim follows from this prototype. No certification image is produced.
