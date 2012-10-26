#!/bin/bash

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
# Config
#

# Get the location of the script
SCRIPT=$(readlink -f $0)
SCRIPTPATH=`dirname $SCRIPT`

FS_DIR="${SCRIPTPATH}/fs"
MOUNT_DIR="/mnt"
SDCARD_DEV="/dev/sdc"


DELETE_UNKNOWN_FILES=true
UMOUNT_ON_EXIT=true

######################################################################
# Functions


onexit () {
  local exit_status=${1:-$?}

  sync;sync

  if ${UMOUNT_ON_EXIT}; then
    umount ${MOUNT_DIR}/boot
    umount ${MOUNT_DIR}
  fi

  if [ ${exit_status} -eq 0 ]; then
    echo "--- DONE ---"
  else
    echo "!!! FAILED !!!"
  fi
  exit ${exit_status}
}


######################################################################
# Main 
#

if [ `id -u` -ne 0 ]; then
  echo "ERROR: This script needs root privilges"
  onexit 1
fi

mount | grep ${SDCARD_DEV}1 | umount ${SDCARD_DEV}1
mount | grep ${SDCARD_DEV}2 | umount ${SDCARD_DEV}2

mount ${SDCARD_DEV}2 ${MOUNT_DIR}

if [ ! -d ${MOUNT_DIR}/boot ]; then
  mkidr ${MOUNT_DIR}/boot
fi

mount ${SDCARD_DEV}1 ${MOUNT_DIR}/boot

delete_parm=""
if ${DELETE_UNKNOWN_FILES}; then
  delete_parm="--delete"
fi

rsync -v -a ${delete_parm} ${FS_DIR}/ ${MOUNT_DIR}/

onexit 0

