#!/bin/bash
set -eo pipefail

# generate-build-info.sh <image_name>
#
# Generates:
#   1. components/repo-info/summary.txt   (consumed by make-rootfs.sh)
#   2. repo-info.tar.gz                   (archive of all repo info)
#   3. images/changes/<channel>/<timestamp>.changelog.yaml
#      Contains a full version snapshot AND a diff against the previous build.

if [ $# -lt 1 ]; then
    echo "Usage: $0 <image_name>"
    exit 1
fi

IMAGE_NAME="$1"

source config.sh

# Source the image-specific version overrides (same logic as update-sources.sh)
if [[ "${IMAGE_NAME}" && "${IMAGE_NAME}" != "nightly" ]]; then
    VERSIONS_FILE="images/${IMAGE_NAME}.versions.sh"
    if [[ -f "$VERSIONS_FILE" ]]; then
        echo "Sourcing $VERSIONS_FILE"
        source "$VERSIONS_FILE"
    else
        echo "Warning: Versions file $VERSIONS_FILE does not exist. Using defaults."
    fi
elif [[ "${IMAGE_NAME}" == "nightly" ]]; then
    echo "Nightly image: using defaults from config.sh"
fi

COMPONENT_NAMES=(
    linux uboot atf imx-mkimage debian
    backend dial web-app watcher firmware
    rauc hawkbit psplash history-ui plotter-ui crash-reporter
)

COMPONENT_DIRS=(
    "$LINUX_SRC_DIR" "$UBOOT_SRC_DIR" "$ATF_SRC_DIR" "$IMX_MKIMAGE_SRC_DIR" "$DEBIAN_SRC_DIR"
    "$BACKEND_SRC_DIR" "$DIAL_SRC_DIR" "$WEB_APP_SRC_DIR" "$WATCHER_SRC_DIR" "$FIRMWARE_SRC_DIR"
    "$RAUC_SRC_DIR" "$HAWKBIT_SRC_DIR" "$PSPLASH_SRC_DIR" "$HISTORY_UI_SRC_DIR" "$PLOTTER_UI_SRC_DIR" "$CRASH_REPORTER_SRC_DIR"
)

COMPONENT_OPTIONAL=(
    false false false false false
    false false false false false
    false false false true true false
)

REPORT_DIR="components/repo-info"
mkdir -p "$REPORT_DIR"

echo "Repository Information Summary - $(date)" > "$REPORT_DIR/summary.txt"
echo "----------------------------------------" >> "$REPORT_DIR/summary.txt"

# Associative array to collect current SHAs
declare -A CURRENT_REVS

for i in "${!COMPONENT_NAMES[@]}"; do
    name="${COMPONENT_NAMES[$i]}"
    dir="${COMPONENT_DIRS[$i]}"
    optional="${COMPONENT_OPTIONAL[$i]}"

    echo "## ${name} ##" >> "$REPORT_DIR/summary.txt"

    if [[ -d "$dir" ]]; then
        pushd "$dir" > /dev/null

        commit_sha=$(git rev-parse HEAD)
        CURRENT_REVS["$name"]="$commit_sha"

        {
            echo "Repository: $(basename "$dir")"
            echo "URL: $(git config --get remote.origin.url 2>/dev/null || echo 'unknown')"
            echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'detached')"
            echo "Commit: ${commit_sha}"
            echo "Last commit details:"
            git log -1 --pretty=format:"%h - %s (%cr) <%an>"
            echo
            echo "Modified files:"
            git diff --name-only HEAD~1 2>/dev/null || echo "(shallow clone, no parent)"
        } > repository-info.txt

        # Copy into the report directory
        cp repository-info.txt "$OLDPWD/$REPORT_DIR/${name}-info.txt"
        cat repository-info.txt >> "$OLDPWD/$REPORT_DIR/summary.txt"

        popd > /dev/null
    else
        if [[ "$optional" == "true" ]]; then
            echo "Warning: Optional component $name directory $dir not found, skipping."
        else
            echo "Warning: Component $name directory $dir not found."
        fi
        echo "No repository information found" >> "$REPORT_DIR/summary.txt"
    fi

    echo "" >> "$REPORT_DIR/summary.txt"
done

tar -czf repo-info.tar.gz -C "$REPORT_DIR" .
echo "Repository information has been compiled and saved in repo-info.tar.gz"

# Yaml changelog 

TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%S")
CHANGES_DIR="images/changes/${IMAGE_NAME}"
mkdir -p "$CHANGES_DIR"
CHANGELOG_FILE="${CHANGES_DIR}/${TIMESTAMP}.changelog.yaml"

declare -A OLD_REVS
PREVIOUS_FILE=""

