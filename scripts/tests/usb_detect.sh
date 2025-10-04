#!/bin/bash

IDVENDOR="$1"
PRODUCT="$2"

if [ -z "$IDVENDOR" ] || [ -z "$PRODUCT" ]; then
    echo "missing idVendor or product string"
    exit 1
fi

if [ "$IDVENDOR" != "1d6b" ]; then
    busctl --system emit /handlers/massStorage com.Meticulous.Handler.MassStorage Detection s "$PRODUCT"
fi