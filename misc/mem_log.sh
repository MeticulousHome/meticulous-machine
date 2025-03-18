#!/bin/bash

INTERVAL=120
OUTPUT_FILE="memory_use.log"

# Function to rename the log file to .old
rotate_logs() {
    if [[ -f "$OUTPUT_FILE" ]]; then
        if [[ -f "$OUTPUT_FILE.old" ]]; then
            # Search for the next available number for the .old file
            i=1
            while [[ -f "$OUTPUT_FILE.old$i" ]]; do
                ((i++))
            done
            mv "$OUTPUT_FILE.old" "$OUTPUT_FILE.old$i"
        fi
        # rename the current log file to .old
        mv "$OUTPUT_FILE" "$OUTPUT_FILE.old"
    fi
}

# Call the function to rotate the logs
rotate_logs

# Create a new log file
> "$OUTPUT_FILE"

echo "Saving memory use data in $OUTPUT_FILE every $INTERVAL seconds..."
echo "Press Ctrl + C to stop the script."

while true; do
    echo "-------------------------- $(date) --------------------------" >> "$OUTPUT_FILE"
    # Log the first 27 processes sorted by memory usage
    top -b -o +%MEM | awk '{$6=$6/1024; $7=$7/1024; $8=$8/1024; print $0}' | head -n 27 >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    sleep $INTERVAL
done
