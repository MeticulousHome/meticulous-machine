#!/bin/bash

# Parse command line arguments
CERT=""
KEY=""
VERSION="development"

while [[ $# -gt 0 ]]; do
    case $1 in
        --cert)
            CERT="$2"
            shift 2
            ;;
        --key)
            KEY="$2"
            shift 2
            ;;
        --nightly)
            VERSION="nightly-$(date -u +%Y%m%d)"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$CERT" ] || [ -z "$KEY" ]; then
    echo "Error: Both --cert and --key parameters are required"
    echo "Usage: $0 [--nightly] --cert <cert_file> --key <key_file>"
    exit 1
fi

# Get project root directory (assuming we're running from project root)
PROJECT_ROOT="$(pwd)"
BOOTLOADER_PATH="$PROJECT_ROOT/components/bootloader/build/imx-boot-sd.bin"

# Verify bootloader file exists
if [ ! -f "$BOOTLOADER_PATH" ]; then
    echo "Error: Bootloader file not found at $BOOTLOADER_PATH"
    exit 1
fi

# Create temporary directory structure
TEMP_DIR=$(mktemp -d)
CONTENT_DIR="$TEMP_DIR/bundle"
mkdir -p "$CONTENT_DIR"

# Copy bootloader image using absolute path
cp "$BOOTLOADER_PATH" "$CONTENT_DIR/"

# Create installation script with enhanced debugging
cat > "$CONTENT_DIR/install.sh" << 'EOF'
#!/bin/sh
# Enable debug output
set -x
# Ensure script fails on any error
set -e
echo "Starting bootloader installation script"
echo "RAUC_SLOT_DEVICE=$RAUC_SLOT_DEVICE"
echo "RAUC_MOUNT_PREFIX=$RAUC_MOUNT_PREFIX"
echo "RAUC_BUNDLE_MOUNT_POINT=$RAUC_BUNDLE_MOUNT_POINT"

# Get base device name by removing partition number from RAUC_SLOT_DEVICE
BASE_DEV=$(echo "$RAUC_SLOT_DEVICE" | sed 's/p[0-9]*$//')
echo "BASE_DEV=$BASE_DEV"

# Define bootloader partition
BOOT_PART="${BASE_DEV}p1"
echo "BOOT_PART=$BOOT_PART"

# Verify bootloader partition exists
if [ ! -e "$BOOT_PART" ]; then
    echo "Error: Boot partition not found at $BOOT_PART"
    exit 1
fi

# Check if we can read the partition
if ! dd if="$BOOT_PART" of=/dev/null bs=1k count=1; then
    echo "Error: Cannot read from boot partition"
    exit 1
fi

# Find bootloader image
BOOTLOADER_IMAGE=""
# Check in bundle mount point
if [ -f "${RAUC_BUNDLE_MOUNT_POINT}/imx-boot-sd.bin" ]; then
    BOOTLOADER_IMAGE="${RAUC_BUNDLE_MOUNT_POINT}/imx-boot-sd.bin"
# Check in current directory
elif [ -f "./imx-boot-sd.bin" ]; then
    BOOTLOADER_IMAGE="./imx-boot-sd.bin"
# Check in mount prefix bundle directory
elif [ -f "${RAUC_MOUNT_PREFIX}/bundle/imx-boot-sd.bin" ]; then
    BOOTLOADER_IMAGE="${RAUC_MOUNT_PREFIX}/bundle/imx-boot-sd.bin"
fi

if [ -z "$BOOTLOADER_IMAGE" ]; then
    echo "Error: Could not find bootloader image. Checked:"
    echo "  - ${RAUC_BUNDLE_MOUNT_POINT}/imx-boot-sd.bin"
    echo "  - ./imx-boot-sd.bin"
    echo "  - ${RAUC_MOUNT_PREFIX}/bundle/imx-boot-sd.bin"
    echo "Current directory contents:"
    pwd
    ls -la
    echo "Bundle mount point contents:"
    ls -la "${RAUC_BUNDLE_MOUNT_POINT}/" || true
    echo "Mount prefix contents:"
    ls -la "${RAUC_MOUNT_PREFIX}/" || true
    exit 1
fi

echo "Found bootloader image at: $BOOTLOADER_IMAGE"

# Get sizes
BOOTLOADER_SIZE=$(stat -c%s "$BOOTLOADER_IMAGE")
PARTITION_SIZE=$(blockdev --getsize64 "$BOOT_PART")
echo "Bootloader size: $BOOTLOADER_SIZE bytes"
echo "Partition size: $PARTITION_SIZE bytes"

if [ "$BOOTLOADER_SIZE" -gt "$PARTITION_SIZE" ]; then
    echo "Error: Bootloader image is larger than partition"
    exit 1
fi

# Flash bootloader to partition
echo "Flashing bootloader to $BOOT_PART"
if ! dd if="$BOOTLOADER_IMAGE" of="$BOOT_PART" bs=1k conv=fsync status=progress; then
    echo "Error: Failed to write bootloader"
    exit 1
fi

# Ensure write is complete
sync

# Verify the write
echo "Verifying write..."
if ! cmp -n "$BOOTLOADER_SIZE" "$BOOTLOADER_IMAGE" "$BOOT_PART"; then
    echo "Error: Verification failed - written data does not match source"
    exit 1
fi

echo "Bootloader update completed successfully"
exit 0
EOF

# Make install script executable
chmod +x "$CONTENT_DIR/install.sh"

# Create manifest with dynamic version
cat > "$CONTENT_DIR/manifest.raucm" << EOF
[update]
compatible=rauc-meticulous-update
version=$VERSION
[bundle]
format=verity
[hooks]
filename=install.sh
[image.bootloader]
filename=imx-boot-sd.bin
hooks=install
EOF

# Create bundle using provided cert and key
rauc bundle \
  --cert="$CERT" \
  --key="$KEY" \
  "$CONTENT_DIR" \
  "rauc_meticulous_boot_${VERSION}.raucb"

# Cleanup
rm -rf "$TEMP_DIR"