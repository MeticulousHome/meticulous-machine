#!/usr/bin/env bash
#
# The backend and the watcher both vendor MeticulousHome/meticulous-log-redactor
# as a submodule at log_redactor/, and both read the same per-device key from
# /root/.redaction_key. That is what makes a value produce the same token in
# either service, so an SSID in a backend log line can be matched to the same
# network in the NetworkManager line beside it.
#
# Each repo's own test suite runs the module's contract test against the commit
# that repo has pinned, so a broken pin fails there. What no test in either repo
# can see is the *other* repo's pin: two different-but-valid commits pass
# everywhere and silently produce different redaction. This is the only place
# both trees exist side by side, so the comparison lives here.
#
# Direction matters, and only one direction is unsafe. The watcher filters at
# read time, immediately before the archive is written, so it is the last line of
# defence: anything the backend's emit-time filter misses is still caught. The
# reverse is not true. A watcher missing a rule the backend already has means
# that value reaches the archive.
#
#   watcher behind backend  -> hard fail, the image would ship a hole
#   pins merely different   -> warn, the build continues
#
set -euo pipefail

source config.sh

BACKEND_REDACTOR="${BACKEND_SRC_DIR}/log_redactor"
WATCHER_REDACTOR="${WATCHER_SRC_DIR}/log_redactor"

for dir in "$BACKEND_REDACTOR" "$WATCHER_REDACTOR"; do
    if [ ! -d "${dir}/.git" ] && [ ! -f "${dir}/.git" ]; then
        echo "log_redactor submodule not checked out at ${dir}, skipping pin check"
        echo "  run ./update-sources.sh first, or git submodule update --init"
        exit 0
    fi
done

BACKEND_SHA=$(git -C "$BACKEND_REDACTOR" rev-parse HEAD)
WATCHER_SHA=$(git -C "$WATCHER_REDACTOR" rev-parse HEAD)

if [ "$BACKEND_SHA" = "$WATCHER_SHA" ]; then
    echo "log_redactor: backend and watcher agree on ${BACKEND_SHA}"
    exit 0
fi

echo "WARNING: backend and watcher are pinned to different log_redactor commits"
echo "  backend: ${BACKEND_SHA}"
echo "  watcher: ${WATCHER_SHA}"

# update-sources.sh fetches with --depth 2, so neither clone necessarily has the
# other's commit or enough history to answer --is-ancestor. Deepen the watcher's
# clone and pull the backend's commit into it before asking.
if ! git -C "$WATCHER_REDACTOR" cat-file -e "${BACKEND_SHA}^{commit}" 2>/dev/null; then
    git -C "$WATCHER_REDACTOR" fetch --quiet --unshallow origin 2>/dev/null ||
        git -C "$WATCHER_REDACTOR" fetch --quiet origin || true
fi

if ! git -C "$WATCHER_REDACTOR" cat-file -e "${BACKEND_SHA}^{commit}" 2>/dev/null; then
    echo "ERROR: the backend's log_redactor commit ${BACKEND_SHA} is unknown to the"
    echo "watcher's clone even after fetching. One of them is pinned to a commit that"
    echo "is not on the module's remote -- a local commit, or a fork. Cannot verify"
    echo "that the watcher is not missing a rule, so failing rather than guessing."
    exit 1
fi

if ! git -C "$WATCHER_REDACTOR" merge-base --is-ancestor "$BACKEND_SHA" "$WATCHER_SHA"; then
    echo
    echo "ERROR: the watcher's log_redactor is behind the backend's."
    echo "The watcher redacts the archive last, so a rule the backend has and the"
    echo "watcher does not is a value that reaches the bug report. Bump the watcher's"
    echo "submodule to ${BACKEND_SHA} or newer before building an image."
    exit 1
fi

echo "OK: the watcher is ahead of the backend. Safe direction -- the watcher"
echo "filters last, so anything the backend misses is still caught."
