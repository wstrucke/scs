#!/bin/sh

# provision/deprovision kvm virtual machines
#
# William Strucke [wstrucke@gmail.com]
# Version 1.0.0 - 2012-01-24
# - initial release
# Version 1.1.0 - 2014-08-28
# - near complete re-implementation and new options
#
# Copyright 2014
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Requires:
#   yum install -y libvirt libvirt-client libvirt-python qemu-img qemu-kvm python-virtinst virt-top ntop libguestfs libguestfs-tools libguestfs-tools-c perl-Sys-Guestfs
#

# error / exit function
#
function err {
  if [ $QUIET -ne 1 ]; then test ! -z "$1" && echo $1 >&2 || echo "An error occurred" >&2; fi
  test x"${BASH_SOURCE[0]}" == x"$0" && exit 1 || return 1
}

# help/usage function
#
function usage {
  test $QUIET -eq 1 && exit 2
  cat <<_EOF
Usage: $0 [...args...] vm-name

Options:
  --arch <string>       system architecture: either i386 or x86_64, default i386
  --base <string>       use a base qcow2 image as a backing file for the new VM
  --cpu <int>           number of processors, default 1
  --destroy             forcibly remove the VM if it already exists - DATA LOSS WARNING -
  --disk <int>          size of disk in GB, default 30
  --disk-path <string>  override path to the system disk
  --disk-type <string>  override disk type, option must be one of 'ide', 'scsi', 'usb', 'virtio' or 'xen'
  --dry-run             do not make any changes, simply output the expected commands
  --ip <string>         specify static ip during build, default dhcp
  --interface <string>  specify the bridge interface to attach to (default $BUILD_NET_INTERFACE)
  --ks <URL>            full URL to optional kick-start answer file
  --mac <string>        physical address to assign, default auto-generate
  --nic <string>        NIC model, one of 'e1000', 'rtl8139', or 'virtio'
  --no-console          do not automatically connect the console, useful for automation
  --no-install          do not kickstart or install an OS, just create a VM around the new disk image
  --no-reboot           do not automatically restart the system following the install
  --os <string>         operating system for build: either centos5 or centos6, default centos5
  --quiet               silence as much output as possible
  --ram <int>           amount of ram in MB, default 512
  --vnc <port>          activate VNC server on tcp port <port>
  --uuid <string>       specify the uuid to assign, default auto-generate
  --yes-i-am-sure       do not prompt for confirmation of destructive changes

_EOF
  exit 2
}

# Test an IP address for validity:
# Usage:
#      valid_ip IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ip IP_ADDRESS; then echo good; else echo bad; fi
#
# SOURCE: http://www.linuxjournal.com/content/validating-ip-address-bash-script
#
function valid_ip() {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS; IFS='.'; ip=($ip); IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}


# local constants
#
# primary dns server in build network
BUILD_NET_DNS=""
#
# gateway in build network
BUILD_NET_GW=""
#
# network mask for build network
BUILD_NET_MASK=""
#
# hypervisor interface name for the build network (bridge)
BUILD_NET_INTERFACE=""
#
# space seperated list of hypervisor host names (hosts this script can run on)
HYPERVS=""
#
# centos mirror URL
WEBROOT="http://mirror.cc.columbia.edu/pub/linux/centos"
#
# local directory for virtual machine disk images
VMDIR=""

# local settings
test -f "`dirname $0`/kvm-install.sh.settings" && source `dirname $0`/kvm-install.sh.settings

# global constants
XMLDIR=/etc/libvirt/qemu
centos4_i386_ks="${WEBROOT}/ks/generic-vm-4.cfg"
centos4_i386_root="${WEBROOT}/4/os/"
centos5_i386_ks="${WEBROOT}/ks/generic-vm-5.cfg"
centos5_i386_root="${WEBROOT}/5/os/i386/"
centos5_x86_64_ks="${WEBROOT}/ks/generic-vm-5x86_64.cfg"
centos5_x86_64_root="${WEBROOT}/5/os/x86_64/"
centos6_i386_ks="${WEBROOT}/ks/generic-vm-6.cfg"
centos6_i386_root="${WEBROOT}/6/os/i386/"
centos6_x86_64_ks="${WEBROOT}/ks/generic-vm-6-64.cfg"
centos6_x86_64_root="${WEBROOT}/6/os/x86_64/"

