#!/bin/bash
#
# Author: Jan Van Winkel <vanwinkeljan@gmail.com>
#
# Following packages need to be installed:
# sudo apt-get install binfmt-support qemu qemu-user-static debootstrap
#
#
#
#


######################################################################
# Bash vehaviour

# Error Handling
# This will behave like "set -e" but with the extra that
# on exit is called
set -E
trap onexit ERR

# debug output
#set -x

######################################################################
# Default Config
#
# DO NOT EDIT
# Use Overwrite Config block instead
#

# Get the location of the script
SCRIPT=$(readlink -f $0)
SCRIPTPATH=`dirname $SCRIPT`

FS_DIR="${SCRIPTPATH}/fs"
PREPEND="###"
REPO="http://archive.raspbian.org/raspbian"
REPO_KEY="http://archive.raspbian.org/raspbian.public.key"
SUITE="wheezy"
ARCH="armhf"

CHROOT="LC_ALL=C LANGUAGE=C LANG=C chroot"
CHROOT_NO_INTERACTIVE="DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true ${CHROOT}"

# raspberrypi firmware repo
# see https://github.com/raspberrypi/firmware
FIRMWARE_REPO="${SCRIPTPATH}/../firmware"

# Ammount of ram assigned to GPU 
GPU_RAM=128

HOSTNAME="rpi"
FQN="rpi.local"
USE_DHCP=true
IP=""
GW=""
NETMASK=""
BROADCAST=""
NETWORK=""
DNS_NAMESERVERS=""
DNS_SEARCH=""

FORCE_CREATE_CHROOT=false
CONFIGURE=true
ADD_REPO=true
INSTALL_EXTRA_PACKAGES=true
ENTER_CHROOT=false

ROOT_PASSWORD="Change_Me"

LINUX_IMAGE_VERSION="3.2.0"
LINUX_IMAGE_UPSTEP="3"
LINUX_IMAGE="linux-image-${LINUX_IMAGE_VERSION}-${LINUX_IMAGE_UPSTEP}-rpi"
KERNEL_IMG="vmlinuz-${LINUX_IMAGE_VERSION}-${LINUX_IMAGE_UPSTEP}-rpi"


######################################################################
#Overwrite Config 
#ADD_REPO=false
#INSTALL_EXTRA_PACKAGES=false
#ENTER_CHROOT=true

HOSTNAME="imco100"
FQN="imco100.be.alcatel-lucent.com"
USE_DHCP=false
IP="172.31.237.100"
GW="172.31.237.1"
NETMASK="255.255.255.0"
BROADCAST="172.31.237.255"
NETWORK="172.31.237.0"
DNS_NAMESERVERS="138.203.68.208 138.203.68.209"
DNS_SEARCH="be.alcatel-lucent.com"


######################################################################
# Functions

onexit () {
  local exit_status=${1:-$?}

  # check if we need to unmount proc
  # sleep is need to make sure that dev is not in use any more of a chroot command fails
  sleep 1
  mount | grep "${FS_DIR}/proc" > /dev/null && umount ${FS_DIR}/proc || true
  mount | grep "${FS_DIR}/sys"  > /dev/null && umount ${FS_DIR}/sys  || true
  mount | grep "${FS_DIR}/dev"  > /dev/null && umount ${FS_DIR}/dev  || true

  if [ ${exit_status} -eq 0 ]; then 
    echo "${PREPEND} DONE"
  else
    echo "${PREPEND} FAILED"
  fi
  exit ${exit_status}
}

function create_chroot () {

  rm -rf ${FS_DIR}
  mkdir ${FS_DIR}

  echo "${PREPEND} Running debootstrap ..."
  debootstrap --arch=${ARCH} --foreign ${SUITE} ${FS_DIR} ${REPO}
  echo "${PREPEND} Finshed debootstrap ..."
  cp /usr/bin/qemu-arm-static ${FS_DIR}/usr/bin/qemu-arm-static
  echo "${PREPEND} Placed qemu-arm-static in chroot"

  echo "${PREPEND} Running Second Stage debootstrap ..."
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} /debootstrap/debootstrap --second-stage
  echo "${PREPEND} Finshed Second Stage debootstrap ..."
}

