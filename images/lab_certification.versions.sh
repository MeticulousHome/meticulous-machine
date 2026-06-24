#!/bin/bash

# Lab certification images intentionally inherit nightly defaults.
# Pin only the lab-specific app branches; firmware and other components inherit
# the nightly baseline until they need certification-specific changes.

export BACKEND_BRANCH="lab-certification-controls"
export BACKEND_REV="HEAD"

export DIAL_BRANCH="lab-certification-controls"
export DIAL_REV="HEAD"