if [[ -d "$CHANGES_DIR" ]]; then
    PREVIOUS_FILE=$(ls -1 "${CHANGES_DIR}"/*.changelog.yaml 2>/dev/null | sort | tail -n1 || true)
fi

if [[ -n "$PREVIOUS_FILE" && -f "$PREVIOUS_FILE" ]]; then
    echo "Found previous changelog: $PREVIOUS_FILE"

    in_versions=false
    while IFS= read -r line; do
        if [[ "$line" == "versions:" ]]; then
            in_versions=true
            continue
        fi

        if $in_versions && [[ "$line" =~ ^[a-z] ]]; then
            break
        fi
        if $in_versions; then
            # Match lines like:   linux: "f7e1dec23d..."
            if [[ "$line" =~ ^[[:space:]]+([a-z][a-z0-9_-]+):[[:space:]]+\"([a-f0-9]+)\" ]]; then
                OLD_REVS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi
        fi
    done < "$PREVIOUS_FILE"
    echo "Loaded ${#OLD_REVS[@]} previous component versions"
else
    echo "No previous changelog found for channel ${IMAGE_NAME} (first build)"
fi

# Helper: escape a string for YAML double-quoted scalar
yaml_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "$s"
}

{
    echo "channel: \"${IMAGE_NAME}\""
    echo "timestamp: \"${TIMESTAMP}\""

    # Write full version snapshot
    echo "versions:"
    for i in "${!COMPONENT_NAMES[@]}"; do
        name="${COMPONENT_NAMES[$i]}"
        if [[ -n "${CURRENT_REVS[$name]}" ]]; then
            echo "  ${name}: \"${CURRENT_REVS[$name]}\""
        fi
    done

    # Write changes section
    echo "changes:"

    has_changes=false
    for i in "${!COMPONENT_NAMES[@]}"; do
        name="${COMPONENT_NAMES[$i]}"
        dir="${COMPONENT_DIRS[$i]}"
        new_rev="${CURRENT_REVS[$name]:-}"
        old_rev="${OLD_REVS[$name]:-}"

        # Skip components we don't have a current revision for
        if [[ -z "$new_rev" ]]; then
            continue
        fi

        # Skip if unchanged
        if [[ "$old_rev" == "$new_rev" ]]; then
            continue
        fi

        has_changes=true
        echo "  ${name}:"

        if [[ -z "$old_rev" ]]; then
            echo "    old_rev: null"
        else
            echo "    old_rev: \"${old_rev}\""
        fi
        echo "    new_rev: \"${new_rev}\""

        # Get git log between old and new
        if [[ -n "$old_rev" && -d "$dir" ]]; then
            echo "    commits:"

            # The shallow clone may not have enough history. Try to fetch
            # enough commits to cover the range.
            log_output=""
            pushd "$dir" > /dev/null

            # First attempt: check if old_rev is reachable
            if ! git cat-file -e "${old_rev}^{commit}" 2>/dev/null; then
                echo "      # Fetching deeper history to cover range..."  >&2
                git fetch --deepen=200 2>/dev/null || true
            fi

            if git cat-file -e "${old_rev}^{commit}" 2>/dev/null; then
                log_output=$(git log --oneline "${old_rev}..${new_rev}" 2>/dev/null) || true
            fi

            popd > /dev/null

            if [[ -n "$log_output" ]]; then
                while IFS= read -r log_line; do
                    commit_hash="${log_line%% *}"
                    commit_msg="${log_line#* }"
                    echo "      - hash: \"${commit_hash}\""
                    echo "        message: \"$(yaml_escape "$commit_msg")\""
                done <<< "$log_output"
            else
                echo "      []  # git log not available (insufficient history or old rev not reachable)"
            fi
        else
            echo "    commits: []"
        fi
    done

    if [[ "$has_changes" == "false" ]]; then
        echo "  {}  # no component changes detected"
    fi

} > "$CHANGELOG_FILE"

echo "Changelog written to $CHANGELOG_FILE"
echo ""
echo "=== Changes Summary ==="
if [[ "$has_changes" == "true" ]]; then
    for i in "${!COMPONENT_NAMES[@]}"; do
        name="${COMPONENT_NAMES[$i]}"
        new_rev="${CURRENT_REVS[$name]:-}"
        old_rev="${OLD_REVS[$name]:-}"
        if [[ -n "$new_rev" && "$old_rev" != "$new_rev" ]]; then
            if [[ -z "$old_rev" ]]; then
                echo "  ${name}: initial (${new_rev:0:12})"
            else
                echo "  ${name}: ${old_rev:0:12} -> ${new_rev:0:12}"
            fi
        fi
    done
else
    echo "  No changes detected."
fi
