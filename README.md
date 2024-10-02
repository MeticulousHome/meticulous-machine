# Meticulous Machine Image Builder

This collection of scripts automates the process of building machine images for
the Meticulous project. It includes capabilities for updating sources, building
components, creating a root filesystem (rootfs), and preparing an SD card image
which can be transfered to the machines emmc

## TLDR

```bash
update-sources.sh --all
build-components.sh --all
sudo make-rootfs.sh --all
sudo make-sdcard.sh --image
```

## Running on non-ubuntu > 24.04 systems (macOS / docker)
For building on macOS or non-ubuntu systems we offer the `./run-in-container.sh` script. It will start an ubuntu container with all dependencies
installed

## Getting Started by checking out the sources

Before running any scripts, ensure you have installed all necessary dependencies and configured the config.sh file for your environment.

```bash
update-sources.sh --all
```

The update-sources.sh script manages the updating and checking out of various software components from their respective repositories.
Usage

```bash
update-sources.sh [OPTIONS]
```

By default, running the script should be done with the `--all` flag which will update all components.
You can also update specific components using the following options:

- `--install_ubuntu_dependencies`: Installs required dependencies on Ubuntu.
- `--debian`: Checks out or updates the Debian repository.
- `--backend`: Checks out or updates the Backend repository.
- `--watcher`: Checks out or updates the Watcher repository.
- `--dial`: Checks out or updates the Dial repository.
- `--dash`: Checks out or updates the Dash repository.
- `--all`: All of the above
- `--help`: Displays usage information.

**Install Ubuntu Dependencies**: If run on Ubuntu this will install all necessary Ubuntu host packages, including Node.js if it's not already installed

**Update Repositories**: Utilizes `git` for each component (debian, backend, etc.) to ensure the latest version is checked-out of it. **Cleans all local changes.**

## Building the meticulous components

For the creation of the rootfs all meticulous components have to be pre-compiled:

```bash
build-components.sh --all
```

The build-components.sh script is responsible for building various components of the project such as Debian, Dial, and Dashboard.
Usage

```bash
build-components.sh [OPTIONS]
```

Run the script with the following options to build specific components:

- `--debian`: Builds the Debian base rootfs from the source directory..
- `--dial`: Builds the Dial application.
- `--dash` or `--dashboard`: Builds the Dashboard application.
- `--help`: Displays usage information.

The Debian building process for the i.MX8M Nano (i.MX8MN) involves creating a basic
Debian system using debootstrap, and then adding specific dependencies and drivers
for the i.MX8MN SOM, particularly from Variscite as SOM vendor and NXP as SOC vendor.
The debian requires NXP specific GPU drivers and therefore a custom wayland stack.
It furthermore contains the downstrad custom NXP kernel for now.

The Dial and the Dashboard App are nodeJS base applications which are build using npm.

The Backend and the Watcher are shipped as raw python for now and don't need to be pre-build.

### Building the Root Filesystem

The make_rootfs.sh script creates a root filesystem for the Meticulous machine.
This process involves unpacking the pre-built Debian image, installing additional user-defined
and potentially development packages, setting up Meticulous specific systemd services
and installing the various Meticulous components with their dependencies.

```bash
sudo ./make_rootfs.sh
```

Run the script with the following options to build specific components:

- `--clean`: Unpacks the debian rootfs for further modification and installs all systemd services
- `--components`: Installs / Updates all components and installs their python dependencies where applicable
- `--tar`: Compresses the rootfs to a tarbal. e.g. after manual changes
- `--all`: All of the above
- `--help`: Displays a help text


#### Rootfs creation steps

1) Unpacking Debian Image:
Unpacks the prebuild Debian image into the rootfs directory

1) System and Development Packages

    - Installs additional packages defined in config.sh into the rootfs

1) Meticulous Services Installation

    - Installs systemd service files for Meticulous components
    - Enables these services to start on system boot

1) Meticulous Components Installation

    - Dial App: Installs the Dial application from the prebuild Debian package to the rootfs
    - Backend: Copied to /opt/meticulous-backend
    - Dashboard: Copied to /opt/meticulous-dashboard
    - Watcher: Copied to /opt/meticulous-watcher

1) Python Installation and Configuration

    - Installs Python 3.12 in the rootfs
    - Reinstalls pip for Python 3.12 to ensure it points to the correct location
    - Installs Python dependencies for Backend and Watcher using pip

1) Packing the rootfs into meticulous-rootfs.tar.gz

### Building an SDCard Image

To create an image for an SD card:

```bash
make-sdcard.sh --image
```

The `make-sdcard.sh` script can be used to immediatly create a bootable physical sdcard or to generate an image for later copy to an SDCard or the internal EMMC

```bash
make-sdcard.sh [OPTIONS]
```

Run the script with the following options to build specific components:

- `--image`: Builds a 16GiB image into sdcard.img and compresses it to sdcard.img.gz
- `--device [DEVICE]`: Builds a physical device into a bootable sdcard. The whole disk will be used with the user partition filling the remaining space
- `--help`: Displays a help text

The `make-sdcard.sh` script creates a bootable SDcard / EMMC image for the Meticulous machine.
It partitions the SDcard image, formats partitions and installs the necessary bootloader and operating system.

#### SDCard partitions scheme

| Partition | Name      | Mountpoint       | Start (KiB) | End (KiB) | Size     | Type  |
|-----------|-----------|------------------|-------------|-----------|----------|-------|
| 1         | uboot     |                  | 0x000020    | 0x00201f  | 8 MiB    | raw   |
| 2         | uboot_env | /boot/env        | 0x002020    | 0x00401f  | 8 MiB    | fat32 |
| 3         | root_a    | /                | 0x004400    | 0x5043ff  | 5 GiB    | ext4  |
| 4         | root_b    | /                | 0x504400    | 0xa043ff  | 5 GiB    | ext4  |
| 5         | user      | /meticulous_user | 0xa04400    |           | min 6 GiB| ext4  |

#### SDCard creation steps

1) Creating partitions:
    - Creates each partition needed for A/B booting the meticulous machine
    - The partition table is printed for verification.
    - Sets the boot flag on the U-Boot environment partition.
1) Formatting partitions:
    - Formats the U-Boot environment partition as FAT32.
    - Formats both root partitions and the user data partition as EXT4.
1) Mounting and populating the first root partition by unpacking the root filesystem from meticulous-rootfs.tar.gz
1) Installs the bootloader to the bootloader partition which automatically ensures the 32KiB offset required
1) Compresses the image if required
