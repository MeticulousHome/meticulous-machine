#!/usr/bin/env bash
set -eo pipefail

source config.sh

# Taken from var-debian
# get sources from git repository
# $1 - git repository
# $2 - branch name
# $3 - output dir
# $4 - commit id
function get_git_src() {
    if ! [ -d $3 ]; then
        # clone src code
        git clone ${1} -b ${2} ${3} --recurse-submodules
    fi
    cd ${3}
    git fetch origin --recurse-submodules
    git checkout origin/${2} -B ${2} -f --recurse-submodules
    git reset --hard ${4}

    {
        echo "Repository: $(basename ${3})"
        echo "URL: ${1}"
        echo "Branch: ${2}"
        echo "Commit: ${4}"
        echo "Last commit details:"
        git log -1 --pretty=format:"%h - %s (%cr) <%an>"
        echo
        echo "Modified files:"
        git diff --name-only HEAD~1
    } > repository-info.txt

    echo "Generated repository information at: $(pwd)/repository-info.txt"
    echo "Content of repository-info.txt:"
    cat repository-info.txt

    cd -
}

function install_ubuntu_dependencies() {
    echo "Installing host dependencies"
    if [ -z "$(which sudo)" ]; then
        apt update
        apt install -y sudo
    fi

    sudo dpkg --add-architecture 'arm64'
    if [ -e /etc/apt/sources.list.d/ubuntu.sources ]; then
        sudo sed -i "s/URIs:/Architectures: amd64\nURIs:/g" /etc/apt/sources.list.d/ubuntu.sources
        sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu_arm64.sources
        sudo sed -i "s/amd64/arm64/g" /etc/apt/sources.list.d/ubuntu_arm64.sources
        sudo sed -i "s\http://archive.ubuntu.com/ubuntu\http://ports.ubuntu.com/ubuntu-ports\g" /etc/apt/sources.list.d/ubuntu_arm64.sources
        sudo sed -i "s\http://security.ubuntu.com/ubuntu\http://ports.ubuntu.com/ubuntu-ports\g" /etc/apt/sources.list.d/ubuntu_arm64.sources
    else
        sudo apt update
        sudo apt install -y lsb-release

        ubuntu_release=$(lsb_release -cs)
        sudo sed -i "s/^deb /deb [arch=amd64] /g"  /etc/apt/sources.list
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release} main restricted universe multiverse" | sudo tee /etc/apt/sources.list.d/ubuntu_arm64.list
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-updates main restricted universe multiverse" | sudo tee -a /etc/apt/sources.list.d/ubuntu_arm64.list
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ ${ubuntu_release}-security main restricted universe multiverse" | sudo tee -a /etc/apt/sources.list.d/ubuntu_arm64.list
    fi
    sudo apt update
    sudo apt -y install libssl-dev:arm64
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
        rm -rf .piocore-installer-*
    fi
    if [ -z "$(which bundle)" ]; then
        sudo apt install -y ruby ruby-bundler
    fi
}

function update_debian() {
    echo "Cloning / Updating Debian Repository"
    get_git_src ${DEBIAN_GIT} ${DEBIAN_BRANCH} \
        ${DEBIAN_SRC_DIR} ${DEBIAN_REV}
}

function update_backend() {
    echo "Cloning / Updating Backend Repository"
    get_git_src ${BACKEND_GIT} ${BACKEND_BRANCH} \
        ${BACKEND_SRC_DIR} ${BACKEND_REV}
}

function update_watcher() {
    echo "Cloning / Updating Watcher Repository"
    get_git_src ${WATCHER_GIT} ${WATCHER_BRANCH} \
        ${WATCHER_SRC_DIR} ${WATCHER_REV}
}

function update_dial() {
    echo "Cloning / Updating Dial Repository"
    get_git_src ${DIAL_GIT} ${DIAL_BRANCH} \
        ${DIAL_SRC_DIR} ${DIAL_REV}

    if [ -z "$(which pio)" ]; then
        echo "node / npm not found. Not checking out Dial App dependencies."
    else
        echo "Installing Dial App dependencies"
        pushd $DIAL_SRC_DIR
        npm install
        popd
    fi
}


function update_web() {
    echo "Cloning / Updating WebApp Repository"
    get_git_src ${WEB_APP_GIT} ${WEB_APP_BRANCH} \
        ${WEB_APP_SRC_DIR} ${WEB_APP_REV}
}

function update_firmware() {
    echo "Cloning / Updating Firmware Repository"
    get_git_src ${FIRMWARE_GIT} ${FIRMWARE_BRANCH} \
        ${FIRMWARE_SRC_DIR} ${FIRMWARE_REV}
    pushd $FIRMWARE_SRC_DIR
    if [ $(uname -s) == "Darwin" ]; then
        echo "Skipping firmware dependencies for MacOS"
    elif [ -z "$(which pio)" ]; then
        echo "PlatformIO not found. Not checking out Firmware dependencies."
    else
        pio lib install
    fi
    popd
}

function update_history() {
    echo "Cloning / Updating History UI Repository"
    get_git_src ${HISTORY_UI_GIT} ${HISTORY_UI_BRANCH} \
        ${HISTORY_UI_SRC_DIR} ${HISTORY_UI_REV}
    pushd $HISTORY_UI_SRC_DIR
    popd
}

