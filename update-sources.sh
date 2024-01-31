#!/bin/bash

source config.sh

# Taken from var-debian
# get sources from git repository
# $1 - git repository
# $2 - branch name
# $3 - output dir
# $4 - commit id
function get_git_src()
{
	if ! [ -d $3 ]; then
		# clone src code
		git clone ${1} -b ${2} ${3}
	fi
	cd ${3}
	git fetch origin
	git checkout origin/${2} -B ${2} -f
	git reset --hard ${4}
	cd -
}

function install_ubuntu_dependencies()
{
if [  -n "$(uname -a | grep Ubuntu)" ]; then
    echo "Running on ubuntu: Installing host dependencies"

    sudo apt -y install ${HOST_PACKAGES}

    if [  -z "$(which node)" ]; then
        curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash - &&\
        sudo apt-get install -y nodejs
    fi
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
	npm install
	popd
}


function show_help() {
cat << EOF
Usage: ${0##*/} [OPTIONS]
Run various functions to install dependencies and checkout or update components.

By default --all functions should be used to get a full initial checkout.
Specific components can be fetched and updated by passing their names as options.

Available options:
    --all                           Checkout / Update All repositories
    --install_ubuntu_dependencies   Install dependencies for Ubuntu
    --update_debian                 Checkout / Update Debian repository
    --update_backend                Checkout / Update Backend repository
    --update_watcher                Checkout / Update Watcher repository
    --update_dial                   Checkout / Update Dial repository
    --update_dash                   Checkout / Update Dash repository
    --help                          Display this help and exit

EOF
}

any_selected=0;
all_selected=0;
declare -A steps

steps=(
    [install_ubuntu_dependencies]=0
    [update_debian]=0
    [update_backend]=0
    [update_watcher]=0
    [update_dial]=0
    [update_dash]=0
)

# Parse command line arguments, enable steps when selected
for arg in "$@"; do
    case $arg in
        --install_ubuntu_dependencies) steps[install_ubuntu_dependencies]=1 ;;
        --debian) steps[update_debian]=1 ;;
        --backend) steps[update_backend]=1 ;;
        --watcher) steps[update_watcher]=1 ;;
        --dial) steps[update_dial]=1 ;;
        --dashboard) steps[update_dash]=1 ;;
        # Enable all steps via special case
        --all) all_selected=1;;
        *) echo "Invalid option: $arg"; show_help; exit 1 ;;
    esac
done

for key in "${!steps[@]}"; do
    if [ ${steps[$key]} -eq 1 ] \
    || [ $all_selected -eq 1 ]; then
        any_selected=1
        # Execute step
        $key
    fi
done

# Print help if no step has been executed
if [ $any_selected -eq 0 ]; then
    show_help
fi
