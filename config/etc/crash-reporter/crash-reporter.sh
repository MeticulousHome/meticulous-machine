#!/usr/bin/bash

# get a journal entry with the service that failed
echo "$MONITOR_UNIT has failed - restarting"

# report the error to sentry
/opt/meticulous-crash-reporter

#restart the service if meant to be restarted

declare -a restart
restart=(
    "meticulous-backend.service"
    "meticulous-dial.service"
    "meticulous-watcher.service"
    "rauc-hawkbit-updater.service"
)

for SERVICE in "${restart[@]}"; do

    [ "$SERVICE" = "$MONITOR_UNIT" ] && systemctl restart "$MONITOR_UNIT" && break

done