#!/usr/bin/env bash
#
# Shared helpers for scripts that need to know which repositories feed an
# image. There is deliberately no list of repositories here: config.sh (and
# the images/<image>.versions.sh overlay) is the single place that declares a
# component repository as a <NAME>_SRC_DIR / <NAME>_GIT / <NAME>_BRANCH /
# <NAME>_REV set, and update-sources.sh checks out exactly those. These helpers
# read that same declaration back, so adding or re-pointing a repository in
# config.sh is all it takes for caching and fingerprinting to follow.
#
# Source this file from the repository root.

# Load config.sh plus the image overlay, the same way update-sources.sh does.
# Output from the config files goes to stderr so callers can print results on
# stdout.
load_image_config() {
    local image="${1:-}"

    # shellcheck disable=SC1091
    source config.sh >&2

    if [[ -n "${image}" && "${image}" != "nightly" ]]; then
        local versions_file="images/${image}.versions.sh"
        if [[ ! -f "${versions_file}" ]]; then
            echo "Versions file ${versions_file} does not exist." >&2
            return 1
        fi
        # shellcheck disable=SC1090
        source "${versions_file}" >&2
    fi
}

# Print the NAME of every repository declared in the loaded config, i.e. every
# NAME that has both NAME_GIT and NAME_SRC_DIR set.
image_repo_names() {
    local var name
    for var in $(compgen -A variable | grep -E '^[A-Z0-9_]+_GIT$' | sort); do
        name="${var%_GIT}"
        if [[ -n "$(repo_var "${name}" SRC_DIR)" ]]; then
            echo "${name}"
        fi
    done
}

# repo_var NAME FIELD -> value of NAME_FIELD, empty when unset.
repo_var() {
    local var="${1}_${2}"
    echo "${!var:-}"
}

# repo_head NAME -> commit currently checked out in NAME_SRC_DIR.
repo_head() {
    git -C "$(repo_var "$1" SRC_DIR)" rev-parse HEAD
}
