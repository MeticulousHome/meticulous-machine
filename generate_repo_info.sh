#!/bin/bash

REPORT_DIR="components/repo-info"
mkdir -p $REPORT_DIR

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

echo "Repository Information Summary - $(date)" > "$REPORT_DIR/summary.txt"
echo "----------------------------------------" >> "$REPORT_DIR/summary.txt"

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