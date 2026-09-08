# Rear-button boot partition switch

The rear pinhole button can switch a machine to the other RAUC root filesystem
slot in one power-on. This replaces the former repeated-restart procedure.

## Workflow

1. Power the machine off.
2. Press and hold the button through the small hole on the rear of the machine.
3. Power the machine on while continuing to hold the button.
4. Release the button after the machine begins booting.

U-Boot samples the active-low button twice, 100 ms apart. A confirmed press asks
the boot script to validate and activate the other slot. The serial console logs
the requested slot and whether the switch was accepted or refused.

## Safety behavior

The switch is committed only when the alternate slot:

- is still marked bootable by RAUC (`BOOT_<slot>_LEFT` is greater than zero);
- contains a kernel that U-Boot can load and decompress; and
- contains the device tree required by the installed SOM revision.

If any check fails, `BOOT_ORDER` and both attempt counters remain unchanged and
the current primary slot boots normally. If validation succeeds, the alternate
slot becomes primary with one boot attempt. A successful userspace boot marks it
good and restores the normal three-attempt allowance. If that first boot fails,
the following restart falls back to the previous slot instead of entering a
multi-reboot loop.

## Hardware and release coupling

On I2C Expansion Board Rev E, SW1 drives `SOM_INTn` low through J4. The main board
routes that net to VAR-SOM J3.175 (`UART3_RXD` / `GPIO5_IO26`, legacy GPIO 154)
and supplies its pull-up. The U-Boot device tree must mux that pad as GPIO and
the U-Boot environment must set the volatile `rauc_switch_requested` flag; the
RAUC boot script consumes and clears the flag before saving the environment.

Deploy the matching U-Boot and `u-boot.scr` changes together. The initial release
target for this workflow is the `beta` image channel.
