#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
EVENT_FILE="$SCRIPT_DIR/act-event.json"

cd "$REPO_ROOT"
source config.sh

failed=0
child_pid=0

function cleanup() {
    if [ $child_pid -ne 0 ]; then
        kill -TERM -$child_pid 2>/dev/null
        kill -KILL -$child_pid 2>/dev/null
    fi
    echo ""
    log_info "Interrupted"
    exit 130
}
trap cleanup INT TERM

function log_info() { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
function log_ok()   { echo -e "\033[0;32m[ OK ]\033[0m  $*"; }
function log_skip() { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
function log_fail() { echo -e "\033[0;31m[FAIL]\033[0m  $*"; }

# mirrors the matrix in build-all-components.yml
declare -A component_build_path=(
    [bootloader]="components/bootloader/build"
    [linux]="components/linux-build"
    [debian]="components/debian-base/rootfs-base.tar.gz"
    [psplash]="components/psplash-build/"
    [rauc]="components/rauc/build"
    [dial]="components/meticulous-dial/src-tauri/target/aarch64-unknown-linux-gnu/release/bundle/deb/meticulous-dial.deb"
    [web]="components/meticulous-web-ui/out/"
    [firmware]="components/meticulous-firmware-build"
    [plotter]="components/meticulous-plotter-ui/build/"
    [crash-reporter]="components/crash-reporter/target"
)

declare -A component_runner=(
    [bootloader]="ubuntu-24.04"
    [linux]="ubuntu-24.04"
    [debian]="ubuntu-24.04"
    [psplash]="ubuntu-22.04"
    [rauc]="ubuntu-22.04"
    [dial]="ubuntu-24.04"
    [web]="ubuntu-24.04"
    [firmware]="ubuntu-24.04"
    [plotter]="ubuntu-24.04"
    [crash-reporter]="ubuntu-24.04"
)

declare -A component_packages=(
    [bootloader]="build-essential gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu u-boot-tools bison flex libssl-dev libgnutls28-dev bc"
    [linux]=""
    [debian]="debootstrap qemu-user-static binfmt-support pv systemd-container"
    [psplash]="qemu-user-static binfmt-support"
    [rauc]="qemu-user-static binfmt-support"
    [dial]="binutils zstd xz-utils pv"
    [web]=""
    [firmware]="python3 python3-venv"
    [plotter]=""
    [crash-reporter]=""
)

declare -A src_dir=(
    [bootloader]="$UBOOT_SRC_DIR"
    [linux]="$LINUX_SRC_DIR"
    [debian]="$DEBIAN_SRC_DIR"
    [psplash]="$PSPLASH_SRC_DIR"
    [rauc]="$RAUC_SRC_DIR"
    [dial]="$DIAL_SRC_DIR"
    [web]="$WEB_APP_SRC_DIR"
    [firmware]="$FIRMWARE_SRC_DIR"
    [plotter]="$PLOTTER_UI_SRC_DIR"
    [crash-reporter]="$CRASH_REPORTER_SRC_DIR"
)

all_components=(bootloader linux debian psplash rauc dial web firmware plotter crash-reporter)

function show_help() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Test GitHub Actions workflows locally using act: validate YAML, dry-run
through act, and build components inside act containers.

Requires at least one option. Use --all to run everything, or pick
individual steps.

Available options:
    --all                     Run validation, dry-runs, and build all components
    --validate                Validate workflow YAML syntax
    --dryrun                  Dry-run workflows through act
    --bootloader              Build bootloader via act
    --linux | --kernel        Build Linux Kernel via act
    --debian                  Build Debian base rootfs via act
    --psplash | --splash      Build psplash via act
    --rauc                    Build RAUC via act
    --dial                    Build Dial app via act
    --web | --webapp          Build WebApp via act
    --firmware                Build firmware via act
    --plotter                 Build Plotter UI via act
    --crash-reporter          Build crash reporter via act
    --help                    Displays this help and exits
EOF
}

GH_TOKEN=""

function check_dependencies() {
    local missing=0
    for cmd in act docker python3; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Required command '$cmd' not found"
            missing=1
        fi
    done
    [ $missing -eq 0 ] || exit 1

    # Try to get a real GitHub token for private repo access
    if command -v gh &>/dev/null; then
        GH_TOKEN="$(gh auth token 2>/dev/null || true)"
    fi
    if [ -z "$GH_TOKEN" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
        GH_TOKEN="$GITHUB_TOKEN"
    fi
    if [ -z "$GH_TOKEN" ]; then
        log_info "No GitHub token found — private repo checkouts will fail"
        log_info "Run 'gh auth login' or export GITHUB_TOKEN to fix this"
    else
        log_ok "GitHub token detected"
    fi
}

function step_validate() {
    echo ""
    log_info "Validating workflow YAML"

    for f in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        if python3 -c "
import yaml, sys
try:
    with open('$f') as fh:
        yaml.safe_load(fh)
except yaml.YAMLError as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" 2>&1; then
            log_ok "yaml: $name"
        else
            log_fail "yaml: $name"
            failed=1
        fi
    done
}

function step_dryrun() {
    echo ""
    log_info "Dry-running workflows through act"

    local act_args=()
    if [ -f "$EVENT_FILE" ]; then
        act_args+=(-e "$EVENT_FILE")
    fi
    act_args+=(--secret "GH_REPO_WORKFLOW=${GH_TOKEN:-dummy}")

    for wf in build-component.yml build-all-components.yml build-nightly-image.yml; do
        if act -n workflow_dispatch -W "$WORKFLOWS_DIR/$wf" "${act_args[@]}" >/dev/null 2>&1; then
            log_ok "dryrun: $wf"
        else
            log_fail "dryrun: $wf"
            failed=1
        fi
    done
}

function run_build() {
    local component=$1
    local dir="${src_dir[$component]}"

    if [ ! -d "$dir" ]; then
        log_skip "build: $component (not checked out)"
        return
    fi

    local build_path="${component_build_path[$component]}"
    local runner="${component_runner[$component]}"
    local packages="${component_packages[$component]}"

    local tmplog
    tmplog="$(mktemp)"
    log_info "Building: $component (log: $tmplog)"

    setsid act workflow_dispatch \
        -W "$WORKFLOWS_DIR/build-component.yml" \
        --input "build-option=$component" \
        --input "build-path=$build_path" \
        --input "image=nightly" \
        --input "runner=$runner" \
        --input "packages=$packages" \
        --secret "GH_REPO_WORKFLOW=${GH_TOKEN:-dummy}" \
        -b \
        >"$tmplog" 2>&1 &
    child_pid=$!
    local rc=0
    wait "$child_pid" || rc=$?
    child_pid=0

    # artifact upload always fails locally, check if the build itself passed
    if [ $rc -ne 0 ] && grep -q "Success - Main Build components" "$tmplog"; then
        log_ok "build: $component"
        rm -f "$tmplog"
        return
    fi

    if [ $rc -eq 0 ]; then
        log_ok "build: $component"
        rm -f "$tmplog"
    else
        log_fail "build: $component (log: $tmplog)"
        failed=1
    fi
}

# ── parse arguments ──────────────────────────────────────────────────

do_validate=0
do_dryrun=0
build_all=0
declare -A selected=()

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

for arg in "$@"; do
    case $arg in
    --all) build_all=1; do_validate=1; do_dryrun=1 ;;
    --validate) do_validate=1 ;;
    --dryrun) do_dryrun=1 ;;
    --bootloader) selected[bootloader]=1 ;;
    --linux | --kernel) selected[linux]=1 ;;
    --debian) selected[debian]=1 ;;
    --psplash | --splash) selected[psplash]=1 ;;
    --rauc) selected[rauc]=1 ;;
    --dial) selected[dial]=1 ;;
    --web | --webapp) selected[web]=1 ;;
    --firmware) selected[firmware]=1 ;;
    --plotter) selected[plotter]=1 ;;
    --crash-reporter | --crash) selected[crash-reporter]=1 ;;
    --help)
        show_help
        exit 0
        ;;
    *)
        echo "Invalid option: $arg"
        show_help
        exit 1
        ;;
    esac
done

# ── main ─────────────────────────────────────────────────────────────

check_dependencies

if [ $do_validate -eq 1 ]; then
    step_validate
fi

if [ $do_dryrun -eq 1 ]; then
    step_dryrun
fi

has_builds=0
for key in "${!selected[@]}"; do
    if [ "${selected[$key]}" -eq 1 ]; then
        has_builds=1
    fi
done

if [ $has_builds -eq 1 ] || [ $build_all -eq 1 ]; then
    echo ""
    log_info "Building components via act"

    for component in "${all_components[@]}"; do
        if [ $build_all -eq 1 ] || [ "${selected[$component]:-0}" -eq 1 ]; then
            run_build "$component"
        fi
    done
fi

# done

echo ""
if [ $failed -ne 0 ]; then
    log_fail "Some tests failed"
    exit 1
fi
log_ok "All tests passed"
