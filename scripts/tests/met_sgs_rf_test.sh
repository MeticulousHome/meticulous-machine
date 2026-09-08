#!/usr/bin/env bash
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly runner="${repo_root}/scripts/met-sgs-rf-test"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

mkdir -p "${temp_dir}/bin" "${temp_dir}/tool"
touch "${temp_dir}/tool/Murata_NXP_RF_Test_Tool.py"

for command_name in systemctl rfkill ip python3; do
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s %s\\n" "$(basename "$0")" "$*" >> "${MET_SGS_RF_TEST_LOG}"' \
        'exit 0' \
        > "${temp_dir}/bin/${command_name}"
    chmod +x "${temp_dir}/bin/${command_name}"
done

export MET_SGS_RF_TEST_LOG="${temp_dir}/commands.log"
export MET_SGS_RF_TOOL_DIR="${temp_dir}/tool"
export MET_SGS_RF_WIFI_INTERFACE="test-wlan0"

PATH="${temp_dir}/bin:/usr/bin:/bin" "${runner}" > "${temp_dir}/output.log"

grep -Fx 'systemctl stop NetworkManager.service' "${MET_SGS_RF_TEST_LOG}"
grep -Fx 'systemctl stop wpa_supplicant.service' "${MET_SGS_RF_TEST_LOG}"
grep -Fx 'systemctl stop meticulous-backend.service' "${MET_SGS_RF_TEST_LOG}"
grep -Fx 'systemctl stop meticulous-watcher.service' "${MET_SGS_RF_TEST_LOG}"
grep -Fx 'systemctl stop rauc-hawkbit-updater.service' "${MET_SGS_RF_TEST_LOG}"
grep -Fx 'rfkill unblock wifi' "${MET_SGS_RF_TEST_LOG}"
grep -Fx 'ip link show test-wlan0' "${MET_SGS_RF_TEST_LOG}"
grep -Fx 'ip link set test-wlan0 down' "${MET_SGS_RF_TEST_LOG}"
grep -Fx "python3 ${temp_dir}/tool/Murata_NXP_RF_Test_Tool.py" "${MET_SGS_RF_TEST_LOG}"
grep -F 'Run it from the FTDI serial console, not over SSH.' "${temp_dir}/output.log"
grep -F 'Reboot the machine before returning it to normal operation.' "${temp_dir}/output.log"

printf 'met-sgs-rf-test integration test passed.\n'
