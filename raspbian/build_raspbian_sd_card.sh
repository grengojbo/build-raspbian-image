#!/bin/bash

# build your own Raspberry Pi SD card
#
# Modifications by
# Andrius Kairiukstis <andrius@kairiukstis.com>, http://andrius.mobi/
#
# 2013-05-05
#	resulting files will be stored in rpi folder of script
#	during installation, delivery contents folder will be mounted and install.sh script within it will be called
#
# 2013-04-20
#	distro replaced from Debian Wheezy to Raspbian (http://raspbian.org)
#	build environment and resulting files not in /tmp/rpi instead of /root/rpi
#	fixed umount issue
#	keymap selection replaced from German (deadkeys) to the US
#	size of resulting image was increased to 2GB
#
#	Install apt-cacher-ng (apt-get install apt-cacher-ng) and use deb_local_mirror
#	more: https://www.unix-ag.uni-kl.de/~bloch/acng/html/config-servquick.html#config-client
#
#
#
# by Klaus M Pfeiffer, http://blog.kmp.or.at/
#
# 2012-06-24
#	just checking for how partitions are called on the system (thanks to Ricky Birtles and Luke Wilkinson)
#	using http.debian.net as debian mirror,
#	see http://rgeissert.blogspot.co.at/2012/06/introducing-httpdebiannet-debians.html
#	tested successfully in debian squeeze and wheezy VirtualBox
#	added hint for lvm2
#	added debconf-set-selections for kezboard
#	corrected bug in writing to etc/modules
#
# 2012-06-16
#	improoved handling of local debian mirror
#	added hint for dosfstools (thanks to Mike)
#	added vchiq & snd_bcm2835 to /etc/modules (thanks to Tony Jones)
#	take the value fdisk suggests for the boot partition to start (thanks to Mike)
#
# 2012-06-02
#       improoved to directly generate an image file with the help of kpartx
#	added deb_local_mirror for generating images with correct sources.list
#
# 2012-05-27
#	workaround for https://github.com/Hexxeh/rpi-update/issues/4
#	just touching /boot/start.elf before running rpi-update
#
# 2012-05-20
#	back to wheezy, http://bugs.debian.org/672851 solved,
#	http://packages.qa.debian.org/i/ifupdown/news/20120519T163909Z.html
#
# 2012-05-19
#	stage3: remove eth* from /lib/udev/rules.d/75-persistent-net-generator.rules
#	initial

# you need at least
# apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

deb_mirror="http://archive.raspbian.org/raspbian"
deb_local_mirror="http://localhost:3142/archive.raspbian.org/raspbian"

deb_raspiorg_mirror="http://archive.raspberrypi.org/debian"
deb_raspiorg_local_mirror="http://localhost:3142/archive.raspberrypi.org/debian"

if [ ${EUID} -ne 0 ]; then
  echo "this tool must be run as root"
  exit 1
fi

show_help() {
cat << EOF
Usage: ${0##*/} [-h] [-d DEVICE] CREATURE1 CREATURE2...
Generate an SD image on DEVICE for CREATURES. With not DEVICE, create an image file instead.

    -h         display this help and exit
    -d DEVICE  DEVICE where to burn the image (if absent create an image file)
    CREATURE.   which Poppy Creature(s) is(are) used

EOF
}

device=""
creatures=""

OPTIND=1
while getopts "hd:" opt; do
    case "$opt" in
        h)
            show_help
            exit 0
            ;;
        d)  device=$OPTARG
            ;;
        '?')
            show_help >&2
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"

creatures=$@
EXISTING_ONES="poppy-humanoid poppy-ergo-jr"

if [ "${creatures}" == "" ]; then
  echo 'ERROR: option "CREATURE" not given. See -h.' >&2
  exit 1
fi

for creature in $creatures
  do
  if ! [[ $EXISTING_ONES =~ $creature ]]; then
    echo "ERROR: creature \"${creature}\" not among possible creatures (choices \"$EXISTING_ONES\")"
    exit 1
  fi
done


if ! [ -b ${device} ]; then
  echo "${device} is not a block device"
  exit 1
fi

if [ "${deb_local_mirror}" == "" ]; then
  deb_local_mirror=${deb_mirror}
fi

bootsize="64M"
deb_release="wheezy"

relative_path=`dirname $0`

# locate path of this script
absolute_path=`cd ${relative_path}; pwd`

# locate path of delivery content
delivery_path=`cd ${absolute_path}/../delivery; pwd`

# define destination folder where created image file will be stored
buildenv=`cd ${absolute_path}; cd ..; mkdir -p rpi/images; cd rpi; pwd`
# buildenv="/tmp/rpi"

# cd ${absolute_path}

rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"

today=`date +%Y%m%d`

image=""

if [ "${device}" == "" ]; then
  echo "no block device given, just creating an image"
  mkdir -p ${buildenv}
  image="${buildenv}/images/raspbian_basic_${deb_release}_${creature}_${today}.img"
  dd if=/dev/zero of=${image} bs=1MB count=3800
  device=`losetup -f --show ${image}`
  echo "image ${image} created and mounted as ${device}"
else
  dd if=/dev/zero of=${device} bs=512 count=1
fi

fdisk ${device} << EOF
n
p
1

+${bootsize}
t
c
n
p
2


w
EOF


