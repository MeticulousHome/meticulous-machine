#!/bin/bash
set -eo pipefail

source config.sh

if [ ! -f ${DEBIAN_SRC_DIR}/output/rootfs.tar.gz ]; then
    echo "Building debian"

    pushd $DEBIAN_SRC_DIR
    sudo ./var_make_debian -c all
    popd
fi

echo "Building Dial app"
pushd $DIAL_SRC_DIR
rm -f out/make/deb/arm64/*.deb
npm run make -- --arch=arm64 --platform=linux


pushd out/make/deb/arm64
ar x meticulous-ui*.deb
# Uncompress zstd files an re-compress them using xz
zstd -d < control.tar.zst | xz > control.tar.xz
zstd -d < data.tar.zst | xz > data.tar.xz
# Re-create the Debian package in /tmp/
ar -m -c -a sdsd meticulous-ui.deb debian-binary control.tar.xz data.tar.xz
# Clean up
rm debian-binary control.tar.xz data.tar.xz control.tar.zst data.tar.zst
popd
popd

echo "Building Dashboard app"
pushd $DASH_SRC_DIR
npm run build
popd