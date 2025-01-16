#!/bin/bash

# Configuration file
CONFIG_FILE="config.sh"
# Directory where the repository folders are located
COMPONENTS_DIR="components"
# Output file
OUTPUT_FILE="repository_info"

# Initialize output file
echo "Detailed repository information:" > "$OUTPUT_FILE"
echo "Starting the process of generating detailed repository information..."
echo ""

# Function to extract information from a repository
extract_repo_info() {
    local repo_name=$1
    local repo_dir=$2
    local url_var=$3
    local branch_var=$4

    # Retrieve URL and branch from the configuration file
    local url=$(grep -E "readonly ${url_var}=" "$CONFIG_FILE" | cut -d'"' -f2)
    local branch=$(grep -E "export[[:space:]]+${branch_var}=" "$CONFIG_FILE" | cut -d'"' -f2)

    echo "Processing repository: $repo_name"
    echo " URL: $url"
    echo " Branch: $branch"

    # Initial variables
    local git_describe_output="Not available"
    local git_show_output="Not available"

    # If the repository folder exists, retrieve additional information using Git
    if [ -d "$repo_dir/.git" ]; then
        echo " Accessing the repository at: $repo_dir"

        # Change to the repository directory and capture the Git output
        cd "$repo_dir" || exit
        git_describe_output=$(git describe --always 2>/dev/null)

        # If the hash is valid, execute git show to get more details
        if [ -n "$git_describe_output" ]; then
            git_show_output=$(git show "$git_describe_output" --oneline -s 2>/dev/null)
        fi

        cd - > /dev/null || exit
    else
        echo " No Git repository found in $repo_dir"
        echo " Warning: No Git repository found in $repo_dir" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi

    # Write the information to the output file
    {
        echo "Repository: $repo_name"
        echo " Directory: $repo_dir"
        echo " URL: $url"
        echo " Branch: $branch"
        echo " Hash: $git_describe_output"
        echo " Detail of hash (git show): $git_show_output"
        echo "------------------------------------------------------------"
    } >> "$OUTPUT_FILE"

    echo "Processing of $repo_name complete."
    echo ""
}

# Iterate through each folder in the components directory
for folder in "$COMPONENTS_DIR"/*; do
    if [ -d "$folder" ]; then
        repo_name=$(basename "$folder")
        # Exclude the "bootloader" folder
        if [ "$repo_name" != "bootloader" ]; then
            # Determine the corresponding variables for the repository
            case "$repo_name" in
                linux)
                    extract_repo_info "$repo_name" "$folder" "LINUX_GIT" "LINUX_BRANCH"
                    ;;
                debian-base)
                    extract_repo_info "$repo_name" "$folder" "DEBIAN_GIT" "DEBIAN_BRANCH"
                    ;;
                meticulous-backend)
                    extract_repo_info "$repo_name" "$folder" "BACKEND_GIT" "BACKEND_BRANCH"
                    ;;
                meticulous-dial)
                    extract_repo_info "$repo_name" "$folder" "DIAL_GIT" "DIAL_BRANCH"
                    ;;
                meticulous-dashboard)
                    extract_repo_info "$repo_name" "$folder" "DASH_GIT" "DASH_BRANCH"
                    ;;
                meticulous-web-app)
                    extract_repo_info "$repo_name" "$folder" "WEB_APP_GIT" "WEB_APP_BRANCH"
                    ;;
                meticulous-watcher)
                    extract_repo_info "$repo_name" "$folder" "WATCHER_GIT" "WATCHER_BRANCH"
                    ;;
                psplash)
                    extract_repo_info "$repo_name" "$folder" "PSPLASH_GIT" "PSPLASH_BRANCH"
                    ;;
                rauc)
                    # Special handling for the rauc folder with multiple repositories
                    extract_repo_info "rauc" "$folder/rauc" "RAUC_GIT" "RAUC_BRANCH"
                    extract_repo_info "rauc-hawkbit-updater" "$folder/rauc-hawkbit-updater" "HAWKBIT_GIT" "HAWKBIT_BRANCH"
                    ;;
                *)
                    echo "No information found for the repository: $repo_name" >> "$OUTPUT_FILE"
                    echo "" >> "$OUTPUT_FILE"
                    ;;
            esac
        fi
    fi
done

echo "Process complete. The information is located in the file $OUTPUT_FILE"