# argument validation
ARCHLIST="i386 x86_64"
DISK_TYPE_LIST="ide scsi usb virtio xen"
NIC_LIST="e1000 rtl8139 virtio"
OSLIST="centos4 centos5 centos6 ubuntu generic"

# defaults
BASE=""
DESTROY=0
DRYRUN=0
KSURL=""
INSTALL=1
INSTALL_URL=""
INTERFACE=""
QUIET=0
SURE=0
VMADDR=""
VMARCH="x86_64"
VMCONSOLE=1
VMCPUS=1
VMDISK=""
VMDISK_TYPE="virtio"
VMIP=""
VMNAME=""
VMNIC=""
VMOS="centos6"
VMRAM=1024
VMREBOOT=1
VMSIZE=40
VMUUID=""
VNC=""

# settings
while [ $# -gt 0 ]; do case $1 in
  -a|--arch) VMARCH="$2"; shift;;
  -b|--base) BASE="$2"; shift;;
  -c|--cpu) VMCPUS="$2"; shift;;
  -d|--disk) VMSIZE="$2"; shift;;
  -D|--disk-path) VMDISK="$2"; shift;;
  -k|--ks) KSURL="$2"; shift;;
  -I|--interface) INTERFACE="$2"; shift;;
  -i|--ip) VMIP="$2"; shift;;
  -m|--mac) VMADDR="$2"; shift;;
  -n|--nic) VMNIC="$2"; shift;;
  -o|--os) VMOS="$2"; shift;;
  -q|--quiet) QUIET=1;;
  -r|--ram) VMRAM="$2"; shift;;
  -T|--disk-type) VMDISK_TYPE="$2"; shift;;
  -u|--uuid) VMUUID="$2"; shift;;
  -v|--vnc) VNC="$2"; shift;;
  --destroy) DESTROY=1;;
  --dry-run) DRYRUN=1;;
  --no-console) VMCONSOLE=0;;
  --no-install) INSTALL=0;;
  --no-reboot) VMREBOOT=0;;
  --yes-i-am-sure) SURE=1;;
  *) test -z "$VMNAME" && VMNAME="$1" || usage;;
esac; shift; done


# restrictions
test `whoami` != 'root' && err "You must be root"
printf -- " $HYPERVS " |grep -q " `hostname` " || err "Run on kvm"

# verification
test -z "$VMNAME" && usage
test "${VMSIZE}${VMCPUS}${VMRAM}" != "${VMSIZE//[^0-9]/}${VMCPUS//[^0-9]/}${VMRAM//[^0-9]/}" && usage
test $VMSIZE -lt 15 && err "Minimum disk size is 15 GB"
test $VMCPUS -gt 48 && err "Maximum expected CPU value"
test $VMRAM -lt 128 && err "Minimum system memory is 128MB. Yes, this is arbitrary."
test $VMRAM -gt 131072 && err "Maximum system memory is 128GB. Yes, this is arbitrary."
if [ ! -z "$VMIP" ]; then valid_ip $VMIP || err "Invalid IP address"; fi
printf -- " $ARCHLIST " |grep -q " $VMARCH " || err "Invalid system architecture"
printf -- " $OSLIST " |grep -q " $VMOS " || err "Invalid operating system"
printf -- " $DISK_TYPE_LIST " |grep -q " $VMDISK_TYPE " || err "Invalid bus (disk type). Must be one of $DISK_TYPE_LIST."
if [ ! -z "$VMNIC" ]; then printf -- " $NIC_LIST " |grep -q " $VMNIC " || err "Invalid NIC model. Must be one of $NIC_LIST."; fi
if [[ ! -z "$VMDISK" && ! -f "$VMDISK" ]]; then err "Invalid disk specified: $VMDISK"; fi
if [ ! -z "$BASE" ]; then test -f "$BASE" || err "Invalid base image"; fi
if [ ! -z "$INTERFACE" ]; then
  /sbin/ifconfig $INTERFACE >/dev/null 2>&1 || err "Invalid interface"
