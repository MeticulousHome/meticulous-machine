#!/bin/bash

REPORT_DIR="components/repo-info"
mkdir -p $REPORT_DIR

declare -A components=(
    ["bootloader"]="components/bootloader/uboot"
    ["linux"]="components/linux"
    ["debian"]="components/debian-base"
    ["psplash"]="components/psplash"
    ["rauc"]="components/rauc/rauc"
    ["dial"]="components/meticulous-dial"
    ["web"]="components/meticulous-web-app"
    ["firmware"]="components/meticulous-firmware"
    ["history"]="components/meticulous-history-ui"
    ["plotter"]="components/meticulous-plotter-ui"
)

echo "Repository Information Summary - $(date)" > "$REPORT_DIR/summary.txt"
echo "----------------------------------------" >> "$REPORT_DIR/summary.txt"

for component in "${!components[@]}"; do
    echo "## $component ##" >> "$REPORT_DIR/summary.txt"
    
    if [ -f "${components[$component]}/repository-info.txt" ]; then
        # Copy the original file
        cp "${components[$component]}/repository-info.txt" "$REPORT_DIR/${component}-info.txt"
        # Add to the summary
        cat "${components[$component]}/repository-info.txt" >> "$REPORT_DIR/summary.txt"
    else
        echo "No repository information found for $component" >> "$REPORT_DIR/summary.txt"
    fi
    echo "" >> "$REPORT_DIR/summary.txt"
done

tar -czf repo-info.tar.gz -C "$REPORT_DIR" .
echo "Repository information has been compiled and saved in repo-info.tar.gz"