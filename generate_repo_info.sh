#!/bin/bash

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
    ["bootloader"]="components/bootloader/build/repo-info/repository-info.txt"
    ["linux"]="components/linux-build/repo-info/repository-info.txt"
    ["debian"]="components/debian-base/repo-info/repository-info.txt"
    ["psplash"]="components/psplash-build/repo-info/repository-info.txt"
    ["rauc"]="components/rauc/build/repo-info/repository-info.txt"
    ["dial"]="components/meticulous-dial/out/make/deb/arm64/repo-info/repository-info.txt"
    ["web"]="components/meticulous-web-app/out/repo-info/repository-info.txt"
    ["firmware"]="components/meticulous-firmware-build/repo-info/repository-info.txt"
    ["history"]="components/meticulous-history-ui/build/repo-info/repository-info.txt"
    ["plotter"]="components/meticulous-plotter-ui/build/repo-info/repository-info.txt"
)

declare -A special_components=(
    ["backend"]="components/meticulous-backend"
    ["watcher"]="components/meticulous-watcher"
)

echo "Repository Information Summary - $(date)" > "$REPORT_DIR/summary.txt"
echo "----------------------------------------" >> "$REPORT_DIR/summary.txt"

for component in "${!special_components[@]}"; do
    echo "## $component ##" >> "$REPORT_DIR/summary.txt"
    
    # Create repo-info directory
    mkdir -p "${special_components[$component]}/repo-info"
    output_file="${special_components[$component]}/repo-info/repository-info.txt"
    
    if generate_repo_info "${special_components[$component]}" "$output_file"; then
        cp "$output_file" "$REPORT_DIR/${component}-info.txt"
        cat "$output_file" >> "$REPORT_DIR/summary.txt"
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