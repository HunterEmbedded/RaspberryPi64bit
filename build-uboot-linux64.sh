#!/bin/sh

# This script builds a 64 bit version of u-boot and linux kernel and then 
# adds them to a Raspbian image to create a .img file that can be written to 
# an SD card
# It has been tested on RPi3+


# Set some variables to help with the build
ROOTDIR=`pwd`

# Select 64 bit arm for kernel and correct cross compiler
ARM_TYPE=arm64
CROSS_COMPILE=aarch64-linux-gnu-
ARCH=${ARM_TYPE}

LINARO_TOOL_VERSION="7.3.1-2018.05"

# Set name of RASPBIAN image which is the date it was created
RASPBIAN_NAME="2018-07-11-Raspbian"

# RPi is officially only supported with 32 bit.
# So need to download a 64 bit compiler
if [ ! -e aarch64-toolchain.downloaded ]; then
  mkdir -p tools || exit
  cd tools || exit 
  wget https://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/aarch64-linux-gnu/gcc-linaro-${LINARO_TOOL_VERSION}-x86_64_aarch64-linux-gnu.tar.xz || exit
  tar -xJf gcc-linaro-${LINARO_TOOL_VERSION}-x86_64_aarch64-linux-gnu.tar.xz || exit
  cd ..
  touch aarch64-toolchain.downloaded
fi

# set up path for tools
TOOLPATH=${ROOTDIR}/tools/gcc-linaro-${LINARO_TOOL_VERSION}-x86_64_aarch64-linux-gnu

export PATH=${TOOLPATH}/bin:${PATH}

###########################################################################
# Now download and patch the 4.14 kernel.
###########################################################################

# download kernel if required
if [ ! -e kernel.cloned ]; then
   git clone https://github.com/raspberrypi/linux || exit
   touch kernel.cloned
fi

if [ ! -e kernel.checkedout ]; then
   cd linux
   # checkout latest 4.14, this will always be the HEAD of 4.14-y and so change every day
   #git checkout -b rpi-4.14-y || exit
   ##!!!! This is HEAD from rpi-4.14-y on 11th July 2018 which is date script was tested !!!!
   git checkout db81c14ce9fbd705c2d3936edecbc6036ace6c05 -b rpi-4.14-y || exit
   cd ..
   touch kernel.checkedout
fi

# patch kernel if required
if [ ! -e kernel.patched ]; then
   cd linux
   # This patch allows Rpi3B to have terminal rather than Bluetooth 
   git am ../patches/kernel/0001-use-device-tree-to-swap-UART-pin-usage-on-RPi-3B-for.patch || exit
 
   cd ..
   touch kernel.patched
fi

###########################################################################
# Now download and build the 2018.05 u-boot.
###########################################################################

if [ ! -e uboot-downloaded ]
then
    git clone git://git.denx.de/u-boot.git
    cd u-boot/

     # update to latest tag 
    git checkout v2018.05 -b tmp || exit

    # configure it once after download
    # uboot does not have a separate arm64 architecture so here still specify arm
    # but use a 64 bit compiler
    make ARCH=arm CROSS_COMPILE=${TOOLPATH}/bin/${CROSS_COMPILE} distclean || exit   
    make ARCH=arm CROSS_COMPILE=${TOOLPATH}/bin/${CROSS_COMPILE} rpi_3_defconfig || exit

    touch ../uboot-downloaded
  cd ..
fi

# Build the full u-boot
cd u-boot/
make ARCH=arm CROSS_COMPILE=${TOOLPATH}/bin/${CROSS_COMPILE} || exit
cd ..

###########################################################################
# Now create a new img file from a standard Raspbian that can be mounted
# and then modified with the new u-boot and kernel
###########################################################################


# copy the clean img file so that we can mount and edit it
mkdir -p raspbian-image

# If the selected RASPBIAN image does not exist, exit with an error
if [ ! -d pi-gen/work/${RASPBIAN_NAME} ]; then
  echo "RASPBIAN_NAME needs to be set correctly in this script."
  echo "pi-gen/work/${RASPBIAN_NAME} needs to exist"
  exit
fi  


cp pi-gen/work/${RASPBIAN_NAME}/export-image/${RASPBIAN_NAME}-lite.img raspbian-image/uboot-linux64.img || exit


# Set paths to mount the partitions
BOOT_PART=mnt/boot
ROOTFS_PART=mnt/rootfs
# create mount directories for the two partitions
mkdir -p ${BOOT_PART}
mkdir -p ${ROOTFS_PART}


