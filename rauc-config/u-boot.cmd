
test -n "${BOOT_ORDER}" || setenv BOOT_ORDER "A B"
test -n "${BOOT_A_LEFT}" || setenv BOOT_A_LEFT 3
test -n "${BOOT_B_LEFT}" || setenv BOOT_B_LEFT 3

setenv rauc_active
for BOOT_SLOT in "${BOOT_ORDER}"; do
if test "x${rauc_active}" != "x"; then
    # skip remaining slots
  elif test "x${BOOT_SLOT}" = "xA"; then
    if test 0x${BOOT_A_LEFT} -gt 0; then
      echo "Found valid slot A, ${BOOT_A_LEFT} attempts remaining"
      setexpr BOOT_A_LEFT ${BOOT_A_LEFT} - 1
      setenv mmcpart 3
      setenv load_kernel "nand read ${kernel_loadaddr} ${kernel_a_nandoffset} ${kernel_size}"
      setenv rauc_slot "rauc.slot=A"
      setenv rauc_active "1"
    fi
  elif test "x${BOOT_SLOT}" = "xB"; then
    if test 0x${BOOT_B_LEFT} -gt 0; then
      echo "Found valid slot B, ${BOOT_B_LEFT} attempts remaining"
      setexpr BOOT_B_LEFT ${BOOT_B_LEFT} - 1
      setenv mmcpart 4
      setenv rauc_slot "rauc.slot=B"
      setenv rauc_active "1"
    fi
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