function add_repo () {
  echo "${PREPEND} Adding raspbian repo key"
  wget ${REPO_KEY} -O ${FS_DIR}/tmp/raspbian.public.key
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} apt-key add /tmp/raspbian.public.key
  rm ${FS_DIR}/tmp/raspbian.public.key
  echo "${PREPEND} Adding raspbian repo"
  echo "deb http://archive.raspbian.org/raspbian ${SUITE} main contrib non-free" > ${FS_DIR}/etc/apt/sources.list 
  echo "deb-src http://archive.raspbian.org/raspbian ${SUITE} main contrib non-free" >> ${FS_DIR}/etc/apt/sources.list 
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} apt-get update 
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} apt-get upgrade 
}

function enter_chroot () {
  mount_for_chroot
  echo "${PREPEND} Entering chroot, have fun"
  eval ${CHROOT} ${FS_DIR}
}

function mount_for_chroot () {
  mount | grep "${FS_DIR}/proc" > /dev/null || mount -t proc proc ${FS_DIR}/proc
  mount | grep "${FS_DIR}/sys"  > /dev/null || mount -t sysfs sys ${FS_DIR}/sys
  mount | grep "${FS_DIR}/dev"  > /dev/null || mount --bind /dev ${FS_DIR}/dev
}

function install_packages () {
  
  local boot_dir="${FIRMWARE_REPO}/boot"
  local gpu_dir="${FIRMWARE_REPO}/hardfp/opt/vc"

  mount_for_chroot

  # locales for embedded systems
  echo "${PREPEND} Installing locales"
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} apt-get -y install locales
  # this should grant us access via ssh
  echo "${PREPEND} Installing ssh server"
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} apt-get -y install openssh-server
  # this will allow to specify dns info in /et/network/interfaces
  echo "${PREPEND} Installing reslovconf" 
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} apt-get -y install resolvconf 
  # use the stock raspbian kernel
  echo "${PREPEND} Installing Kernel"
  eval ${CHROOT_NO_INTERACTIVE} ${FS_DIR} apt-get -y install ${LINUX_IMAGE}

  # seems that there is no package for raspberry pi boot/firmware
  # so will do some manualy copying
  echo "${PREPEND} Installing Boot firmware"
  cp ${boot_dir}/* ${FS_DIR}/boot
  
  # Make sure that the config file points to the correct kernel image
  # see for more info http://elinux.org/RPi_config.txt
  echo "${PREPEND} Adding config.txt file (kernel=${KERNEL_IMG}; GPU RAM=${GPU_RAM}MB)"
  cat > ${FS_DIR}/boot/config.txt << EOF
kernel=${KERNEL_IMG}
gpu_mem=${GPU_RAM}
EOF

  # kernel arguments
  echo "${PREPEND} Adding cmdline.txt"
  echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait" > ${FS_DIR}/boot/cmdline.txt

  # GPU stuff
  echo "${PREPEND} Installing VideoCore SW"
  cp -r ${gpu_dir} ${FS_DIR}/opt/
  echo "${PREPEND} Adding VideoCore bin to PATH"
  cat > ${FS_DIR}/etc/profile.d/vc.sh << EOF
if [ "\`id -u\`" -eq 0 ]; then
  PATH="\${PATH}:/opt/vc/bin:/opt/vc/sbin"
else
  PATH="\${PATH}:/opt/vc/bin"
fi
export PATH
EOF
  echo "${PREPEND} Adding VideoCore Libs to ldconfig"
  echo "/opt/vc/lib" > ${FS_DIR}/etc/ld.so.conf.d/vc.conf
  eval ${CHROOT} ${FS_DIR} ldconfig

  #todo read packages from file
}

function configure_hostname () {

  if [ ! ${HOSTNAME} ]; then
    echo "ERROR: No hostname given"
    onexit 1
  fi

  echo "${PREPEND} Setting hostname to ${HOSTNAME}"
  echo ${HOSTNAME} > ${FS_DIR}/etc/hostname

  echo "${PREPEND} Updating /etc/hosts with hostanme and fqn (${HOSTNAME}/${FQN})"
  cat >  ${FS_DIR}/etc/hosts << EOF
127.0.0.1	localhost ${HOSTNAME} ${FQN}
::1		localhost ip6-localhost ip6-loopback
fe00::0		ip6-localnet
ff00::0		ip6-mcastprefix
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

}

function configure_network () {

  local if_file="${FS_DIR}/etc/network/interfaces"
  local indent="       "

  cat > ${if_file} << EOD
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
EOD

  if ${USE_DHCP}; then
    echo "${PREPEND} Setting-up network interface (DHCP)"
    echo "iface eth0 inet dhcp" >> ${if_file}
  else
    echo "${PREPEND} Setting-up network interface (STATIC)"
    echo "iface eth0 inet static" >> ${if_file}
    if [ ${IP} ]; then
      echo "${indent} address ${IP}" >> ${if_file}
    else
      echo "ERROR: Using static network configuration but no IP address defined"
      onexit 1
    fi
    if [ ${NETMASK} ]; then
      echo "${indent} netmask ${NETMASK}" >> ${if_file}
    fi 
    if [ ${NETWORK} ]; then
      echo "${indent} network ${NETWORK}" >> ${if_file}
    fi 
    if [ ${BROADCAST} ]; then
      echo "${indent} broadcast ${BROADCAST}" >> ${if_file}
    fi 
    if [ ${GW} ]; then
      echo "${indent} gateway ${GW}" >> ${if_file}
    fi 
  fi

  if [ "${DNS_NAMESERVERS}" ]; then
    echo "${indent} dns-nameservers ${DNS_NAMESERVERS}" >> ${if_file}
  fi 
  if [ ${DNS_SEARCH} ]; then
    echo "${indent} dns-search ${DNS_SEARCH}" >> ${if_file}
  fi 

}

function change_root_password () {
  echo "${PREPEND} Setting Root Password (Don't forget to change this after boot ;) )"
  cat > ${FS_DIR}/tmp/setpassword << EOF
#!/bin/bash
echo -e "${ROOT_PASSWORD}\n${ROOT_PASSWORD}" | passwd
EOF
  chmod +x ${FS_DIR}/tmp/setpassword
  eval ${CHROOT} ${FS_DIR} /tmp/setpassword
  rm ${FS_DIR}/tmp/setpassword
}

function create_fstab () {
  echo "${PREPEND} Creating /etc/fstab"
  cat > ${FS_DIR}/etc/fstab << EOD
# /etc/fstab: static file system information.
#
# Use 'blkid -o value -s UUID' to print the universally unique identifier
# for a device; this may be used with UUID= as a more robust way to name
# devices that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    nodev,noexec,nosuid 0       0
devpts          /dev/pts        devpts  rw,nosuid,noexec,relatime,gid=5,mode=620        0       0
/dev/mmcblk0p1  /boot           vfat    defaults         0       0
/dev/mmcblk0p2  /               ext4    defaults,noatime 0       0
EOD

}

######################################################################
# MAIN

if [ `id -u` -ne 0 ]; then
  echo "ERROR: This script needs root privilges"
  onexit 1
fi

if [ -d ${FS_DIR}/debootstrap ]; then
  echo "${PREPEND} Detected debootstrap dir in ${FS_DIR}"
  echo "${PREPEND} This possibly mean that a previous debootstrap run failed, removing ${FS_DIR} ..."
  rm -rf ${FS_DIR}
fi

if [ ! -d ${FS_DIR} ] || ${FORCE_CREATE_CHROOT}; then
  create_chroot 
fi

change_root_password

if ${CONFIGURE}; then
  configure_hostname
  configure_network
  create_fstab
fi

if ${ADD_REPO}; then
  add_repo
fi

if ${INSTALL_EXTRA_PACKAGES}; then
  install_packages
fi

if ${ENTER_CHROOT}; then
  enter_chroot
fi

onexit 0
