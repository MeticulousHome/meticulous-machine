#!/bin/bash
set -eo pipefail

DRY_RUN=0
PROMOTE=0
SOURCE_IMAGE=""
DEST_IMAGE=""
SINGLE_COMPONENT_PATH=""

show_help() {
    cat <<EOF
Usage:
  $0 [--dry-run] <image_name> [component_path]
  $0 [--dry-run] --promote <source_image> <destination_image>

Modes:
  <image_name>                         Pin currently checked-out component SHAs to images/<image_name>.versions.sh.
  --promote <source> <destination>      For nightly->beta or beta->stable, merge controlled component branches.

Controlled component repos are MeticulousHome GitHub repos. Custom destination images are file-only pins and never move component branches.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --promote)
            PROMOTE=1
            SOURCE_IMAGE="${2:-}"
            DEST_IMAGE="${3:-}"
            if [[ -z "$SOURCE_IMAGE" || -z "$DEST_IMAGE" ]]; then
                echo "Error: --promote requires <source_image> and <destination_image>."
                show_help
                exit 1
            fi
            shift 3
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$DEST_IMAGE" ]]; then
                DEST_IMAGE="$1"
            elif [[ -z "$SINGLE_COMPONENT_PATH" ]]; then
                SINGLE_COMPONENT_PATH="$1"
            else
                echo "Error: unexpected argument '$1'."
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$DEST_IMAGE" ]]; then
    echo "Error: destination image is required."
    show_help
    exit 1
fi

mkdir -p images
OUTPUT_FILE="images/${DEST_IMAGE}.versions.sh"
FINAL_OUTPUT_FILE="$OUTPUT_FILE"

source config.sh

is_channel_image() {
    [[ "$1" == "nightly" || "$1" == "beta" || "$1" == "stable" ]]
}

is_controlled_repo() {
    local url="$1"
    [[ "$url" =~ github\.com[:/]MeticulousHome/ ]]
}

should_push_branches() {
    [[ "$PROMOTE" -eq 1 && "$SOURCE_IMAGE" == "nightly" && "$DEST_IMAGE" == "beta" ]] ||
        [[ "$PROMOTE" -eq 1 && "$SOURCE_IMAGE" == "beta" && "$DEST_IMAGE" == "stable" ]]
}

should_merge_branches() {
    should_push_branches
}

validate_promotion() {
    if [[ "$PROMOTE" -ne 1 ]]; then
        return
    fi

    if [[ "$SOURCE_IMAGE" == "nightly" && "$DEST_IMAGE" == "stable" ]]; then
        echo "Error: direct promotion from nightly to stable is forbidden. Promote nightly to beta, then beta to stable."
        exit 1
    fi

    if is_channel_image "$DEST_IMAGE"; then
        if ! should_push_branches; then
            echo "Error: channel promotions are limited to nightly->beta and beta->stable. Got ${SOURCE_IMAGE}->${DEST_IMAGE}."
            exit 1
        fi
    else
        echo "Custom destination '${DEST_IMAGE}' requested; creating file pins only."
    fi
}

reset_output_file() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN: would rewrite ${OUTPUT_FILE}"
    else
        printf '#!/bin/bash\n' > "$OUTPUT_FILE"
    fi
}

ensure_output_file() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN: would update ${OUTPUT_FILE}"
    elif [[ ! -f "$OUTPUT_FILE" ]]; then
        printf '#!/bin/bash\n' > "$OUTPUT_FILE"
    fi
}

append_pin() {
    local var_name="$1"
    local value="$2"
    local comment="${3:-}"
    local line

    line="export ${var_name}=\"${value}\""
    if [[ -n "$comment" ]]; then
        line="${line} # ${comment}"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN: ${line}"
    else
        sed -i "/^export ${var_name}=/d" "$OUTPUT_FILE"
        echo "$line" >> "$OUTPUT_FILE"
    fi
}

