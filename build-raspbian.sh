#!/bin/sh

if [ ! -e pi-gen-tools.installed ]; then
   sudo apt-get update
   sudo apt-get install quilt parted realpath qemu-user-static debootstrap zerofree pxz zip dosfstools bsdtar libcap2-bin grep rsync xz-utils
   touch pi-gen-tools.installed
fi

if [ ! -e pi-gen.downloaded ]; then
   git clone git://github.com/RPi-Distro/pi-gen
   touch pi-gen.downloaded
fi

cd pi-gen


# create config file
echo "IMG_NAME='Raspbian'" > config
echo "CLEAN=1" >> config
# Now build only a minimal FS so skip stages 4 and 5
touch ./stage3/SKIP ./stage4/SKIP ./stage5/SKIP
touch ./stage4/SKIP_IMAGES ./stage5/SKIP_IMAGES

sudo ./build.sh
