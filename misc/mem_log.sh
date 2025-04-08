#!/bin/bash

INTERVAL=300
MEMORY_LOG="/memory-log/memory_use.csv"
PROCESS_INFO="/memory-log/process_info.csv"
FREE_MEMORY="/memory-log/free_memory.csv"  # Nuevo archivo para free -m
PROCESS_NAMES="meticulous-ui|meticulous-dial|meticulous-backend"

# Function to rotate logs
rotate_logs() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if [[ -f "$file.old" ]]; then
            i=1
            while [[ -f "$file.old$i" ]]; do
                ((i++))
            done
            mv "$file.old" "$file.old$i"
        fi
        mv "$file" "$file.old"
    fi
}

# Rotate logs and create new files
rotate_logs "$MEMORY_LOG"
rotate_logs "$PROCESS_INFO"
rotate_logs "$FREE_MEMORY"  # Rotación para el nuevo archivo

echo "timestamp,pid,name,command,minflt/s,majflt/s,VSZ_MB,RSS_MB,%MEM" > "$MEMORY_LOG"
echo "timestamp,pid,process_type,full_command" > "$PROCESS_INFO"
echo "timestamp,total,used,free,shared,buffers,cache,available" > "$FREE_MEMORY"  # Cabecera para free -m

echo "Tracking memory usage every $INTERVAL seconds..."
echo "Logging memory metrics to $MEMORY_LOG"
echo "Logging process info to $PROCESS_INFO"
echo "Logging free memory to $FREE_MEMORY"
echo "Press Ctrl+C to stop."

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

    # Capturar salida de free -m y guardarla en FREE_MEMORY
    free_output=$(free -m)
    
    # Extraer línea de memoria
    mem_line=$(echo "$free_output" | grep "^Mem:")
    if [[ -n "$mem_line" ]]; then
        # Extraer valores (total, used, free, shared, buffers, cache, available)
        read -r _ total used free shared buffers cache available <<< "$mem_line"
        # Escribir al archivo CSV
        echo "$TIMESTAMP,$total,$used,$free,$shared,$buffers,$cache,$available" >> "$FREE_MEMORY"
    fi

    # Get process info and write to process_info.csv
    for pid in $(pgrep -f "$PROCESS_NAMES"); do
        if [[ -e /proc/$pid/cmdline ]]; then
            full_command=$(tr '\0' ' ' < /proc/$pid/cmdline)
            
            # Extract process type
            if [[ "$full_command" =~ --type=([^ ]+) ]]; then
                process_type="${BASH_REMATCH[1]}"
            else
                process_type="main"
            fi
            
            # Escape commas for CSV format
            full_command_escaped="${full_command//,/\\,}"
            
            # Write to process info CSV
            echo "$TIMESTAMP,$pid,$process_type,$full_command_escaped" >> "$PROCESS_INFO"
        fi
    done

    # Obtain process name (command) from smem
    declare -A NAME_MAP
    smem_output=$(smem -w --processfilter="$PROCESS_NAMES" -c "pid command")
    
    # Skip first line (headers)
    readarray -t smem_lines <<< "$smem_output"
    for ((i=1; i<${#smem_lines[@]}; i++)); do
        line="${smem_lines[$i]}"
        # Extract PID (first field) and Command (rest of line)
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.+)$ ]]; then
            pid="${BASH_REMATCH[1]}"
            command="${BASH_REMATCH[2]}"
            if [[ -n "$pid" && -n "$command" ]]; then
                NAME_MAP[$pid]="$command"
            fi
        fi
    done

    # Get metrics with pidstat
    pidstat_output=$(pidstat -r -p $(pgrep -d, -f "$PROCESS_NAMES") 1 1)
    
    # Process pidstat output
    readarray -t pidstat_lines <<< "$pidstat_output"
    processing_data=false
    for line in "${pidstat_lines[@]}"; do
        # Skip empty lines, Linux header or initial lines
        if [[ -z "$line" || "$line" =~ Linux || "$line" =~ CPU ]]; then
            continue
        fi
        
        # Start processing after first line with UID PID
        if [[ "$line" =~ UID[[:space:]]+PID ]]; then
            processing_data=true
            continue
        fi
        
        if [[ "$processing_data" == true ]]; then
            # Check if it's an Average line
            if [[ "$line" =~ ^Average: ]]; then
                read -r _ uid pid minflt majflt vsz rss pmem cmd rest <<< "$line"
                
                # Only process if it's a valid Average line
                if [[ "$uid" =~ ^[0-9]+$ && "$pid" =~ ^[0-9]+$ ]]; then
                    vsz_mb=$(awk "BEGIN {printf \"%.2f\", $vsz/1024}")
                    rss_mb=$(awk "BEGIN {printf \"%.2f\", $rss/1024}")
                    echo "$TIMESTAMP,average,$pid,$cmd,$minflt,$majflt,$vsz_mb,$rss_mb,$pmem" >> "$MEMORY_LOG"
                fi
            else
                # Normal format: timestamp UID PID minflt/s majflt/s VSZ RSS %MEM Command
                read -r timestamp uid pid minflt majflt vsz rss pmem cmd rest <<< "$line"
                
                # Only process if it's a valid data line
                if [[ "$pid" =~ ^[0-9]+$ && -n "$vsz" && -n "$rss" ]]; then
                    command="${NAME_MAP[$pid]:-unknown}"
                    vsz_mb=$(awk "BEGIN {printf \"%.2f\", $vsz/1024}")
                    rss_mb=$(awk "BEGIN {printf \"%.2f\", $rss/1024}")
                    # Escape commas in command to avoid CSV issues
                    command_escaped="${command//,/\\,}"
                    echo "$TIMESTAMP,$pid,$command_escaped,$cmd,$minflt,$majflt,$vsz_mb,$rss_mb,$pmem" >> "$MEMORY_LOG"
                fi
            fi
        fi
    done

    sleep $INTERVAL
done