merge_component_branch() {
    local name="$1"
    local repo_dir="$2"
    local source_rev="$3"
    local destination_ref="refs/remotes/origin/${DEST_IMAGE}"
    local destination_rev final_rev

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN: git -C ${repo_dir} fetch origin refs/heads/${SOURCE_IMAGE}:refs/remotes/origin/${SOURCE_IMAGE}" >&2
        echo "DRY-RUN: git -C ${repo_dir} fetch origin refs/heads/${DEST_IMAGE}:refs/remotes/origin/${DEST_IMAGE}" >&2
        echo "DRY-RUN: require origin/${DEST_IMAGE} to exist for ${name}" >&2
        echo "DRY-RUN: if origin/${DEST_IMAGE} already contains ${source_rev}, pin origin/${DEST_IMAGE}" >&2
        echo "DRY-RUN: otherwise git -C ${repo_dir} checkout -B ${DEST_IMAGE} refs/remotes/origin/${DEST_IMAGE}" >&2
        echo "DRY-RUN: git -C ${repo_dir} merge --no-ff --no-edit ${source_rev}" >&2
        echo "DRY-RUN: git -C ${repo_dir} push origin HEAD:refs/heads/${DEST_IMAGE}" >&2
        echo "<destination-head-after-merge>"
        return
    fi

    if ! git -C "$repo_dir" fetch origin "refs/heads/${SOURCE_IMAGE}:refs/remotes/origin/${SOURCE_IMAGE}" >&2; then
        echo "Error: source branch '${SOURCE_IMAGE}' does not exist in ${name} (${repo_dir})." >&2
        exit 1
    fi

    if ! git -C "$repo_dir" fetch origin "refs/heads/${DEST_IMAGE}:refs/remotes/origin/${DEST_IMAGE}" >&2; then
        echo "Error: destination branch '${DEST_IMAGE}' does not exist in ${name} (${repo_dir})." >&2
        exit 1
    fi

    if ! git -C "$repo_dir" rev-parse -q --verify "$destination_ref" >/dev/null; then
        echo "Error: destination branch '${DEST_IMAGE}' does not exist in ${name} (${repo_dir})." >&2
        exit 1
    fi

    destination_rev="$(git -C "$repo_dir" rev-parse "$destination_ref")"
    git -C "$repo_dir" checkout -B "$DEST_IMAGE" "$destination_ref" >&2

    if git -C "$repo_dir" merge-base --is-ancestor "$source_rev" HEAD; then
        final_rev="$(git -C "$repo_dir" rev-parse HEAD)"
        echo "Destination branch ${DEST_IMAGE} for ${name} already contains ${source_rev}; pinning ${final_rev}." >&2
        echo "$final_rev"
        return
    fi

    if ! git -C "$repo_dir" merge --no-ff --no-edit "$source_rev" >&2; then
        git -C "$repo_dir" merge --abort || true
        git -C "$repo_dir" checkout -B "$DEST_IMAGE" "$destination_rev" >&2
        echo "Error: merge conflict while promoting ${SOURCE_IMAGE} to ${DEST_IMAGE} in ${name} (${repo_dir})." >&2
        exit 1
    fi

    final_rev="$(git -C "$repo_dir" rev-parse HEAD)"
    git -C "$repo_dir" push origin "HEAD:refs/heads/${DEST_IMAGE}" >&2
    echo "$final_rev"
}

pin_component() {
    local name="$1"
    local repo_dir="$2"
    local git_url="$3"
    local branch_var="$4"
    local rev_var="$5"
    local optional="${6:-}"

    if [[ -z "$repo_dir" || ! -d "$repo_dir" ]]; then
        if [[ "$optional" == "optional" ]]; then
            echo "Warn: optional component ${name} directory '${repo_dir}' not found; skipping."
            return
        fi
        echo "Error: component ${name} directory '${repo_dir}' not found."
        exit 1
    fi

    local current_rev current_commit branch_name controlled merge_branch final_rev
    current_rev="$(git -C "$repo_dir" rev-parse HEAD)"
    current_commit="$(git -C "$repo_dir" log --format=%B -n 1 HEAD | head -n1)"
    controlled=0
    if is_controlled_repo "$git_url"; then
        controlled=1
    fi
    merge_branch=0
    if [[ "$controlled" -eq 1 ]] && should_merge_branches; then
        merge_branch=1
    fi

    if [[ "$merge_branch" -eq 1 ]]; then
        branch_name="$DEST_IMAGE"
    else
        branch_name="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        if [[ -z "$branch_name" || "$branch_name" == "HEAD" ]]; then
            branch_name="${!branch_var:-HEAD}"
        fi
    fi

    echo "Pinning ${name}: ${current_rev} (${current_commit})"

    final_rev="$current_rev"
    if [[ "$merge_branch" -eq 1 ]]; then
        final_rev="$(merge_component_branch "$name" "$repo_dir" "$current_rev")"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            current_commit="destination branch HEAD after merge"
        else
            current_commit="$(git -C "$repo_dir" log --format=%B -n 1 "$final_rev" | head -n1)"
        fi
    fi

    if [[ "$merge_branch" -eq 1 ]]; then
        append_pin "$branch_var" "$branch_name"
    fi
    append_pin "$rev_var" "$final_rev" "$current_commit"
}

