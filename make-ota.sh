#!/bin/bash
# Parse the command line arguments
source config.sh

nightly=false
release=false

variant=""

# Check if $ROOTFS_PATH exists as a file
if [[ ! -f $METIUCULOUS_ROOTFS ]]; then
    echo "Rootfs tarball does not exist: $METIUCULOUS_ROOTFS"
    exit 1
fi

# Parse the command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    --nightly)
        # Check if --release was already passed
        if [[ $release == true ]]; then
            echo "Only one of --nightly or --release can be passed"
            exit 1
        fi
        nightly=true
        variant="nightly"
        ;;
    --release)
        # Check if --nightly was already passed
        if [[ $nightly == true ]]; then
            echo "Only one of --nightly or --release can be passed"
            exit 1
        fi
        release=true
        variant="release"
        ;;
    --cert)
        shift
        cert="$1"
        ;;
    --key)
        shift
        key="$1"
        ;;
    *)
        echo "Invalid argument: $key"
        exit 1
        ;;
    esac
    shift
done

# Check if --cert and --key were passed
if [[ -z $cert || -z $key ]]; then
    echo "Both --cert and --key must be passed"
    exit 1
fi

# Check if $cert and $key exist as files
if [[ ! -f $cert ]]; then
    echo "Certificate file does not exist: $cert"
    exit 1
fi

if [[ ! -f $key ]]; then
    echo "Key file does not exist: $key"
    exit 1
fi


# Check if either --nightly or --release was passed
if [[ $nightly == false && $release == false ]]; then
    echo "Either --nightly or --release must be passed"
    exit 1
fi

# Check if --version was passed
if [[ $version ]]; then
    bundle_version=$version
else
    bundle_version=$(date -u +'%Y-%m-%dT%H:%M:%S%z')
fi

echo -e "\e[1;35m"
echo "Bundle Version:  $bundle_version"
echo "Bundle Variant:  $variant"
echo "Bundle Rootfs:   ${METIUCULOUS_ROOTFS}"
echo "Bundle Key:      ${key}"
echo "Bundle Cert:     ${cert}"
echo -e "\e[0m"

echo -e "\e[1;31mIT IS YOUR RESPONSIBILITY TO ENSURE ${cert} EXISTS IN THE ROOTFS\e[0m\n"

rm -rf rauc_build
mkdir -p rauc_build
cp ${METIUCULOUS_ROOTFS} rauc_build/${METIUCULOUS_ROOTFS}

# Write the modified template to a new file
echo -e "\e[1;34mRAUC config:\e[1;32m\n"

echo "\
[update]
compatible=rauc-meticulous-update
version=${bundle_version}
description=${variant}

[bundle]
format=verity

[image.rootfs]
filename=${METIUCULOUS_ROOTFS}
" | tee rauc_build/manifest.raucm

echo -e "\e[0m"

echo -e "\e[1;34mBuilding EMMC bundle:\e[0m"
rauc --cert $cert --key $key bundle rauc_build rauc_meticulous_emmc_${variant}_${bundle_version}.raucb
echo -e "Done"

echo -e "\e[1;34mPreparing SDCard bundle:\e[0m"

    echo -e "Extracting rauc system.conf and /etc/fstab from rootfs"

    cd rauc_build/
    pigz -d meticulous-rootfs.tar.gz

    rm -rf rootfs_patch
    mkdir rootfs_patch
    cd rootfs_patch

    tar xfv ../meticulous-rootfs.tar ./etc/rauc/system.conf ./etc/fstab

    echo -e "Patching system.conf and fstab for sdcard usage"
    sed -i 's\/dev/mmcblk2p\/dev/mmcblk1p\g' ./etc/rauc/system.conf
    sed -i 's\/dev/mmcblk2p\/dev/mmcblk1p\g' ./etc/fstab

    echo -e "Inserting patched files back into rootfs and recompressing"
    tar fuv ../meticulous-rootfs.tar ./etc/rauc/system.conf ./etc/fstab
    cd ..

    rm -rf rootfs_patch
    pigz meticulous-rootfs.tar
    cd ..

    echo -e "\e[1;34mBuilding SDCard bundle:\e[0m"
    rauc --cert $cert --key $key bundle rauc_build rauc_meticulous_sdcard_${variant}_${bundle_version}.raucb

rm -r rauc_build