fi
if [ ! -z "$VNC" ]; then printf -- " $( /bin/netstat -ln |grep '^tcp' |awk '{print $4}' |cut -d: -f2 |tr '\n' ' ' ) " |grep -q " $VNC " && err "VNC port in use"; fi

# if no interface was specified, use the default
if [ -z "$BUILD_NET_INTERFACE" ]; then BUILD_NET_INTERFACE=$( netstat -rn |grep -E '^0\.0\.0\.0' |awk '{print $NF}' ); fi
if [ -z "$INTERFACE" ]; then INTERFACE=$BUILD_NET_INTERFACE; fi

# check minimum system requirements
if [[ "$VMOS" == "centos4" && "$VMARCH" != "i386" ]]; then err "Centos 4 only supports i386 architecture"; fi
if [[ "$VMOS" == "centos6" && $VMRAM -lt 1024 ]]; then err "CentOS 6 requires at least 1GB of RAM"; fi
if [[ "$VMOS" == "centos6" && $VMSIZE -lt 30 ]]; then err "CentOS 6 requires at least 30GB of disk"; fi

# check settings
if [[ -z "$BUILD_NET_DNS" || -z "$BUILD_NET_GW" || -z "$BUILD_NET_MASK" || -z "$BUILD_NET_INTERFACE" || -z "$VMDIR" ]]; then err "Settings are not defined"; fi

# set up urls
if [ -z "$KSURL" ]; then VAR="${VMOS}_${VMARCH}_ks"; KSURL=${!VAR}; fi
VAR="${VMOS}_${VMARCH}_root"; INSTALL_URL=${!VAR}

# protection
if [[ -z ${VMDISK} && -f ${VMDIR}/${VMNAME}.img ]]; then
  if [ $DESTROY -eq 0 ]; then
    err "VM already exists"
  else
    if [ $DRYRUN -eq 1 ]; then
      echo "DRY-RUN: Destroying existing virtual machine..."
      virsh list --all |grep $VMNAME
      ls -l ${XMLDIR}/${VMNAME}.xml ${VMDIR}/${VMNAME}.img
    else
      if [ $SURE -eq 0 ]; then
	echo "This operation will permanently remove an existing VM."
        read -p "Are you sure (Y/n)? " Q
        if [ "$Q" != "Y" ]; then err "'$Q' is not Y, aborting!"; fi
      fi
      test $QUIET -eq 0 && echo "Destroying existing virtual machine..."
      virsh destroy $VMNAME >/dev/null 2>&1
      virsh undefine $VMNAME >/dev/null 2>&1
      test -f ${XMLDIR}/${VMNAME}.xml && rm -f ${XMLDIR}/${VMNAME}.xml
      test -f ${VMDIR}/${VMNAME}.img && rm -f ${VMDIR}/${VMNAME}.img
    fi
  fi
fi
printf -- " $( /usr/bin/virsh list --all 2>/dev/null |awk '{print $2}' |grep -vE '^(Name)?$' | tr '\n' ' ' ) " |grep -q " $VMNAME "
if [[ $? -eq 0 && $DESTROY -eq 0 ]]; then err "VM already registered"; fi


# build the installation arguments
ARGS="--name ${VMNAME} --ram=${VMRAM} --vcpus=${VMCPUS} --os-type=linux --accelerate --hvm"

case $VMARCH in
  i386|i686) ARGS="$ARGS --arch=i686";;
  x86_64) ARGS="$ARGS --arch=x86_64";;
