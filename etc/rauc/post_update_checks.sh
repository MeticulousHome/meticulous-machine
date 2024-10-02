#!/bin/bash

# Function to print status messages
print_status() {
    echo "==== $1 ===="
}

# Function to handle errors
handle_error() {
    echo "✗ Error: $1"
    echo "✗ Something went wrong during the update verification"
    exit 1
}

# Function to attempt to mount the partition with retries
retry_mount() {
    local partition=$1
    local mount_point=$2
    local attempts=2

    for ((i=1; i<=$attempts; i++)); do
        if mount -o ro $partition $mount_point; then
            echo "✓ Mounted partition $partition successfully on attempt $i"
            return 0
        else
            echo "✗ Failed to mount partition $partition on attempt $i"
            if mountpoint -q $mount_point; then
                echo "Unmounting partition $partition before retry"
                umount $mount_point || handle_error "Failed to unmount $partition after a failed mount"
            fi
        fi
    done

    handle_error "Failed to mount partition $partition after $attempts attempts"
}

# Get RAUC information and determine the inactive partition
print_status "Retrieving RAUC information for the inactive partition"
rauc_status=$(rauc status) || handle_error "Failed to retrieve RAUC status"
echo "$rauc_status"

# Determine the inactive partition (rootfs.0 or rootfs.1)
INACTIVE_PARTITION=$(echo "$rauc_status" | grep -E "\[rootfs\.[01]\].*inactive" | sed -E 's/.*\((\/dev\/[^,]+).*/\1/') || handle_error "Failed to determine the inactive partition"

if [ -z "$INACTIVE_PARTITION" ]; then
    handle_error "Unable to identify the inactive partition"
fi

echo "Inactive partition identified: $INACTIVE_PARTITION"

# Determine the mount point dynamically based on inactive partition
MOUNT_POINT="/mnt/inactive_partition"

# Check the filesystem of the inactive partition
print_status "Checking the filesystem of the inactive partition"
fsck -n $INACTIVE_PARTITION || handle_error "Filesystem check failed on the inactive partition"

# Check the disk space of the inactive partition
print_status "Checking the disk space of the inactive partition"
fdisk -l $INACTIVE_PARTITION || handle_error "Failed to check disk space on the inactive partition"

# Mount the inactive partition in read-only mode with retry logic
print_status "Attempting to mount the inactive partition in read-only mode"
mkdir -p $MOUNT_POINT || handle_error "Failed to create mount point directory"

# Attempt to mount the partition, retrying once if it fails
retry_mount $INACTIVE_PARTITION $MOUNT_POINT

# Check the existence and permissions of critical files on the inactive partition
print_status "Checking critical files on the inactive partition"
critical_files=(
    "/etc/fstab"
    "/etc/passwd"
    "/etc/shadow"
    "/etc/hostname"
    "/etc/hosts"
    "/sbin/init"
    "/bin/bash"
    "/lib/systemd/systemd"
    "/etc/rauc/system.conf"
)

for file in "${critical_files[@]}"; do
    if [ -e "$MOUNT_POINT$file" ] || [ -e "$MOUNT_POINT"$(eval echo $file) ]; then
        echo "✓ $file exists on the inactive partition"
        ls -l "$MOUNT_POINT$file" || handle_error "Failed to list permissions for $file"
    else
        echo "✗ $file not found on the inactive partition"
        handle_error "Critical file $file is missing on the inactive partition"
    fi
done

# Check the operating system version on the inactive partition
print_status "Checking the operating system version on the inactive partition"
cat $MOUNT_POINT/etc/os-release || handle_error "Failed to read OS version from the inactive partition"

# Unmount the inactive partition
print_status "Unmounting the inactive partition"
umount $MOUNT_POINT || handle_error "Failed to unmount the inactive partition"

print_status "Verification of the inactive partition completed successfully"
