#!/bin/sh

# Creates a zipped & partitioned image file for burning onto SD cards
# 256MB bootable FAT32L partition with official Alpine linux and lncm-box
# Make sure "parted", "dosfstools" and "zip" are installed

# For Outputing an image
OUTPUT_VERSION=v0.5.2

# For fetching Alpine
ARCH=aarch64
ARCH32=armhf
ALP=alpine-rpi-3.10.2-${ARCH}.tar.gz
ALP32=alpine-rpi-3.10.2-${ARCH32}.tar.gz

# Which alpine release directory
REL=v3.10

IMG=lncm-box-${OUTPUT_VERSION}.img
IMG32=lncm-box-${OUTPUT_VERSION}-armhf.img
MNT=/mnt/lncm

if [ "$(id -u)" -ne "0" ]; then
    echo "This script must be run as root"
    exit 1
fi

cmd_exists() {
  $(command -v ${1} 2>&1 1>/dev/null;)
  ret=$?
  echo $ret
  return $ret
}

if  [ "$(cmd_exists apk)" -eq "0" ]; then
  echo "Found Alpine-based system, installing dependencies"
  apk add parted zip unzip
fi

if [ "$(cmd_exists apt-get)" -eq "0" ]; then
  echo "Found Debian-based system, installing dependencies"
  apt-get install -y parted zip unzip
fi

check_deps() {
  cmd_exists parted >/dev/null || exit 1
  cmd_exists zip >/dev/null || exit 1
  cmd_exists unzip >/dev/null || exit 1
  echo "Found required dependencies"
}

echo "Building ${IMG} and ${IMG32}"
echo "Using ${ALP} and ${ALP32} as base distribution"

echo 'Check for existing wpa_supplicant.automatic.conf'
if [ -f ./wpa_supplicant.automatic.conf ]; then
    echo "WPA supplicant automatic file exists, bootstrapping the network configuration"
    cp ./etc/wpa_supplicant/wpa_supplicant.conf ./etc/wpa_supplicant/wpa_supplicant.conf.bak
    cp ./wpa_supplicant.automatic.conf etc/wpa_supplicant/wpa_supplicant.conf
fi

echo 'Check for authorized_keys.automatic'
if [ -f ./authorized_keys.automatic ]; then
    echo "Authorized keys file exists, bootstrapping the ssh authorized keys file"
    if [ ! -d ./home/lncm/.ssh ]; then
        mkdir -p ./home/lncm/.ssh
    fi
    cp ./authorized_keys.automatic ./home/lncm/.ssh/authorized_keys
    echo "Reconfiguring SSHD to not allow for passwords"
    cp ./etc/ssh/sshd_config ./etc/ssh/sshd_config.bak
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' ./etc/ssh/sshd_config
fi

echo 'Check for seed'
if [ -f ./seed.automatic.txt ]; then
    echo "Seed file exists, boostrapping the seed into the installation"
    cp ./seed.automatic.txt ./home/lncm/seed.txt
fi

echo 'Generate fresh box.apkovl.tar.gz from source'
sh make_apkovl.sh
# Cleanup files we created
if [ -f ./etc/wpa_supplicant/wpa_supplicant.conf.bak ]; then
    echo 'Restore old WPA Supplicant after making apkovl (and deleting the backup file)'
    cp ./etc/wpa_supplicant/wpa_supplicant.conf.bak ./etc/wpa_supplicant/wpa_supplicant.conf
    rm ./etc/wpa_supplicant/wpa_supplicant.conf.bak
fi

# Cleanup authorized_keys
if [ -d ./home/lncm/.ssh ]; then
    echo "Remove .ssh directory"
    rm -fr ./home/lncm/.ssh
fi

# Cleanup seed from home/lncm
if [ -f ./home/lncm/seed.txt ]; then
    echo "Remove seed.txt from installation so everything is equal to last commit"
    rm ./home/lncm/seed.txt
fi

if [ -f ./etc/ssh/sshd_config.bak ]; then
    echo "Restoring sshd_config to be equal with last commit"
    cp ./etc/ssh/sshd_config.bak ./etc/ssh/sshd_config
    rm ./etc/ssh/sshd_config.bak
fi

mkdir -p lncm-workdir
cd lncm-workdir || exit

if ! [ -f ${ALP} ]; then
  echo "${ALP} not found, fetching..."
  wget --no-verbose http://dl-cdn.alpinelinux.org/alpine/${REL}/releases/${ARCH}/${ALP} || echo "Error fetching alpine"
fi

if ! [ -f ${ALP32} ]; then
  echo "${ALP32} not found, fetching..."
  wget --no-verbose http://dl-cdn.alpinelinux.org/alpine/${REL}/releases/${ARCH32}/${ALP32} || echo "Error fetching alpine"
fi

echo "Create and mount 256MB image"
dd if=/dev/zero of=${IMG} bs=1M count=256 && \
    DEV=$(losetup -f) && \
    losetup -f ${IMG} && \
    echo "Create 256MB FAT32 partition and filesystem" && \
    parted -s "${DEV}" mklabel msdos mkpart p fat32 2048s 100% set 1 boot on && \
    mkfs.vfat "${DEV}"p1 -IF 32

if ! [ -d ${MNT} ]; then
  mkdir ${MNT}
fi

echo "Mount FAT partition"
mount "${DEV}"p1 "${MNT}"

echo "Extract alpine distribution"
tar -xzf ${ALP} -C ${MNT}/ --no-same-owner || echo "Can't extract alpine"

echo "Copy latest box.apkovl tarball"
cp ../box.apkovl.tar.gz ${MNT} || echo "Can't extract alpine box"

echo "Flush writes to disk"
sync

echo "Unmount"
umount ${MNT}

losetup -d "${DEV}"
echo "Compress img as zip"

zip -r ${IMG}.zip ${IMG}

# Setup 32 bit
if [ -f ${ALP32} ]; then
   dd if=/dev/zero of=${IMG32} bs=1M count=256 && \
   DEV32=$(losetup -f) && \
   losetup -f ${IMG32} && \
   parted -s "${DEV32}" mklabel msdos mkpart p fat32 2048s 100% set 1 boot on && \
   echo "Preparing 32 bit arm image" && \
   mkfs.vfat "${DEV32}"p1 -IF 32

   echo "Mount FAT partition"
   mount "${DEV32}"p1 "${MNT}"
   echo "Extract alpine distribution and copy to 32 bit"
   tar -xzf ${ALP32} -C ${MNT}/ --no-same-owner || echo "Cant extract alpine"
   cp ../box.apkovl.tar.gz ${MNT} || echo "Cant extract alpine box"
   sync
   umount ${MNT}
   losetup -d "${DEV32}"
   zip -r ${IMG32}.zip ${IMG32}
fi

echo "Done!"
echo "You may flash your ${IMG}.zip using Etcher or dd the ${IMG}"
echo "or you may flash your ${IMG32}.zip using Etcher or dd the ${IMG32}"

