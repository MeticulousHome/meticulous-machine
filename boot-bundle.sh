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

# Get project root directory
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

# Create bootloader image file
cp "$BOOTLOADER_PATH" "$CONTENT_DIR/bootloader.img"

# Create manifest
cat > "$CONTENT_DIR/manifest.raucm" << EOF
[update]
compatible=rauc-meticulous-update
version=$VERSION
[bundle]
format=verity
[image.bootloader]
filename=bootloader.img
EOF

# Create bundle using provided cert and key
rauc bundle \
  --cert="$CERT" \
  --key="$KEY" \
  "$CONTENT_DIR" \
  "rauc_meticulous_boot_${VERSION}.raucb"

# Cleanup
rm -rf "$TEMP_DIR"