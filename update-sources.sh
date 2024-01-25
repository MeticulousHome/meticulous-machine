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

if [  -n "$(uname -a | grep Ubuntu)" ]; then
    echo "Running on ubuntu: Installing host dependencies"

    sudo apt -y install \
        binfmt-support pv qemu-user-static debootstrap kpartx lvm2 dosfstools gpart\
        binutils git libncurses-dev python3-m2crypto gawk wget git-core diffstat unzip\
        texinfo gcc-multilib build-essential chrpath socat libsdl1.2-dev autoconf libtool\
        libglib2.0-dev libarchive-dev python3-git xterm sed cvs subversion coreutils\
        texi2html docbook-utils help2man make gcc g++ desktop-file-utils libgl1-mesa-dev\
        libglu1-mesa-dev mercurial automake groff curl lzop asciidoc u-boot-tools mtd-utils\
        libgnutls28-dev flex bison libssl-dev systemd-container

    if [  -z "$(which node)" ]; then
        curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash - &&\
        sudo apt-get install -y nodejs
    fi
fi

echo "Cloning / Updating Debian Repository"
get_git_src ${DEBIAN_GIT} ${DEBIAN_BRANCH} \
		${DEBIAN_SRC_DIR} ${DEBIAN_REV}

echo "Asking debian to fetch its dependencies"
$DEBIAN_SRC_DIR/var_make_debian.sh -c deploy

echo "Cloning / Updating Backend Repository"
get_git_src ${BACKEND_GIT} ${BACKEND_BRANCH} \
		${BACKEND_SRC_DIR} ${BACKEND_REV}

echo "Cloning / Updating Dial Repository"
get_git_src ${DIAL_GIT} ${DIAL_BRANCH} \
		${DIAL_SRC_DIR} ${DIAL_REV}

echo "Installing Dial App dependencies"
pushd $DIAL_SRC_DIR
npm install
popd

echo "Cloning / Updating Dash Repository"
get_git_src ${DASH_GIT} ${DASH_BRANCH} \
		${DASH_SRC_DIR} ${DASH_REV}
pushd $DIAL_SRC_DIR
npm install
popd