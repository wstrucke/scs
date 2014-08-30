#!/bin/sh

# provision/deprovision kvm virtual machines
#
# William Strucke [wstrucke@gmail.com]
# Version 1.0.0 - 2012-01-24
# - initial release: https://scribe.2checkout.com/view.html?wid=32098
# Version 1.1.0 - 2014-08-28
# - near complete re-implementation and new options
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
  --arch <string>  system architecture: either i386 or x86_64, default i386
  --cpu <int>      number of processors, default 1
  --destroy        forcibly remove the VM if it already exists - DATA LOSS WARNING -
  --disk <int>     size of disk in GB, default 30
  --dry-run        do not make any changes, simply output the expected commands
  --ip <string>    specify static ip during build, default dhcp
  --ks <URL>       full URL to optional kick-start answer file
  --mac <string>   physical address to assign, default auto-generate
  --no-console     do not automatically connect the console, useful for automation
  --no-reboot      do not automatically restart the system following the install
  --os <string>    operating system for build: either centos5 or centos6, default centos5
  --quiet          silence as much output as possible
  --ram <int>      amount of ram in MB, default 512
  --uuid <string>  specify the uuid to assign, default auto-generate
  --yes-i-am-sure  do not prompt for confirmation of destructive changes

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
BUILD_NET_DNS="192.168.32.46"
BUILD_NET_GW="192.168.32.10"
BUILD_NET_MASK="255.255.254.0"
BUILD_NET_INTERFACE="br3"
HYPERVS="kvm-01 kvm-02 kvm-03"
WEBROOT="http://192.168.32.39/centos"
VMDIR=/san/virtual-machines

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
OSLIST="centos4 centos5 centos6"

# defaults
DESTROY=0
DRYRUN=0
KSURL=""
INSTALL_URL=""
QUIET=0
SURE=0
VMADDR=""
VMARCH="i386"
VMCONSOLE=1
VMCPUS=1
VMIP=""
VMNAME=""
VMOS="centos5"
VMRAM=512
VMREBOOT=1
VMSIZE=30
VMUUID=""

# settings
while [ $# -gt 0 ]; do case $1 in
  -a|--arch) VMARCH="$2"; shift;;
  -c|--cpu) VMCPUS="$2"; shift;;
  -d|--disk) VMSIZE="$2"; shift;;
  -k|--ks) KSURL="$2"; shift;;
  -i|--ip) VMIP="$2"; shift;;
  -m|--mac) VMADDR="$2"; shift;;
  -o|--os) VMOS="$2"; shift;;
  -q|--quiet) QUIET=1;;
  -r|--ram) VMRAM="$2"; shift;;
  -u|--uuid) VMUUID="$2"; shift;;
  --destroy) DESTROY=1;;
  --dry-run) DRYRUN=1;;
  --no-console) VMCONSOLE=0;;
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

# check minimum system requirements
if [[ "$VMOS" == "centos4" && "$VMARCH" != "i386" ]]; then err "Centos 4 only supports i386 architecture"; fi
if [[ "$VMOS" == "centos6" && $VMRAM -lt 1024 ]]; then err "CentOS 6 requires at least 1GB of RAM"; fi
if [[ "$VMOS" == "centos6" && $VMSIZE -lt 30 ]]; then err "CentOS 6 requires at least 30GB of disk"; fi

# set up urls
if [ -z "$KSURL" ]; then VAR="${VMOS}_${VMARCH}_ks"; KSURL=${!VAR}; fi
VAR="${VMOS}_${VMARCH}_root"; INSTALL_URL=${!VAR}

# protection
if [ -f ${VMDIR}/${VMNAME}.img ]; then
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

# build the installation arguments
ARGS="--name ${VMNAME} --ram=${VMRAM} --vcpus=${VMCPUS} --os-type=linux"

case $VMARCH in
  i386|i686) ARGS="$ARGS --arch=i686";;
  x86_64) ARGS="$ARGS --arch=x86_64";;
esac

case $VMOS in
  centos4) ARGS="$ARGS --os-variant=rhel4";;
  centos5) ARGS="$ARGS --os-variant=rhel5.4";;
  centos6) ARGS="$ARGS --os-variant=rhel6";;
esac

# add optional arguments
test ! -z "$VMADDR" && ARGS="$ARGS --mac=${VMADDR}"
test ! -z "$VMUUID" && ARGS="$ARGS --uuid=${VMUUID}"
test $VMCONSOLE -eq 0 && ARGS="$ARGS --noautoconsole"
test $VMREBOOT -eq 0 && ARGS="$ARGS --noreboot"

ARGS="$ARGS --accelerate --hvm \
--disk path=${VMDIR}/${VMNAME}.img,size=${VMSIZE},format=qcow2,cache=writeback \
--network=bridge:${BUILD_NET_INTERFACE} --location=${INSTALL_URL} --nographics \
--extra-args=\"ks=${KSURL} ksdevice=${BUILD_NET_INTERFACE}"

# optionally append ip data if a static address was provided
if [ ! -z "$VMIP" ]; then
  ARGS="$ARGS ip=${VMIP} netmask=${BUILD_NET_MASK} dns=${BUILD_NET_DNS} gateway=${BUILD_NET_GW}"
fi

ARGS="$ARGS console=ttyS0\""

# create the disk
if [ $DRYRUN -eq 1 ]; then
  echo "DRY-RUN: Create disk..."
  echo "qemu-img create -f qcow2 ${VMDIR}/${VMNAME}.img ${VMSIZE}G"
  echo
else
  if [ $QUIET -eq 1 ]; then
    qemu-img create -f qcow2 ${VMDIR}/${VMNAME}.img ${VMSIZE}G >/dev/null 2>&1
  else
    qemu-img create -f qcow2 ${VMDIR}/${VMNAME}.img ${VMSIZE}G
  fi
  test $? -eq 0 || err "Error creating disk"
echo
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
