#!/bin/bash

# Lab-only image definition for SN002006 display-wrap diagnostics.
# Keep the machine on its original stable component set and replace only Linux.
source images/stable.versions.sh

export LINUX_BRANCH="codex/diagnostic-st7701-wrap"
export LINUX_REV="e073738253d7c5ca88a5809752b253515a3742d0"
