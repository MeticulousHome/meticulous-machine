#!/usr/bin/env bash

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
    cd -
}

function install_ubuntu_dependencies() {
    echo "Installing host dependencies"
    if [ -z "$(which sudo)" ]; then
        apt update
        apt install -y sudo
    fi
    sudo apt update
    sudo apt -y install ${HOST_PACKAGES}
    if [ $(uname -m) == "aarch64" ]; then
        if lsb_release -i | grep -i ubuntu; then
            sudo dpkg -i ./misc/libssl1.1_1.1.1f-1ubuntu2.23_arm64.deb
        fi
        sudo apt -y install ./misc/rauc_*_arm64.deb 
    else
        sudo apt -y install ./misc/rauc_*_amd64.deb
    fi

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

    echo "Asking debian to fetch its dependencies"
    $DEBIAN_SRC_DIR/var_make_debian.sh -c deploy
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

    echo "Installing Dial App dependencies"
    pushd $DIAL_SRC_DIR
    npm install
    popd
}

function update_dash() {
    echo "Cloning / Updating Dash Repository"
    get_git_src ${DASH_GIT} ${DASH_BRANCH} \
        ${DASH_SRC_DIR} ${DASH_REV}
    pushd $DASH_SRC_DIR
    popd
}

function update_web() {
    echo "Cloning / Updating WebApp Repository"
    get_git_src ${WEB_APP_GIT} ${WEB_APP_BRANCH} \
        ${WEB_APP_SRC_DIR} ${WEB_APP_REV}
    pushd $WEB_APP_SRC_DIR
    popd
}

function update_firmware() {
    echo "Cloning / Updating Firmware Repository"
    get_git_src ${FIRMWARE_GIT} ${FIRMWARE_BRANCH} \
        ${FIRMWARE_SRC_DIR} ${FIRMWARE_REV}
    pushd $FIRMWARE_SRC_DIR
    popd
}

function update_history() {
    echo "Cloning / Updating History UI Repository"
    get_git_src ${HISTORY_UI_GIT} ${HISTORY_UI_BRANCH} \
        ${HISTORY_UI_SRC_DIR} ${HISTORY_UI_REV}
    pushd $HISTORY_UI_SRC_DIR
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
    --backend                       Checkout / Update Backend repository
    --watcher                       Checkout / Update Watcher repository
    --dial                          Checkout / Update Dial repository
    --dash / --dashboard            Checkout / Update Dashboard repository
    --web / --webapp                Checkout / Update WebApp repository
    --firmware                      Checkout / Update Firmware repository (Requires explicit access)
    --mobile                        Checkout / Update Mobile app repository (Requires explicit access)
    --history                       Checkout / Update History UI repository (Requires explicit access)
    --rauc                          Checkout / Update rauc and rauc-hawkbit-updatere repositories
    --help                          Display this help and exit

EOF
}

any_selected=0
all_selected=0
firmware_selected=0
mobile_selected=0
install_ubuntu_dependencies_selected=0
history_ui_selected=0
rauc_selected=0
declare -A steps
steps=(
    [update_debian]=0
    [update_backend]=0
    [update_watcher]=0
    [update_dial]=0
    [update_dash]=0
    [update_web]=0
)

# Parse command line arguments, enable steps when selected
for arg in "$@"; do
    case $arg in
    --install_ubuntu_dependencies) install_ubuntu_dependencies_selected=1 ;;
    --debian) steps[update_debian]=1 ;;
    --backend) steps[update_backend]=1 ;;
    --watcher) steps[update_watcher]=1 ;;
    --dial) steps[update_dial]=1 ;;
    --dashboard) steps[update_dash]=1 ;;
    --dash) steps[update_dash]=1 ;;
    --web) steps[update_web]=1 ;;
    --webapp) steps[update_web]=1 ;;
    --firmware) firmware_selected=1 ;;
    --mobile) mobile_selected=1 ;;
    --rauc) rauc_selected=1 ;;
    --history) history_ui_selected=1 ;;

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

if [ ${rauc_selected} -eq 1 ]; then
    rauc_selected
    any_selected=1
fi


# Print help if no step has been executed
if [ $any_selected -eq 0 ]; then
    show_help
fi