function update_plotter() {
    echo "Cloning / Updating Plotter UI Repository"
    get_git_src ${PLOTTER_UI_GIT} ${PLOTTER_UI_BRANCH} \
        ${PLOTTER_UI_SRC_DIR} ${PLOTTER_UI_REV}
    pushd $PLOTTER_UI_SRC_DIR
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

function update_linux() {
    echo "Cloning / Updating linux Repositories"
    get_git_src ${LINUX_GIT} ${LINUX_BRANCH} \
        ${LINUX_SRC_DIR} ${LINUX_REV}
}

function update_uboot() {
    echo "Cloning / Updating uboot Repositories"
    get_git_src ${UBOOT_GIT} ${UBOOT_BRANCH} \
        ${UBOOT_SRC_DIR} ${UBOOT_REV}

    get_git_src ${ATF_GIT} ${ATF_BRANCH} \
        ${ATF_SRC_DIR} ${ATF_REV}

    get_git_src ${IMX_MKIMAGE_GIT} ${IMX_MKIMAGE_BRANCH} \
        ${IMX_MKIMAGE_SRC_DIR} ${IMX_MKIMAGE_REV}
}

function update_psplash() {
    echo "Cloning / Updating psplash Repositories"
    get_git_src ${PSPLASH_GIT} ${PSPLASH_BRANCH} \
        ${PSPLASH_SRC_DIR} ${PSPLASH_REV}
}

function show_help() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Run various functions to install dependencies and checkout or update components.

By default --all functions should be used to get a full initial checkout.
Specific components can be fetched and updated by passing their names as options.

Available options:
    --all                           Checkout / Update All repositories except for the firmware
    --image [IMAGE]                 Checkout a specific image version / pinning

    --install_ubuntu_dependencies   Install dependencies for Ubuntu

    --debian                        Checkout / Update Debian repository
    --backend                       Checkout / Update Backend repository
    --watcher                       Checkout / Update Watcher repository
    --dial                          Checkout / Update Dial repository
    --dash / --dashboard            Checkout / Update Dashboard repository
    --web / --webapp                Checkout / Update WebApp repository
    --linux / --kernel              Checkout / Update Linux Kernel repository
    --uboot / --bootloader          Checkout / Update U-Boot repository
    --rauc                          Checkout / Update rauc and rauc-hawkbit-updater repositories
    --firmware                      Checkout / Update Firmware repository (Requires explicit access)
    --mobile                        Checkout / Update Mobile app repository (Requires explicit access)
    --history                       Checkout / Update History UI repository (Requires explicit access)
    --plotter                       Checkout / Update Plotter UI repository (Requires explicit access)
    --rauc                          Checkout / Update rauc and rauc-hawkbit-updatere repositories
    --psplash / --splash            Checkout / Update psplash repository
    --help                          Display this help and exit
EOF
}

any_selected=0
all_selected=0
firmware_selected=0
mobile_selected=0
install_ubuntu_dependencies_selected=0
history_ui_selected=0
plotter_ui_selected=0
declare -A steps
steps=(
    [update_debian]=0
    [update_backend]=0
    [update_watcher]=0
    [update_dial]=0
    [update_web]=0
    [update_linux]=0
    [update_uboot]=0
    [update_rauc]=0
    [update_psplash]=0
)

# Parse command line arguments, enable steps when selected
while [[ $# -gt 0 ]]; do
    arg="$1"

    case $arg in
        --image)
            if [[ -n $2 && $2 != --* ]]; then
                IMAGE_NAME="$2"
                shift
            else
                echo "Error: --image requires a NAME argument."
                exit 1
            fi
            ;;
        --install_ubuntu_dependencies) install_ubuntu_dependencies_selected=1 ;;
        --debian) steps[update_debian]=1 ;;
        --backend) steps[update_backend]=1 ;;
        --watcher) steps[update_watcher]=1 ;;
        --dial) steps[update_dial]=1 ;;
        --web) steps[update_web]=1 ;;
        --webapp) steps[update_web]=1 ;;
        --firmware) firmware_selected=1 ;;
        --mobile) mobile_selected=1 ;;
        --rauc) steps[update_rauc]=1 ;;
        --history) history_ui_selected=1 ;;
        --plotter) plotter_ui_selected=1 ;;
        --linux) steps[update_linux]=1 ;;
        --kernel) steps[update_linux]=1 ;;
        --uboot) steps[update_uboot]=1 ;;
        --bootloader) steps[update_uboot]=1 ;;
        --psplash) steps[update_psplash]=1 ;;
        --splash) steps[update_psplash]=1 ;;
        --help) show_help; exit 0 ;;

        # Enable all steps via special case
        --all) all_selected=1 ;;
        *)
            echo "Invalid option: $arg"
            show_help
            exit 1
            ;;
        esac
    shift # Shift past the argument
done

if [[ $IMAGE_NAME ]]; then
    VERSIONS_FILE="images/${IMAGE_NAME}.versions.sh"
    if [[ -f "$VERSIONS_FILE" ]]; then
        echo "Sourcing $VERSIONS_FILE"
        source "$VERSIONS_FILE"
    else
        echo "Versions file $VERSIONS_FILE does not exist."
        exit 1
    fi
else
    echo "No image name provided, using default versions."
fi

if [ ${install_ubuntu_dependencies_selected} -eq 1 ]; then
    install_ubuntu_dependencies
    any_selected=1
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
    any_selected=1
fi

if [ ${mobile_selected} -eq 1 ]; then
    update_mobile
    any_selected=1
fi

if [ ${history_ui_selected} -eq 1 ]; then
    update_history
    any_selected=1
fi

if [ ${plotter_ui_selected} -eq 1 ]; then
    update_plotter
    any_selected=1
fi

# Print help if no step has been executed
if [ $any_selected -eq 0 ]; then
    show_help
fi
