# Energy modes: investigation and validation plan

Status: implementation and dedicated-lab investigation in progress, 2026-10-19.
Eight bounded suspend trials were run and the machine was recovered. No power
measurement, compliance claim or certification image has been made.

## Existing implementation

The reviewed beta snapshots are Dial `59b92313`, backend `32ddb73`, firmware
`f8064c0c`, and machine `854f070`. Remote origins were verified before inspection.
The four repositories' branches, commit history and matching open/closed PRs
were searched for sleep, standby, suspend, energy and power-saving work.
Available active and archived Codex task summaries and Ada's brain were also
checked. No competing implementation of system sleep was found in that search.
This does not establish that no unpublished hardware work exists.

- Dial already has a manual **sleep** menu entry and a five-minute idle timer.
  Its idle screen then starts a brightness cycle after another ten minutes:
  3% for 55 seconds and 33% for five seconds. It does not remain at zero.
  DigitalClock also writes brightness independently on mount/unmount.
- Backend implements `/api/v1/machine/backlight`, an animated sysfs brightness
  write. This is neither Linux suspend nor a SoM power-cut operation.
- Firmware receives the rotary encoder and buttons. Idle can still preheat;
  `status == idle` alone is insufficient evidence of disabled heating.
- The image carries old `pm-utils` Wi-Fi/Bluetooth hooks. Their presence does
  not prove that systemd suspend executes them or that resume works.
