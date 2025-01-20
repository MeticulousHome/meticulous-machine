#!/bin/bash

# Directory where all the reports will be saved
REPORT_DIR="components/repo-info"
mkdir -p $REPORT_DIR

# List of components and their artifact directories
declare -A components=(
    ["bootloader"]="components/bootloader/build"
    ["linux"]="components/linux-build"
    ["debian"]="components/debian-base"
    ["psplash"]="components/psplash-build"
    ["rauc"]="components/rauc/build"
    ["dial"]="components/meticulous-dial/out/make/deb/arm64"
    ["web"]="components/meticulous-web-app/out"
    ["firmware"]="components/meticulous-firmware-build"
    ["history"]="components/meticulous-history-ui/build"
    ["plotter"]="components/meticulous-plotter-ui/build"
)

# Create a summary file
echo "Repository Information Summary - $(date)" > "$REPORT_DIR/summary.txt"
echo "----------------------------------------" >> "$REPORT_DIR/summary.txt"

# Gather information from each component
for component in "${!components[@]}"; do
    echo "## $component ##" >> "$REPORT_DIR/summary.txt"
    
    # Search for the repository-info.txt in the component directory
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

# Compress all the information files
tar -czf repo-info.tar.gz -C "$REPORT_DIR" .

echo "Repository information has been compiled and saved in repo-info.tar.gz"