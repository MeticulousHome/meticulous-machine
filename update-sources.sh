#!/bin/bash

source config.sh

echo "COMPONENTS_DIR is set to: $COMPONENTS_DIR"

#Function to check and fix permissions
#Function to check and fix permissions
function check_and_fix_permissions() {
    echo "Checking permissions for $COMPONENTS_DIR"
    if [ ! -d "$COMPONENTS_DIR" ]; then
        echo "COMPONENTS_DIR does not exist. Attempting to create it."
        mkdir -p "$COMPONENTS_DIR"
    fi
    if [ ! -w "$COMPONENTS_DIR" ]; then
        echo "Fixing permissions for $COMPONENTS_DIR"
        sudo chown -R $(whoami):$(whoami) "$COMPONENTS_DIR"
    else
        echo "Permissions for $COMPONENTS_DIR are correct"
    fi
    ls -ld "$COMPONENTS_DIR"
}

# Taken from var-debian
# get sources from git repository
# $1 - git repository
# $2 - branch name
# $3 - output dir
# $4 - commit id

check_and_fix_permissions

function get_git_src() {
    if ! [ -d $3 ]; then
        # clone src code
        git clone ${1} -b ${2} ${3} --recurse-submodules
    fi
    cd ${3}
    git fetch origin --recurse-submodules
    git checkout origin/${2} -B ${2} -f --recurse-submodules
    git reset --hard ${4}
    cd -
}

function install_ubuntu_dependencies() {
    if [ -n "$(uname -a | grep Ubuntu)" ]; then
        echo "Running on ubuntu: Installing host dependencies"
        sudo apt update
        sudo apt -y install ${HOST_PACKAGES}

        if [ -z "$(which node)" ]; then
            curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash - &&
                sudo apt-get install -y nodejs
        fi

        if [ -z "$(which pio)" ]; then
            wget -O get-platformio.py https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py
            python3 get-platformio.py
            echo "export PATH=$PATH:$HOME/.platformio/penv/bin" >>$HOME/.bashrc
            export PATH=$PATH:$HOME/.platformio/penv/bin
            rm get-platformio.py
        fi
        if [ -z "$(which bundle)" ]; then
            sudo apt install ruby ruby-bundler
        fi
    fi
}

function update_tester_backend() {
    echo "Cloning / Updating AutomatedMainBoardTesterBackend Repository"
    echo "TESTER_BACKEND_SRC_DIR is set to: $TESTER_BACKEND_SRC_DIR"
    get_git_src ${TESTER_BACKEND_GIT} ${TESTER_BACKEND_BRANCH} \
        ${TESTER_BACKEND_SRC_DIR} ${TESTER_BACKEND_REV}
    
    echo "Installing dependencies for AutomatedMainBoardTesterBackend"
    pushd ${TESTER_BACKEND_SRC_DIR}
    if [ -f requirements.txt ]; then
        # Use the Python that's in the user's PATH
        PYTHON_PATH=$(which python)
        if [ -z "$PYTHON_PATH" ]; then
            echo "Error: Python not found in PATH. Please ensure Python is installed and in your PATH."
            exit 1
        fi
        echo "Using Python at: $PYTHON_PATH"
        
        # Ensure python3-dev is installed
        sudo apt-get update && sudo apt-get install -y python3-dev

        # Install gpiod separately
        $PYTHON_PATH -m pip install --no-binary :all: gpiod==2.1.3

        # Install other requirements
        $PYTHON_PATH -m pip install -r requirements.txt
    else
        echo "requirements.txt not found in ${TESTER_BACKEND_SRC_DIR}"
    fi
    popd
}

function update_debian() {
    echo "Cloning / Updating Debian Repository"
    if [ ! -d "${DEBIAN_SRC_DIR}" ]; then
        echo "Cloning Debian repository..."
        git clone ${DEBIAN_GIT} ${DEBIAN_SRC_DIR}
    fi
    
    pushd ${DEBIAN_SRC_DIR} > /dev/null
    
    echo "Updating remote references..."
    git fetch --all
    
    echo "Checking for and storing any local changes..."
    git stash
    
    echo "Attempting to switch to branch ${DEBIAN_BRANCH}..."
    if git checkout ${DEBIAN_BRANCH}; then
        echo "Branch ${DEBIAN_BRANCH} already exists. Updating..."
        git pull origin ${DEBIAN_BRANCH}
    else
        echo "Branch ${DEBIAN_BRANCH} doesn't exist locally. Creating it..."
        git checkout -b ${DEBIAN_BRANCH} origin/${DEBIAN_BRANCH} || {
            echo "Failed to create branch ${DEBIAN_BRANCH}. It might not exist on remote. Creating from current HEAD..."
            git checkout -b ${DEBIAN_BRANCH}
        }
    fi
    
    echo "Attempting to reset to specific commit ${DEBIAN_REV}..."
    if git reset --hard ${DEBIAN_REV}; then
        echo "Successfully reset to commit ${DEBIAN_REV}"
    else
        echo "Failed to reset to commit ${DEBIAN_REV}. This commit might not exist."
        echo "Showing the last 5 commits of the current branch:"
        git log -n 5 --oneline
        echo "Please verify the DEBIAN_REV variable in config.sh."
        popd > /dev/null
        return 1
    fi
    
    echo "Checking if there were stashed changes..."
    git stash list | grep -q "stash@{0}" && {
        echo "Attempting to apply stashed changes..."
        git stash pop || {
            echo "Failed to apply stashed changes. They might conflict with the new state."
            echo "The changes are still in the stash. Please resolve manually if needed."
        }
    }
    
    popd > /dev/null
    
    echo "Asking debian to fetch its dependencies"
    ${DEBIAN_SRC_DIR}/var_make_debian.sh -c deploy
}

