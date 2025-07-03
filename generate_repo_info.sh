#!/bin/bash

source config.sh
REPORT_DIR="components/repo-info"
mkdir -p $REPORT_DIR

# Function to generate repository info
function generate_repo_info() {
    local dir=$1
    local output=$2
    
    if [ -d "$dir" ]; then
        pushd "$dir" > /dev/null
        {
            echo "Repository: $(basename ${dir})"
            echo "URL: $(git config --get remote.origin.url)"
            echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
            echo "Commit: $(git rev-parse HEAD)"
            echo "Last commit details:"
            git log -1 --pretty=format:"%h - %s (%cr) <%an>"
            echo
            echo "Modified files:"
            git diff --name-only HEAD~1
        } > "$output"
        popd > /dev/null
    else
        echo "Warning: Directory $dir does not exist"
        return 1
    fi
}

declare -A components=(
    ["bootloader"]="${BOOTLOADER_BUILD_DIR}/repo-info/repository-info.txt"
    ["linux"]="${LINUX_BUILD_DIR}/repo-info/repository-info.txt"
    ["debian"]="${DEBIAN_SRC_DIR}/repo-info/repository-info.txt"
    ["psplash"]="${PSPLASH_BUILD_DIR}/repo-info/repository-info.txt"
    ["rauc"]="${RAUC_BUILD_DIR}/repo-info/repository-info.txt"
    ["dial"]="${DIAL_SRC_DIR}/out/make/deb/arm64/repo-info/repository-info.txt"
    ["web"]="${WEB_APP_SRC_DIR}/out/repo-info/repository-info.txt"
    ["firmware"]="${FIRMWARE_OUT_DIR}/repo-info/repository-info.txt"
    ["plotter"]="${PLOTTER_UI_SRC_DIR}/build/repo-info/repository-info.txt"
)

declare -A special_components=(
    ["backend"]="${BACKEND_SRC_DIR}"
    ["watcher"]="${WATCHER_SRC_DIR}"
)

echo "Repository Information Summary - $(date)" > "$REPORT_DIR/summary.txt"
echo "----------------------------------------" >> "$REPORT_DIR/summary.txt"

for component in "${!special_components[@]}"; do
    echo "## $component ##" >> "$REPORT_DIR/summary.txt"
    
    # Create repo-info directory
    if generate_repo_info "${special_components[$component]}" "${special_components[$component]}/repository-info.txt"; then
        repo_info_file="${special_components[$component]}/repository-info.txt"
        if [ -f "$repo_info_file" ]; then
            cp "$repo_info_file" "$REPORT_DIR/${component}-info.txt"
            cat "$repo_info_file" >> "$REPORT_DIR/summary.txt"
        else
            echo "Warning: Repository info file not found at $repo_info_file"
            echo "No repository information found" >> "$REPORT_DIR/summary.txt"
        fi
    else
        echo "No repository information found" >> "$REPORT_DIR/summary.txt"
    fi
    
    echo "" >> "$REPORT_DIR/summary.txt"
done

for component in "${!components[@]}"; do
    echo "## $component ##" >> "$REPORT_DIR/summary.txt"
    
    if [ -f "${components[$component]}" ]; then
        cp "${components[$component]}" "$REPORT_DIR/${component}-info.txt"
        cat "${components[$component]}" >> "$REPORT_DIR/summary.txt"
    else
        echo "Warning: Repository information not found for $component at ${components[$component]}"
        echo "No repository information found" >> "$REPORT_DIR/summary.txt"
    fi
    
    echo "" >> "$REPORT_DIR/summary.txt"
done

tar -czf repo-info.tar.gz -C "$REPORT_DIR" .
echo "Repository information has been compiled and saved in repo-info.tar.gz"