pin_all_components() {
    pin_component "linux" "$LINUX_SRC_DIR" "$LINUX_GIT" "LINUX_BRANCH" "LINUX_REV"
    pin_component "uboot" "$UBOOT_SRC_DIR" "$UBOOT_GIT" "UBOOT_BRANCH" "UBOOT_REV"
    pin_component "atf" "$ATF_SRC_DIR" "$ATF_GIT" "ATF_BRANCH" "ATF_REV"
    pin_component "imx-mkimage" "$IMX_MKIMAGE_SRC_DIR" "$IMX_MKIMAGE_GIT" "IMX_MKIMAGE_BRANCH" "IMX_MKIMAGE_REV"
    pin_component "debian" "$DEBIAN_SRC_DIR" "$DEBIAN_GIT" "DEBIAN_BRANCH" "DEBIAN_REV"
    if [[ "$DEST_IMAGE" != "factory" ]]; then
        pin_component "backend" "$BACKEND_SRC_DIR" "$BACKEND_GIT" "BACKEND_BRANCH" "BACKEND_REV"
        pin_component "dial" "$DIAL_SRC_DIR" "$DIAL_GIT" "DIAL_BRANCH" "DIAL_REV"
    fi
    pin_component "web-app" "$WEB_APP_SRC_DIR" "$WEB_APP_GIT" "WEB_APP_BRANCH" "WEB_APP_REV"
    pin_component "watcher" "$WATCHER_SRC_DIR" "$WATCHER_GIT" "WATCHER_BRANCH" "WATCHER_REV"
    pin_component "firmware" "$FIRMWARE_SRC_DIR" "$FIRMWARE_GIT" "FIRMWARE_BRANCH" "FIRMWARE_REV"
    pin_component "rauc" "$RAUC_SRC_DIR" "$RAUC_GIT" "RAUC_BRANCH" "RAUC_REV"
    pin_component "hawkbit" "$HAWKBIT_SRC_DIR" "$HAWKBIT_GIT" "HAWKBIT_BRANCH" "HAWKBIT_REV"
    pin_component "psplash" "$PSPLASH_SRC_DIR" "$PSPLASH_GIT" "PSPLASH_BRANCH" "PSPLASH_REV"
    pin_component "history-ui" "${HISTORY_UI_SRC_DIR:-}" "${HISTORY_UI_GIT:-}" "HISTORY_UI_BRANCH" "HISTORY_UI_REV" "optional"
    pin_component "plotter-ui" "$PLOTTER_UI_SRC_DIR" "$PLOTTER_UI_GIT" "PLOTTER_UI_BRANCH" "PLOTTER_UI_REV" "optional"
    pin_component "crash-reporter" "$CRASH_REPORTER_SRC_DIR" "$CRASH_REPORTER_GIT" "CRASH_REPORTER_BRANCH" "CRASH_REPORTER_REV"
}

