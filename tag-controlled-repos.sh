#!/bin/bash
set -eo pipefail

DRY_RUN=0
TAG_NAME=""

show_help() {
    cat <<EOF
Usage:
  $0 [--dry-run] --tag <tag_name>

Tags this repository and checked-out MeticulousHome component repositories with
a lightweight tag, then pushes the tag to each repository remote.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --tag)
            TAG_NAME="${2:-}"
            if [[ -z "$TAG_NAME" ]]; then
                echo "Error: --tag requires a tag name."
                show_help
                exit 1
            fi
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Error: unexpected argument '$1'."
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$TAG_NAME" ]]; then
    echo "Error: --tag is required."
    show_help
    exit 1
fi

if ! git check-ref-format "refs/tags/${TAG_NAME}"; then
    echo "Error: invalid tag name '${TAG_NAME}'."
    exit 1
fi

source config.sh

is_controlled_repo() {
    local url="$1"
    [[ "$url" =~ github\.com[:/]MeticulousHome/ ]]
}

remote_tag_commit() {
    local repo_dir="$1"
    local direct_ref deref_ref remote_lines

    remote_lines="$(git -C "$repo_dir" ls-remote --tags origin "refs/tags/${TAG_NAME}" "refs/tags/${TAG_NAME}^{}")"
    direct_ref="$(awk -v tag="refs/tags/${TAG_NAME}" '$2 == tag { print $1; exit }' <<<"$remote_lines")"
    deref_ref="$(awk -v tag="refs/tags/${TAG_NAME}^{}" '$2 == tag { print $1; exit }' <<<"$remote_lines")"

    if [[ -n "$deref_ref" ]]; then
        echo "$deref_ref"
    else
        echo "$direct_ref"
    fi
}

tag_component() {
    local name="$1"
    local repo_dir="$2"
    local git_url="$3"
    local current_rev local_tag_rev remote_rev

    if ! is_controlled_repo "$git_url"; then
        echo "Skipping ${name}: external repository ${git_url}"
        return
    fi

    if [[ -z "$repo_dir" || ! -d "$repo_dir" ]]; then
        echo "Error: component ${name} directory '${repo_dir}' not found."
        exit 1
    fi

    current_rev="$(git -C "$repo_dir" rev-parse HEAD)"

    echo "Tagging ${name}: ${TAG_NAME} -> ${current_rev}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN: git -C ${repo_dir} tag ${TAG_NAME} ${current_rev}"
        echo "DRY-RUN: git -C ${repo_dir} push origin refs/tags/${TAG_NAME}"
        return
    fi

    remote_rev="$(remote_tag_commit "$repo_dir")"

    if [[ -n "$remote_rev" ]]; then
        if [[ "$remote_rev" == "$current_rev" ]]; then
            echo "Tag ${TAG_NAME} already exists on ${name} at ${current_rev}; leaving it unchanged."
            return
        fi

        echo "Error: remote tag ${TAG_NAME} on ${name} points to ${remote_rev}, not ${current_rev}."
        exit 1
    fi

    if git -C "$repo_dir" rev-parse -q --verify "refs/tags/${TAG_NAME}" >/dev/null; then
        local_tag_rev="$(git -C "$repo_dir" rev-parse "${TAG_NAME}^{commit}")"
        if [[ "$local_tag_rev" != "$current_rev" ]]; then
            echo "Error: local tag ${TAG_NAME} on ${name} points to ${local_tag_rev}, not ${current_rev}."
            exit 1
        fi
    fi

    if ! git -C "$repo_dir" rev-parse -q --verify "refs/tags/${TAG_NAME}" >/dev/null; then
        git -C "$repo_dir" tag "$TAG_NAME" "$current_rev"
    fi
    git -C "$repo_dir" push origin "refs/tags/${TAG_NAME}"
}

tag_component "meticulous-machine" "." "git@github.com:MeticulousHome/meticulous-machine.git"
tag_component "linux" "$LINUX_SRC_DIR" "$LINUX_GIT"
tag_component "uboot" "$UBOOT_SRC_DIR" "$UBOOT_GIT"
tag_component "debian" "$DEBIAN_SRC_DIR" "$DEBIAN_GIT"
tag_component "backend" "$BACKEND_SRC_DIR" "$BACKEND_GIT"
tag_component "dial" "$DIAL_SRC_DIR" "$DIAL_GIT"
tag_component "web-app" "$WEB_APP_SRC_DIR" "$WEB_APP_GIT"
tag_component "watcher" "$WATCHER_SRC_DIR" "$WATCHER_GIT"
tag_component "firmware" "$FIRMWARE_SRC_DIR" "$FIRMWARE_GIT"
tag_component "rauc" "$RAUC_SRC_DIR" "$RAUC_GIT"
tag_component "hawkbit" "$HAWKBIT_SRC_DIR" "$HAWKBIT_GIT"
tag_component "psplash" "$PSPLASH_SRC_DIR" "$PSPLASH_GIT"
tag_component "plotter-ui" "$PLOTTER_UI_SRC_DIR" "$PLOTTER_UI_GIT"
tag_component "crash-reporter" "$CRASH_REPORTER_SRC_DIR" "$CRASH_REPORTER_GIT"