if [ "${image}" != "" ]; then
  losetup -d ${device}
  device=`kpartx -va ${image} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
  device="/dev/mapper/${device}"
  bootp=${device}p1
  rootp=${device}p2
else
  if ! [ -b ${device}1 ]; then
    bootp=${device}p1
    rootp=${device}p2
    if ! [ -b ${bootp} ]; then
      echo "uh, oh, something went wrong, can't find bootpartition neither as ${device}1 nor as ${device}p1, exiting."
      exit 1
    fi
  else
    bootp=${device}1
    rootp=${device}2
  fi
fi

mkfs.vfat ${bootp}
mkfs.ext4 ${rootp}

mkdir -p ${rootfs}

mount ${rootp} ${rootfs}

mkdir -p ${rootfs}/proc
mkdir -p ${rootfs}/sys
mkdir -p ${rootfs}/dev
mkdir -p ${rootfs}/dev/pts
mkdir -p ${rootfs}/usr/src/delivery

mount -t proc none ${rootfs}/proc
mount -t sysfs none ${rootfs}/sys
mount -o bind /dev ${rootfs}/dev
mount -o bind /dev/pts ${rootfs}/dev/pts
mount -o bind ${delivery_path} ${rootfs}/usr/src/delivery

cd ${rootfs}

debootstrap --foreign --no-check-gpg --include=ca-certificates --arch armhf ${deb_release} ${rootfs} ${deb_local_mirror}
cp /usr/bin/qemu-arm-static usr/bin/
LANG=C chroot ${rootfs} /debootstrap/debootstrap --second-stage

mount ${bootp} ${bootfs}

echo "deb ${deb_local_mirror} ${deb_release} main contrib non-free
deb ${deb_raspiorg_local_mirror} ${deb_release} main
" > etc/apt/sources.list

echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" > boot/cmdline.txt

echo "proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
" > etc/fstab

HOSTNAME=${creature}
echo "$HOSTNAME" > etc/hostname
printf "127.0.1.1\t$HOSTNAME\n" >> etc/hosts

echo "auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
" > etc/network/interfaces

echo "vchiq
snd_bcm2835
" >> etc/modules

echo "console-common	console-data/keymap/policy	select	Select keymap from full list
console-common	console-data/keymap/full	select	us
" > debconf.set


echo "#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set

wget ${deb_raspiorg_mirror}/raspberrypi.gpg.key -O - | apt-key add -

cd /usr/src/delivery
apt-get update

apt-get -y install git-core binutils ca-certificates curl
wget --continue https://raw.github.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update
chmod +x /usr/bin/rpi-update
mkdir -p /lib/modules/3.1.9+
touch /boot/start.elf
rpi-update

apt-get -y install locales console-common ntp openssh-server less vim

apt-get -y install raspi-config

cp /usr/share/doc/raspi-config/sample_profile_d.sh /etc/profile.d/raspi-config.sh
chmod 755 /etc/profile.d/raspi-config.sh

apt-get install -y ssh locales less fbset sudo psmisc strace module-init-tools ifplugd ed ncdu
apt-get install -y console-setup keyboard-configuration debconf-utils parted unzip
apt-get install -y build-essential manpages-dev python bash-completion gdb pkg-config
apt-get install -y python-rpi.gpio v4l-utils
apt-get install -y lua5.1
[ "$(dpkg --print-architecture)" = armhf ] && apt-get install -y luajit
apt-get install -y hardlink ca-certificates curl
apt-get install -y fake-hwclock ntp nfs-common usbutils
apt-get install -y --no-install-recommends cifs-utils

# Add support for bonjour
apt-get -y install libnss-mdns

adduser --disabled-password --gecos \"\" pi
echo \"pi:raspberry\" | chpasswd
echo \"root:root\" | chpasswd

groupadd -f -r input

for GRP in adm dialout cdrom audio users sudo video games plugdev input; do
  adduser pi \$GRP
done

chmod +w /etc/sudoers
echo \"pi ALL=(ALL) NOPASSWD: ALL\" >> /etc/sudoers
chmod -w /etc/sudoers
usermod --pass='*' root # don't need root password any more

# execute install script at mounted external media (delivery contents folder)
cd /usr/src/delivery
./install.sh $creatures
cd

echo \"root:raspberry\" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules

rm -f third-stage
" > third-stage
chmod +x third-stage
LANG=C chroot ${rootfs} /third-stage

echo "deb ${deb_mirror} ${deb_release} main contrib non-free
deb-src ${deb_mirror} ${deb_release} main contrib non-free

deb ${deb_raspiorg_mirror} ${deb_release} main
deb-src ${deb_raspiorg_mirror} ${deb_release} main
" > etc/apt/sources.list

echo "#!/bin/bash
aptitude update
aptitude clean
apt-get clean
rm -f cleanup
" > cleanup
chmod +x cleanup
LANG=C chroot ${rootfs} /cleanup

cd ${rootfs}

sync
sleep 15

# Make sure we're out of the root fs. We won't be able to unmount otherwise, and umount -l will fail silently.
cd

umount -l ${bootp}

umount -l ${rootfs}/usr/src/delivery
umount -l ${rootfs}/dev/pts
umount -l ${rootfs}/dev
umount -l ${rootfs}/sys
umount -l ${rootfs}/proc

umount -l ${rootfs}
umount -l ${rootp}

# Remove device mapper bindings. Avoids running out of loop devices if run repeatedly.
dmsetup remove_all

echo "finishing ${image}"

if [ "${image}" != "" ]; then
  kpartx -d ${image}
  echo "created image ${image}"
fi

echo "done."