- [Machine PR63](https://github.com/MeticulousHome/meticulous-machine/pull/63)
  disabled Wi-Fi power saving. Re-enabling it must include reconnection and
  provisioning regression tests, not just a power hypothesis.
- [Dial PR638](https://github.com/MeticulousHome/meticulous-dial/pull/638)
  adds a 24-hour clock setting. It is separate work; preserve its clock behavior
  when this change is integrated.

## Hardware evidence and open questions

The kernel beta device trees identify a VAR-SOM-MX8MN / i.MX8MN platform.
`imx8mn-var-som-meticulous.dts` connects ESP32 to UART1 without an explicit
`wakeup-source` property at that node. Its peripheral supply is documented as
enabled by Q2 after SOM_3V3 rises and is declared always-on. The module includes
an SNVS power-key node. The inspected i.MX UART driver's suspend path explicitly
enables UART wake, so the missing DT property alone does not establish that UART
wake is unavailable. These are source observations, not proof of board wiring,
installed driver behavior or a successful wake on any particular machine.

The firmware defines `ESP32_IN_OUT_PIN` (42), but the inspected runtime does not
use it. The name is not evidence of a SoM power-enable or wake connection. Do not
toggle it, reuse an unknown GPIO, or power off Linux speculatively.

### Dedicated-lab observations

Alú confirmed the target and required correlation through its direct USB debug
UART. With the FTDI console unowned, a unique marker sent from the SSH endpoint
to `ttymxc3` was received through that USB cable together with the same boot ID.
This correlation was repeated after recovery. No other machine was operated.

The installed kernel is `6.12.60-g9e14e4a6eb19`, device-tree model VAR-SOM-MX8MN
V2, firmware `0.2.24-428-g63a967c`. Linux exposes `freeze mem` with `deep`
selected. The CPU uses `ondemand` and its available range is only 1.2–1.5 GHz.
The backend holds `ttymxc0`; its TTY wake setting was disabled. The wake control
is under `tty/power/wakeup`, not `tty/device/power/wakeup`.

| Trial | Result | Limit |
| --- | --- | --- |
| RTC1 alarm while awake | Alarm event count advanced; alarm cleared | Does not alone prove suspend recovery |
| Deep suspend, ten-second RTC fallback | Returned with the same boot; approximately 6.91 seconds excluded from CLOCK_MONOTONIC relative to CLOCK_BOOTTIME; wake IRQ 21 | RTC recovery, not local user wake |
| Deep suspend with ESP TTY wake enabled | Approximately 7.29 seconds suspended; returned on RTC IRQ 21 | Did not establish ESP UART wake |
| Deep suspend with debug TTY wake enabled; newline sent after six seconds | Approximately 3.00 seconds suspended; wake IRQ 17 before the twenty-second RTC fallback | Debug cable wake only; not the Dial input path |

The third resume reported an SDMA channel-zero timeout and a DMA warning in the
UART resume path, followed by failure to prepare RX DMA for `30860000.serial`.
The ESP UART RX counter then stopped advancing. A running backend service and
repeated Socket.IO packets were insufficient recovery evidence: the backend can
re-emit cached sensor values. A backend restart did not restore the UART. A
reboot did; fresh UART byte counts advanced and the newly started backend again
reported the same firmware version. No firmware was flashed.

Temporary wake flags and RTC alarms were restored/cleared. During recovery,
automatic firmware flashing was inhibited and boot preheat disabled; both
settings were restored to their exact original values after fresh reception
was confirmed. Suspend counters showed three entries and zero kernel-reported
failures, despite the UART regression. Therefore these are **not** passing
end-to-end power-mode tests.

### UART DMA diagnostic and stock control

The recovery reboot changed the booted rootfs from slot A to slot B; the API's
image version changed from `2026M1446-beta` to `2026M1468-beta`. The inactive A
slot was then mounted read-only without journal replay for comparison. Both
slots have byte-identical `Image.gz` and meticulous V2 DTB files (SHA-256
prefixes `6738c707449e` and `83a13b6e3b3a` respectively), but their userspace
differs. No image was built or installed by this work. This change of slot is
a confounding variable; the first three trials cannot be treated as a pure
comparison of DMA versus non-DMA behavior.

A one-boot diagnostic removed only `dmas` and `dma-names` from UART1 in the
installed V2 DTB. The normalized DT diff was checked for exactly those two
removed properties. A temporary boot service restored the original DTB on disk
before backend startup, so the next reboot used the original configuration.
The running diagnostic tree had no UART1 DMA property; its UART RX counter
advanced before either trial. The machine was correlated through USB again.

| Diagnostic trial | Result | Limit |
| --- | --- | --- |
| UART1 without DMA, ESP TTY wake enabled, ten-second RTC fallback | Woke on ESP UART IRQ 15 after approximately 0.21 seconds suspended; fresh RX bytes after resume | Existing background traffic immediately wakes the SoM; no button or encoder wake was tested |
| Same tree, ESP TTY wake disabled, ten-second RTC fallback | Woke on RTC IRQ 21 after approximately 7.20 seconds suspended; fresh RX bytes after resume | Bounded RTC recovery only |

Neither diagnostic resume reported the earlier SDMA timeout, RX DMA preparation
failure or kernel warning. After restoring the stock DTB and booting B again,
an ESP-UART wake trial also returned on IRQ 15 with fresh reception and no
measurable deep-sleep interval. A second stock-B trial, with UART wake disabled,
returned on RTC IRQ 21 after approximately 6.90 seconds suspended and retained
fresh UART reception. These stock results contradict treating DMA removal as
the demonstrated solution. A third stock-B trial woke through the debug UART
(IRQ 17, approximately 2.56 seconds suspended) and also retained fresh reception
without the earlier kernel errors. The original failure remains unreliably reproduced;
root cause, repeated recovery and physical-input wake need further investigation.

The original DTB was restored; this PR does not change a device tree or kernel.
The bootloader environment was not edited by this work. No conclusion about
CPU cost without DMA, power savings or production readiness follows from these
trials.

Firmware must quiesce non-wake traffic and inhibit actuators before any product
sleep transition. The backend needs an acknowledged transition and recovery
protocol, including its UART watchdog. Full SoM power removal still requires
board power/wake evidence. No product system-sleep mode is implemented yet.

Before implementing SoM-off plus local wake, establish:

1. Exact machine/PCB/SoM revision and running DTB, kernel and bootloader.
2. Schematic nets for SoM power enable / PMIC ONOFF, their polarity, and who
   remains powered when the SoM is off. Confirm the encoder/button path remains
   powered too. Determine whether "movement" means encoder rotation or another
   physically present sensor.
3. Kernel-supported suspend states and enabled wake sources. For UART wake,
   prove the ESP link can wake the SoM and that background telemetry does not
   immediately wake it again; quiescing telemetry also affects backend watchdogs.
4. A bounded recovery path with an onsite person before the first suspend/off
   trial. Prove heater/motor commands are inactive, no brewing/preheat/update is
   in progress, and restore the exact prior installation afterwards.

Full SoM power removal and suspend-to-RAM are different designs. Neither follows
from changing a screen or CPU governor. A 0.5 W target cannot be guaranteed by
software inspection or a successful resume.

## Regulatory interpretation for engineering

The [current consolidated EU 2023/826 text](https://eur-lex.europa.eu/eli/reg/2023/826)
distinguishes off (no reactivation function), standby (local reactivation and/or
information), and networked standby (remote network reactivation). A local-wake
"super sleep" is therefore a standby candidate, not automatically off.
Current limits are 0.50 W off, 0.50 W standby without information, 0.80 W with
information, and 2 W for non-HiNA networked standby. Off tightens to 0.30 W on
9 May 2027; ordinary standby remains 0.50 W. Automatic power management for
non-drip coffee machines is at most 30 minutes; networked power management is at
most 20 minutes under its applicable conditions. Do not use the product label
"standby" until the applicable requirements are demonstrated.

The authorized laboratory correspondence was read, including its 27 August
table image. It reports 0.45 W with the rear switch off, 3.59 W with the switch
on in the tested off condition, and 3.80 W in networked standby. Its September
method waits 30 minutes to stabilize and averages ten minutes. These are the
laboratory's historical results, not measurements of these candidate changes.
The correspondence is with TÜV; the requested eventual destination is SGS.
The coordinator is resolving the destination. No raw email is retained here.

## Work and acceptance sequence

1. Reuse Dial's existing sleep entry and idle timer. Add an explicit **Screen
   off** entry, make the automatic screen-off sustained, and unmount invisible
   clock animations. Centralize brightness ownership so a clock cleanup cannot
   turn the screen back on. Keep normal wake/navigation behavior.
2. Test real components with a simulated backlight: manual entry, automatic
   entry, sustained zero output, clock cleanup, wake and cancellation of stale
   timers. Capture comparable UI evidence. This proves software behavior only.
3. Use the exclusive, identity-verified lab window from Ada. The window and
   USB/UART correlation above supersede the initial identity hold. A previous
   IP address or historical serial alone is insufficient.
4. Run a read-only power capability inventory, then agree on the supported
   local/network wake design using the actual hardware. Implement and test the
   coordinated backend/firmware/kernel transitions only against that evidence.
5. Validate manual/automatic entry and repeated wake, rejected transitions
   during brew/preheat/update, network behavior, error recovery and rollback on
   the dedicated machine. Retain installed hashes and observed results.
6. Alú checks the behavior. Only after his separate explicit authorization may
   the SGS image be created. Product PRs retain independent review and explicit
   Alú/Kerans approval of the reviewed SHA before their author merges them.

Without a mains power instrument, the office can establish behavior and report
best-effort changes. The laboratory must establish actual consumption and test
classification; a software test is not certification.