# Assume this is standard img with following characteristics found by fdisk -l uboot-linux64.img
#fdisk -l uboot-linux64.img
#Disk uboot-linux64.img: 1.7 GiB, 1799356416 bytes, 3514368 sectors
#Units: sectors of 1 * 512 = 512 bytes
#Sector size (logical/physical): 512 bytes / 512 bytes
#I/O size (minimum/optimal): 512 bytes / 512 bytes
#Disklabel type: dos
#Disk identifier: 0xe9b5dd7a
#
#Device     Boot Start     End Sectors  Size Id Type
#uboot-linux64.img1         8192   96484   88293 43.1M  c W95 FAT32 (LBA)
#uboot-linux64.img2        98304 3514367 3416064  1.6G 83 Linux

# This is how the offsets are calculated in the two mount instructions 
# 4194304 = 8192*512
sudo mount -v -o offset=4194304 -t vfat raspbian-image/uboot-linux64.img ${BOOT_PART}
# 50331648 = 98304*512
sudo mount -v -o offset=50331648 -t ext4 raspbian-image/uboot-linux64.img ${ROOTFS_PART}

###########################################################################
# Now build the 64 bit kernel
# and install it to the boot partition
###########################################################################
cd linux


# do a full clean
sudo make ARCH=${ARCH} CROSS_COMPILE=${TOOLPATH}/bin/${CROSS_COMPILE} distclean

# configure 
make ARCH=${ARCH} CROSS_COMPILE=${TOOLPATH}/bin/${CROSS_COMPILE} bcmrpi3_defconfig

#build kernel, modules and device tree files
make -j 6 ARCH=${ARCH} CROSS_COMPILE=${TOOLPATH}/bin/${CROSS_COMPILE} Image dtbs modules

# Install kernel modules
# need to pass all defines as sudo uses a different environment
sudo make ARCH=${ARCH} CROSS_COMPILE=${TOOLPATH}/bin/${CROSS_COMPILE} INSTALL_MOD_PATH=../${ROOTFS_PART} modules_install

# remove all raspbian kernel*.img files from the boot partition 
# so that one we create is guaranteed to be the one run by RPi bootloader firmware
sudo rm ../${BOOT_PART}/kerne*.img

# install linux and device tree to boot partition
sudo cp arch/${ARM_TYPE}/boot/Image ../${BOOT_PART}/Image || exit
sudo cp arch/${ARM_TYPE}/boot/dts/broadcom/*.dtb ../${BOOT_PART}/ || exit
sudo cp arch/${ARM_TYPE}/boot/dts/overlays/*.dtbo ../${BOOT_PART}/overlays || exit
sudo cp arch/${ARM_TYPE}/boot/dts/overlays/README ../${BOOT_PART}/overlays || exit

# install u-boot.bin to the boot partition
# calling u-boot.bin kernel8.img means that it is the executable the GPU fw will load and 8 means it is 64 bit
sudo cp ../u-boot/u-boot.bin ../${BOOT_PART}/kernel8.img
cd ..


###########################################################################
# Now configure the RPi firmware (ie GPU) to correctly run u-boot and then kernel
###########################################################################


# set up uboot script to boot the kernel using a boot.scr file in boot partition
# load kernel to 0x01080000 as that is its run address and it saves relocation
sh -c "echo '
setenv kernel_addr_r 0x01080000
fatload mmc 0:1 \${kernel_addr_r} Image
fatload mmc 0:1 0x01000000 bcm2710-rpi-3-b-plus.dtb
booti \${kernel_addr_r} - 0x01000000' > rpi3-bootscript.txt"

mkimage -A arm64 -O linux -T script -d rpi3-bootscript.txt boot.scr 
sudo cp boot.scr mnt/boot/


# configure the RPi firmware (ie GPU) using the config.txt file
# enable the UART for terminal output
sudo sh -c "echo 'enable_uart=1' >> mnt/boot/config.txt"

# enable 64 bit arm support
sudo sh -c "echo 'arm_control=0x200' >> mnt/boot/config.txt"

sudo sh -c "echo '' > mnt/boot/cmdline.txt"



# configure the filesystem to handle fact Bluetooth is not going to work as
# UART1 is used for terminal

# stop the hciuart service from running in systemd and trying to use UART1
sudo rm mnt/rootfs/etc/systemd/system/multi-user.target.wants/hciuart.service

# enable ssh in Linux by creating file ssh on /boot
sudo touch mnt/boot/ssh

###########################################################################
# Finally unmount the updated partitions
###########################################################################


sudo umount ${BOOT_PART}
sudo umount ${ROOTFS_PART}

###########################################################################
# The file raspbian-image/uboot-linux64.img is now ready to be written to 
# an SD card with a tool like Etcher
###########################################################################