# function update_backend() {
#     echo "Cloning / Updating Backend Repository"
#     get_git_src ${BACKEND_GIT} ${BACKEND_BRANCH} \
#         ${BACKEND_SRC_DIR} ${BACKEND_REV}
# }

function update_watcher() {
    echo "Cloning / Updating Watcher Repository"
    get_git_src ${WATCHER_GIT} ${WATCHER_BRANCH} \
        ${WATCHER_SRC_DIR} ${WATCHER_REV}
}

# function update_dial() {
#     echo "Cloning / Updating Dial Repository"
#     get_git_src ${DIAL_GIT} ${DIAL_BRANCH} \
#         ${DIAL_SRC_DIR} ${DIAL_REV}

#     echo "Installing Dial App dependencies"
#     pushd $DIAL_SRC_DIR
#     npm install
#     popd
# }

function update_dash() {
    echo "Cloning / Updating Dash Repository"
    get_git_src ${DASH_GIT} ${DASH_BRANCH} \
        ${DASH_SRC_DIR} ${DASH_REV}
    pushd $DASH_SRC_DIR
    npm install
    popd
}

function update_web() {
    echo "Cloning / Updating WebApp Repository"
    get_git_src ${WEB_APP_GIT} ${WEB_APP_BRANCH} \
        ${WEB_APP_SRC_DIR} ${WEB_APP_REV}
    pushd $WEB_APP_SRC_DIR
    npm install
    popd
}

function update_firmware() {
    echo "Cloning / Updating Firmware Repository"
    get_git_src ${FIRMWARE_GIT} ${FIRMWARE_BRANCH} \
        ${FIRMWARE_SRC_DIR} ${FIRMWARE_REV}
    pushd $FIRMWARE_SRC_DIR
    pio lib install
    popd
}

function update_mobile() {
    echo "Cloning / Updating Firmware Repository"
    get_git_src ${MOBILE_GIT} ${MOBILE_BRANCH} \
        ${MOBILE_SRC_DIR} ${MOBILE_REV}
    pushd $MOBILE_SRC_DIR
    yarn
    bundle install
    popd
}


function update_rauc() {
    echo "Cloning / Updating rauc and rauc-hawkbit-updater Repositories"
    get_git_src ${RAUC_GIT} ${RAUC_BRANCH} \
        ${RAUC_SRC_DIR} ${RAUC_REV}

    get_git_src ${HAWKBIT_GIT} ${HAWKBIT_BRANCH} \
        ${HAWKBIT_SRC_DIR} ${HAWKBIT_REV}
}


function show_help() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Run various functions to install dependencies and checkout or update components.

By default --all functions should be used to get a full initial checkout.
Specific components can be fetched and updated by passing their names as options.

Available options:
    --all                           Checkout / Update All repositories except for the firmware
    --install_ubuntu_dependencies   Install dependencies for Ubuntu
    --debian                        Checkout / Update Debian repository
    --watcher                       Checkout / Update Watcher repository
    --dash / --dashboard            Checkout / Update Dashboard repository
    --web / --webapp                Checkout / Update WebApp repository
    --firmware                      Checkout / Update Firmware repository (Requires explicit access)
    --mobile                        Checkout / Update Mobile app repository (Requires explicit access)
    --tester_backend                Checkout / Update AutomatedMainBoardTesterBackend repository
    --rauc                          Checkout / Update rauc and rauc-hawkbit-updatere repositories
    --help                          Display this help and exit

EOF
}

any_selected=0
all_selected=0
firmware_selected=0
mobile_selected=0
install_ubuntu_dependencies_selected=0
declare -A steps

steps=(
    [update_debian]=0
    [update_watcher]=0
    [update_dash]=0
    [update_web]=0
    [update_tester_backend]=0
    [update_rauc]=0
)

# Parse command line arguments, enable steps when selected
for arg in "$@"; do
    case $arg in
    --tester_backend) steps[update_tester_backend]=1 ;;
    --install_ubuntu_dependencies) install_ubuntu_dependencies_selected=1 ;;
    --debian) steps[update_debian]=1 ;;
    # --backend) steps[update_backend]=1 ;;
    --watcher) steps[update_watcher]=1 ;;
    # --dial) steps[update_dial]=1 ;;
    --dashboard) steps[update_dash]=1 ;;
    --dash) steps[update_dash]=1 ;;
    --web) steps[update_web]=1 ;;
    --webapp) steps[update_web]=1 ;;
    --firmware) firmware_selected=1 ;;
    --mobile) mobile_selected=1 ;;
    --rauc) steps[update_rauc]=1 ;;
    # Enable all steps via special case
    --all) all_selected=1 ;;
    *)
        echo "Invalid option: $arg"
        show_help
        exit 1
        ;;
    esac
done

if [ ${install_ubuntu_dependencies_selected} -eq 1 ]; then
    install_ubuntu_dependencies
fi

for key in "${!steps[@]}"; do
    if [ ${steps[$key]} -eq 1 ] ||
        [ $all_selected -eq 1 ]; then
        any_selected=1
        # Execute step
        $key
    fi
done

if [ ${firmware_selected} -eq 1 ]; then
    update_firmware
fi

if [ ${mobile_selected} -eq 1 ]; then
    update_mobile
fi

# Print help if no step has been executed
if [ $any_selected -eq 0 ]; then
    show_help
fi
