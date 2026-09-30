#!/bin/bash

# Parse command line arguments 
CERT=""
KEY=""
VERSION=""

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
        --variant)
            VARIANT="$2-$(date -u +%Y%m%d)"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z $VARIANT ]]; then
    echo "Variant must be passed"
    exit 1
fi

# Validate required parameters
if [ -z "$CERT" ] || [ -z "$KEY" ]; then
    echo "Error: Both --cert and --key parameters are required"
    echo "Usage: $0 --variant <variant> --cert <cert_file> --key <key_file>"
    exit 1
fi

# Get project root directory
PROJECT_ROOT="$(pwd)"
BOOTLOADER_PATH="$PROJECT_ROOT/components/bootloader/build/imx-boot-sd.bin"
BOOT_SCRIPT_PATH="$PROJECT_ROOT/components/bootloader/build/u-boot.scr"

# Verify bootloader file exists
if [ ! -f "$BOOTLOADER_PATH" ]; then
    echo "Error: Bootloader file not found at $BOOTLOADER_PATH"
    exit 1
fi
if [ ! -f "$BOOT_SCRIPT_PATH" ]; then
    echo "Error: Boot script not found at $BOOT_SCRIPT_PATH"
    exit 1
fi

# Create temporary directory structure
TEMP_DIR=$(mktemp -d)
CONTENT_DIR="$TEMP_DIR/bundle"
mkdir -p "$CONTENT_DIR"

# Create bootloader image file
cp "$BOOTLOADER_PATH" "$CONTENT_DIR/bootloader.img"
cp "$BOOT_SCRIPT_PATH" "$CONTENT_DIR/u-boot.scr"
cp rauc-config/bootloader_hooks.sh "$CONTENT_DIR/bootloader_hooks.sh"

# Create manifest
cat > "$CONTENT_DIR/manifest.raucm" << EOF
[update]
compatible=rauc-meticulous-update
version=$VARIANT
[bundle]
format=verity
[hooks]
filename=bootloader_hooks.sh
[image.bootloader]
filename=bootloader.img
hooks=post-install
EOF

# Create bundle using provided cert and key
rauc bundle \
  --cert="$CERT" \
  --key="$KEY" \
  "$CONTENT_DIR" \
  "rauc_meticulous_boot_${VARIANT}.raucb"

# Cleanup
rm -rf "$TEMP_DIR"
