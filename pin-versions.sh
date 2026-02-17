#!/bin/bash
set -eo pipefail

# Check if the required arguments are provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 <image_name>"
  exit 1
fi

# Get the image name from the first argument
IMAGE_NAME="$1"

# Create the images directory if it doesn't exist
mkdir -p images

# Define the output file path
OUTPUT_FILE="images/${IMAGE_NAME}.versions.sh"

source config.sh

# Function to pin the revision to a file
pin_revision() {
    local repo_var=$1
    local rev=$2
    local commit=$3

    if [[ ! -f $OUTPUT_FILE ]]; then
        echo "#!/bin/bash" > $OUTPUT_FILE
    fi
    sed -i "/${repo_var}/d" "${OUTPUT_FILE}"
    echo "Pinning $repo_var to $rev ($commit)"
    echo "export $repo_var=\"$rev\" # ${commit}" >> "${OUTPUT_FILE}"
}

# Function to update a single repository
update_repo_rev() {
    local repo_dir=$1
    local repo_var=$2
    local rev_var=$3
    local is_optional=$4

    if [[ -d $repo_dir ]]; then
        echo "Updating $repo_dir"
        pushd "$repo_dir" > /dev/null
        local current_rev=$(git rev-parse HEAD)
        local current_commit=$(git log --format=%B -n 1 HEAD | head -n1)
        popd > /dev/null

        # Pin the revision to the file
        pin_revision "$rev_var" "$current_rev" "$current_commit"
    else
        if  [ "${is_optional}" == "optional" ]; then
            echo "Warn: Directory $repo_dir not found!"
        else
            echo "Error: Directory $repo_dir not found!"
            exit 1
        fi
    fi
}

# Function to update all repositories
update_all_repos() {
    update_repo_rev "$LINUX_SRC_DIR" "LINUX_GIT" "LINUX_REV"
    update_repo_rev "$UBOOT_SRC_DIR" "UBOOT_GIT" "UBOOT_REV"
    update_repo_rev "$ATF_SRC_DIR" "ATF_GIT" "ATF_REV"
    update_repo_rev "$IMX_MKIMAGE_SRC_DIR" "IMX_MKIMAGE_GIT" "IMX_MKIMAGE_REV"
    update_repo_rev "$DEBIAN_SRC_DIR" "DEBIAN_GIT" "DEBIAN_REV"
    if [ "$IMAGE_NAME" != "factory" ]; then
        #always track beta-factory for dial app and main-factory for backend repos when updating factory image revs
        update_repo_rev "$BACKEND_SRC_DIR" "BACKEND_GIT" "BACKEND_REV"
        update_repo_rev "$DIAL_SRC_DIR" "DIAL_GIT" "DIAL_REV"
    fi
    update_repo_rev "$WEB_APP_SRC_DIR" "WEB_APP_GIT" "WEB_APP_REV"
    update_repo_rev "$WATCHER_SRC_DIR" "WATCHER_GIT" "WATCHER_REV"
    update_repo_rev "$FIRMWARE_SRC_DIR" "FIRMWARE_GIT" "FIRMWARE_REV"
    update_repo_rev "$RAUC_SRC_DIR" "RAUC_GIT" "RAUC_REV"
    update_repo_rev "$HAWKBIT_SRC_DIR" "HAWKBIT_GIT" "HAWKBIT_REV"
    update_repo_rev "$PSPLASH_SRC_DIR" "PSPLASH_GIT" "PSPLASH_REV"
    update_repo_rev "$HISTORY_UI_SRC_DIR" "HISTORY_UI_GIT" "HISTORY_UI_REV" "optional"
    update_repo_rev "$PLOTTER_UI_SRC_DIR" "PLOTTER_UI_GIT" "PLOTTER_UI_REV" "optional"
    update_repo_rev "$CRASH_REPORTER_SRC_DIR" "CRASH_REPORTER_GIT" "CRASH_REPORTER_REV"
}


# If a specific path is provided, update only that repo
if [[ -n $2 ]]; then
    case $2 in
        "$LINUX_SRC_DIR") update_repo_rev "$LINUX_SRC_DIR" "LINUX_GIT" "LINUX_REV" ;;
        "$UBOOT_SRC_DIR") update_repo_rev "$UBOOT_SRC_DIR" "UBOOT_GIT" "UBOOT_REV" ;;
        "$ATF_SRC_DIR") update_repo_rev "$ATF_SRC_DIR" "ATF_GIT" "ATF_REV" ;;
        "$IMX_MKIMAGE_SRC_DIR") update_repo_rev "$IMX_MKIMAGE_SRC_DIR" "IMX_MKIMAGE_GIT" "IMX_MKIMAGE_REV" ;;
        "$DEBIAN_SRC_DIR") update_repo_rev "$DEBIAN_SRC_DIR" "DEBIAN_GIT" "DEBIAN_REV" ;;
        "$BACKEND_SRC_DIR") update_repo_rev "$BACKEND_SRC_DIR" "BACKEND_GIT" "BACKEND_REV" ;;
        "$DIAL_SRC_DIR") update_repo_rev "$DIAL_SRC_DIR" "DIAL_GIT" "DIAL_REV" ;;
        "$WEB_APP_SRC_DIR") update_repo_rev "$WEB_APP_SRC_DIR" "WEB_APP_GIT" "WEB_APP_REV" ;;
        "$WATCHER_SRC_DIR") update_repo_rev "$WATCHER_SRC_DIR" "WATCHER_GIT" "WATCHER_REV" ;;
        "$FIRMWARE_SRC_DIR") update_repo_rev "$FIRMWARE_SRC_DIR" "FIRMWARE_GIT" "FIRMWARE_REV" ;;
        "$RAUC_SRC_DIR") update_repo_rev "$RAUC_SRC_DIR" "RAUC_GIT" "RAUC_REV" ;;
        "$HAWKBIT_SRC_DIR") update_repo_rev "$HAWKBIT_SRC_DIR" "HAWKBIT_GIT" "HAWKBIT_REV" ;;
        "$PSPLASH_SRC_DIR") update_repo_rev "$PSPLASH_SRC_DIR" "PSPLASH_GIT" "PSPLASH_REV" ;;
        "$HISTORY_UI_SRC_DIR") update_repo_rev "$HISTORY_UI_SRC_DIR" "HISTORY_UI_GIT" "HISTORY_UI_REV" "optional";;
        "$PLOTTER_UI_SRC_DIR") update_repo_rev "$PLOTTER_UI_SRC_DIR" "PLOTTER_UI_GIT" "PLOTTER_UI_REV" "optional";;
        "$CRASH_REPORTER_SRC_DIR") update_repo_rev "$CRASH_REPORTER_SRC_DIR" "CRASH_REPORTER_GIT" "CRASH_REPORTER_REV" ;;
        *)
            echo "Error: Invalid repository path specified."
            exit 1
            ;;
    esac
else
    # If no path is provided, update all repositories
    update_all_repos
fi
