#!/bin/bash
source config.sh

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <image build number> <image channel>"
    exit 1
fi
build_number=$1
channel=$2
short_year=$(date "+%Y")

version="${short_year}M${build_number}-${channel}" 
echo $version