pin_single_component() {
    case "$SINGLE_COMPONENT_PATH" in
        "$LINUX_SRC_DIR") pin_component "linux" "$LINUX_SRC_DIR" "$LINUX_GIT" "LINUX_BRANCH" "LINUX_REV" ;;
        "$UBOOT_SRC_DIR") pin_component "uboot" "$UBOOT_SRC_DIR" "$UBOOT_GIT" "UBOOT_BRANCH" "UBOOT_REV" ;;
        "$ATF_SRC_DIR") pin_component "atf" "$ATF_SRC_DIR" "$ATF_GIT" "ATF_BRANCH" "ATF_REV" ;;
        "$IMX_MKIMAGE_SRC_DIR") pin_component "imx-mkimage" "$IMX_MKIMAGE_SRC_DIR" "$IMX_MKIMAGE_GIT" "IMX_MKIMAGE_BRANCH" "IMX_MKIMAGE_REV" ;;
        "$DEBIAN_SRC_DIR") pin_component "debian" "$DEBIAN_SRC_DIR" "$DEBIAN_GIT" "DEBIAN_BRANCH" "DEBIAN_REV" ;;
        "$BACKEND_SRC_DIR") pin_component "backend" "$BACKEND_SRC_DIR" "$BACKEND_GIT" "BACKEND_BRANCH" "BACKEND_REV" ;;
        "$DIAL_SRC_DIR") pin_component "dial" "$DIAL_SRC_DIR" "$DIAL_GIT" "DIAL_BRANCH" "DIAL_REV" ;;
        "$WEB_APP_SRC_DIR") pin_component "web-app" "$WEB_APP_SRC_DIR" "$WEB_APP_GIT" "WEB_APP_BRANCH" "WEB_APP_REV" ;;
        "$WATCHER_SRC_DIR") pin_component "watcher" "$WATCHER_SRC_DIR" "$WATCHER_GIT" "WATCHER_BRANCH" "WATCHER_REV" ;;
        "$FIRMWARE_SRC_DIR") pin_component "firmware" "$FIRMWARE_SRC_DIR" "$FIRMWARE_GIT" "FIRMWARE_BRANCH" "FIRMWARE_REV" ;;
        "$RAUC_SRC_DIR") pin_component "rauc" "$RAUC_SRC_DIR" "$RAUC_GIT" "RAUC_BRANCH" "RAUC_REV" ;;
        "$HAWKBIT_SRC_DIR") pin_component "hawkbit" "$HAWKBIT_SRC_DIR" "$HAWKBIT_GIT" "HAWKBIT_BRANCH" "HAWKBIT_REV" ;;
        "$PSPLASH_SRC_DIR") pin_component "psplash" "$PSPLASH_SRC_DIR" "$PSPLASH_GIT" "PSPLASH_BRANCH" "PSPLASH_REV" ;;
        "${HISTORY_UI_SRC_DIR:-}") pin_component "history-ui" "${HISTORY_UI_SRC_DIR:-}" "${HISTORY_UI_GIT:-}" "HISTORY_UI_BRANCH" "HISTORY_UI_REV" "optional" ;;
        "$PLOTTER_UI_SRC_DIR") pin_component "plotter-ui" "$PLOTTER_UI_SRC_DIR" "$PLOTTER_UI_GIT" "PLOTTER_UI_BRANCH" "PLOTTER_UI_REV" "optional" ;;
        "$CRASH_REPORTER_SRC_DIR") pin_component "crash-reporter" "$CRASH_REPORTER_SRC_DIR" "$CRASH_REPORTER_GIT" "CRASH_REPORTER_BRANCH" "CRASH_REPORTER_REV" ;;
        *)
            echo "Error: invalid component path '${SINGLE_COMPONENT_PATH}'."
            exit 1
            ;;
    esac
}

validate_promotion

if [[ -z "$SINGLE_COMPONENT_PATH" && "$DRY_RUN" -ne 1 ]] && should_merge_branches; then
    OUTPUT_FILE="$(mktemp "${FINAL_OUTPUT_FILE}.tmp.XXXXXX")"
    trap 'rm -f "$OUTPUT_FILE"' EXIT
fi

if [[ -n "$SINGLE_COMPONENT_PATH" ]]; then
    ensure_output_file
    pin_single_component
else
    reset_output_file
    pin_all_components
fi

if [[ "$OUTPUT_FILE" != "$FINAL_OUTPUT_FILE" ]]; then
    mv "$OUTPUT_FILE" "$FINAL_OUTPUT_FILE"
    trap - EXIT
fi
