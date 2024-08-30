#!/bin/bash
# Load the nbd module
echo "Loading nbd module..."
modprobe nbd
echo "nbd module loaded."
while true; do
nbd-client -d /dev/nbd0
if [ $? -eq 0 ]; then
        echo "nbd-client executed successfully."
        break
    else
        echo "Error: nbd-client could not execute successfully. Retrying in 5 seconds..."
        sleep 2
    fi
done
echo "Running rauc status and searching for inactive partition..."
# Capture lines that contain '[rootfs.' from the rauc status output
rootfs_lines=$(rauc status | grep '\[rootfs.')
echo "Extracted lines containing '[rootfs.':"
echo "$rootfs_lines"
# From those lines, select only the one that contains the word 'inactive'
inactive_line=$(echo "$rootfs_lines" | grep 'inactive')
echo "Selected line containing 'inactive':"
echo "$inactive_line"
# Extract the device address that starts with /dev from the inactive line
inactive_partition=$(echo "$inactive_line" | grep -oP '/dev/[^\s,]+')
echo "Extracted inactive partition address:"
echo "$inactive_partition"
# Verify that a partition has been found
if [ -n "$inactive_partition" ]; then
    echo "Inactive partition found: $inactive_partition"
    # Attempt to unmount the inactive partition
    echo "Attempting to unmount the partition $inactive_partition..."
    umount "$inactive_partition"
    if [ $? -eq 0 ]; then
        echo "Partition successfully unmounted."
    else
        echo "Error unmounting the partition."
    fi
else
    echo "No inactive partition found."
fi

# Extract the full user name from the hostname
full_user_name=$(hostname)
echo "Extracted full user name: $full_user_name"
# Update the target_name variable in the config file
sed -i "s/target_name               = .*/target_name               = $full_user_name/" /etc/hawkbit/config.conf.template
if [ $? -eq 0 ]; then
    echo "target_name updated successfully in config.conf.template"
else
    echo "Failed to update target_name in config.conf.template"
fi


# Change directory and execute the rauc-hawkbit-updater command
cd /home/hawkbit/build
./rauc-hawkbit-updater -c /etc/hawkbit/config.conf.template
if [ $? -eq 0 ]; then
    echo "rauc-hawkbit-updater executed successfully."
else
    echo "Failed to execute rauc-hawkbit-updater."
fi
