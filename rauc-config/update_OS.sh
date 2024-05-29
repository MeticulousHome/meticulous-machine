#!/bin/bash
# Load the nbd module
echo "Loading nbd module..."
modprobe nbd
echo "nbd module loaded."
nbd-client -d /dev/nbd0
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
# Download the configuration file and move it to the build directory
echo "Downloading configuration file..."
curl -o /tmp/config.conf https://raw.githubusercontent.com/MeticulousHome/Demo-Cert/main/config.conf
if [ $? -eq 0 ]; then
    echo "Configuration file downloaded successfully."
    mv /tmp/config.conf /home/hawkbit/build/config.conf
    echo "Configuration file moved to /home/hawkbit/build."
else
    echo "Failed to download the configuration file."
fi
# Extract the full user name from the hostname
full_user_name=$(hostname)
echo "Extracted full user name: $full_user_name"
# Update the target_name variable in the config file
sed -i "s/target_name               = target/target_name               = $full_user_name/" /home/hawkbit/build/config.conf
if [ $? -eq 0 ]; then
    echo "target_name updated successfully in config.conf."
else
    echo "Failed to update target_name in config.conf."
fi
# Download the certificate file and move it to /etc/rauc
echo "Downloading certificate file..."
curl -o /etc/rauc/demo.cert.pem https://raw.githubusercontent.com/MeticulousHome/Demo-Cert/main/demo.cert.pem
if [ $? -eq 0 ]; then
    echo "Certificate downloaded and placed in /etc/rauc successfully."
else
    echo "Failed to download the certificate."
fi
# Change bundle-formats from -plain to verity
echo "Updating system.conf for bundle-formats..."
sed -i 's/bundle-formats=-plain/bundle-formats=verity/' /etc/rauc/system.conf
if [ $? -eq 0 ]; then
    echo "bundle-formats updated successfully in system.conf."
else
    echo "Failed to update bundle-formats in system.conf."
fi

# Change directory and execute the rauc-hawkbit-updater command
cd /home/hawkbit/build
./rauc-hawkbit-updater -c config.conf
if [ $? -eq 0 ]; then
    echo "rauc-hawkbit-updater executed successfully."
else
    echo "Failed to execute rauc-hawkbit-updater."
fi

