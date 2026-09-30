
test -n "${BOOT_ORDER}" || setenv BOOT_ORDER "A B"
test -n "${BOOT_A_LEFT}" || setenv BOOT_A_LEFT 3
test -n "${BOOT_B_LEFT}" || setenv BOOT_B_LEFT 3

# The rear button request is volatile and is set by U-Boot only after two
# active-low samples. Validate the alternate slot before changing RAUC state.
if test "x${rauc_switch_requested}" = "x1"; then
  setenv rauc_switch_requested
  setenv rauc_switch_from
  setenv rauc_switch_to

  if test "x${rauc_last_booted}" = "xA"; then
    setenv rauc_switch_from A
  elif test "x${rauc_last_booted}" = "xB"; then
    setenv rauc_switch_from B
  else
    # Compatibility for environments created before rauc_last_booted existed:
    # infer the slot that the normal selector can actually boot, not merely the
    # first name in BOOT_ORDER (whose attempts may already be exhausted).
    for BOOT_SLOT in "${BOOT_ORDER}"; do
      if test "x${rauc_switch_from}" = "x"; then
        if test "x${BOOT_SLOT}" = "xA"; then
          if test 0x${BOOT_A_LEFT} -gt 0; then
            setenv rauc_switch_from A
          fi
        elif test "x${BOOT_SLOT}" = "xB"; then
          if test 0x${BOOT_B_LEFT} -gt 0; then
            setenv rauc_switch_from B
          fi
        fi
      fi
    done
  fi

  if test "x${rauc_switch_from}" = "xA"; then
    if test 0x${BOOT_B_LEFT} -gt 0; then
      setenv rauc_switch_to B
      setenv mmcpart 4
      setenv rauc_slot "rauc.slot=B"
    fi
  elif test "x${rauc_switch_from}" = "xB"; then
    if test 0x${BOOT_A_LEFT} -gt 0; then
      setenv rauc_switch_to A
      setenv mmcpart 3
      setenv rauc_slot "rauc.slot=A"
    fi
  fi

  if test -n "${rauc_switch_to}"; then
    echo "Checking alternate slot ${rauc_switch_to} before switching"
    # Keep load and decompression in the same conditional. A semicolon-based
    # saved loadimage command can otherwise decompress stale RAM after a failed
    # filesystem load and incorrectly approve an empty target.
    if load mmc ${mmcdev}:${mmcpart} ${img_addr} ${bootdir}/${image}; then
      if unzip ${img_addr} ${loadaddr}; then
        if run loadfdt; then
          setenv BOOT_ORDER "${rauc_switch_to} ${rauc_switch_from}"
          if test "x${rauc_switch_to}" = "xA"; then
            setenv BOOT_A_LEFT 1
          else
            setenv BOOT_B_LEFT 1
          fi
          echo "Alternate slot ${rauc_switch_to} validated; switching now"
        else
          echo "Rear-button switch refused: alternate slot has no usable device tree"
        fi
      else
        echo "Rear-button switch refused: alternate slot kernel is corrupt"
      fi
    else
      echo "Rear-button switch refused: alternate slot has no usable kernel"
    fi
  else
    echo "Rear-button switch refused: alternate slot is marked unbootable"
  fi

  setenv rauc_switch_from
  setenv rauc_switch_to
fi

setenv rauc_active
setenv rauc_candidate
for BOOT_SLOT in "${BOOT_ORDER}"; do
if test "x${rauc_active}" != "x"; then
    # skip remaining slots
  elif test "x${BOOT_SLOT}" = "xA"; then
    if test 0x${BOOT_A_LEFT} -gt 0; then
      setenv mmcpart 3
      setenv rauc_candidate A
    fi
  elif test "x${BOOT_SLOT}" = "xB"; then
    if test 0x${BOOT_B_LEFT} -gt 0; then
      setenv mmcpart 4
      setenv rauc_candidate B
    fi
  fi

  # An attempt counter above zero only means RAUC has not marked the slot bad.
  # Factory machines ship with an empty slot B, so validate that the candidate
  # actually holds a loadable kernel and device tree before spending an attempt
  # on it. A slot that fails here is skipped without touching its counter, so
  # the selector moves on to the next slot instead of booting into nothing.
  if test -n "${rauc_candidate}"; then
    if load mmc ${mmcdev}:${mmcpart} ${img_addr} ${bootdir}/${image}; then
      if unzip ${img_addr} ${loadaddr}; then
        if run loadfdt; then
          if test "x${rauc_candidate}" = "xA"; then
            echo "Found valid slot A, ${BOOT_A_LEFT} attempts remaining"
            setexpr BOOT_A_LEFT ${BOOT_A_LEFT} - 1
            setenv load_kernel "nand read ${kernel_loadaddr} ${kernel_a_nandoffset} ${kernel_size}"
            setenv rauc_slot "rauc.slot=A"
            setenv rauc_last_booted A
          else
            echo "Found valid slot B, ${BOOT_B_LEFT} attempts remaining"
            setexpr BOOT_B_LEFT ${BOOT_B_LEFT} - 1
            setenv rauc_slot "rauc.slot=B"
            setenv rauc_last_booted B
          fi
          setenv rauc_active "1"
        else
          echo "Slot ${rauc_candidate} skipped: no usable device tree"
        fi
      else
        echo "Slot ${rauc_candidate} skipped: kernel is corrupt"
      fi
    else
      echo "Slot ${rauc_candidate} skipped: no usable kernel"
    fi
    setenv rauc_candidate
  fi
done

if test -n "${rauc_active}"; then
  saveenv
else
  echo "No valid slot found, resetting tries to 3"
  setenv BOOT_A_LEFT 3
  setenv BOOT_B_LEFT 3
  saveenv
  reset
fi

if run loadimage; then run mmcboot; fi;
echo "Bootscript failed, falling back to booting first partition"