esac

case $VMOS in
  centos4) ARGS="$ARGS --os-variant=rhel4";;
  centos5) ARGS="$ARGS --os-variant=rhel5.4";;
  centos6) ARGS="$ARGS --os-variant=rhel6";;
  generic) ARGS="$ARGS --os-variant=generic";;
  ubuntu)  ARGS="$ARGS --os-variant=ubuntuoneiric";;
esac

# add optional arguments
test ! -z "$VMADDR" && ARGS="$ARGS --mac=${VMADDR}"
test ! -z "$VMUUID" && ARGS="$ARGS --uuid=${VMUUID}"
test $VMCONSOLE -eq 0 && ARGS="$ARGS --noautoconsole"
test $VMREBOOT -eq 0 && ARGS="$ARGS --noreboot"

# set NIC settings
#
if [ -z "$VMNIC" ]; then
  ARGS="$ARGS --network=bridge:${INTERFACE}"
else
  ARGS="$ARGS --network=bridge:${INTERFACE},model=${VMNIC}"
fi

# set graphics settings
if [ -z "$VNC" ]; then
  ARGS="$ARGS --nographics"
else
  ARGS="$ARGS --graphics vnc,password=admin123,port=$VNC,listen=0.0.0.0"
fi

# optionally add kickstart settings
if [ $INSTALL -eq 1 ]; then
  ARGS="$ARGS --location=${INSTALL_URL} --extra-args=\"ks=${KSURL} ksdevice=${INTERFACE}"

  # optionally append ip data if a static address was provided
  if [ ! -z "$VMIP" ]; then
    ARGS="$ARGS ip=${VMIP} netmask=${BUILD_NET_MASK} dns=${BUILD_NET_DNS} gateway=${BUILD_NET_GW}"
  fi
  
  ARGS="$ARGS console=ttyS0\""
else
  ARGS="$ARGS --boot kernel_args=\"console=/dev/ttyS0,menu=off\" --import"
fi

# set disk path
if [ -z "$VMDISK" ]; then VMDISK="${VMDIR}/${VMNAME}.img"; fi

# set bus
if [ ! -z "$VMDISK_TYPE" ]; then VMDISK_TYPE=",bus=${VMDISK_TYPE}"; fi

if [[ ! -z "$BASE" || -f "${VMDISK}" ]]; then
  ARGS="$ARGS --disk path=${VMDISK},format=qcow2,cache=writeback${VMDISK_TYPE}"
  BASE="-b $BASE "
  VMSIZE=""
else
  ARGS="$ARGS --disk path=${VMDISK},size=${VMSIZE},format=qcow2,cache=writeback${VMDISK_TYPE}"
  VMSIZE="${VMSIZE}G"
fi

if ! [ -f "${VMDISK}" ]; then
  # create the disk
  if [ $DRYRUN -eq 1 ]; then
    echo "DRY-RUN: Create disk..."
    echo "qemu-img create ${BASE}-f qcow2 ${VMDISK} ${VMSIZE}"
    echo
  else
    if [ $QUIET -eq 1 ]; then
      eval qemu-img create ${BASE}-f qcow2 ${VMDISK} ${VMSIZE} >/dev/null 2>&1
    else
      eval qemu-img create ${BASE}-f qcow2 ${VMDISK} ${VMSIZE}
    fi
    test $? -eq 0 || err "Error creating disk"
  echo
  fi
fi

# create the virtual machine
if [ $DRYRUN -eq 1 ]; then
  echo "DRY-RUN: Create virtual-machine and start install process..."
  echo "virt-install $ARGS"
  echo
else
  if [[ $QUIET -eq 1 && $VMCONSOLE -eq 0 ]]; then
    eval virt-install ${ARGS} >/dev/null 2>&1
  else
    eval virt-install ${ARGS}
  fi
  test $? -eq 0 || err "Error creating VM"
fi

exit 0
