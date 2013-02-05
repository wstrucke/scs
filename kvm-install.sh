#!/bin/sh

# provision/deprovision kvm virtual machines
#

function usage {
  echo "Usage:"
  echo "  $0 vm-name vm-ip [centos5|centos6] [i386|x86_64] [disk] [ram]"
  echo
  echo "  disk   10, or numeric size in GB"
  echo "  ram    512, or numeric amount in MB"
  echo
  exit 0
}

# constants
WEBROOT="http://192.168.1.243/centos"
VMDIR=/san/virtual-machines

# settings
OS="$3"
VMNAME="$1"
VMIP="$2"
VMSIZE="$5"
VMRAM="$6"
VMCPUS=1
VMARCH="$4"

# restrictions
if [ `whoami` != 'root' ]; then
  echo "You must be root"; exit 1
fi
if [[ `hostname` != 'kvm-01' && `hostname` != 'kvm-02' && `hostname` != 'kvm-03' ]]; then
  echo "Run on kvm"; exit 1
fi

# verification
if [[ "$VMNAME" == "" || "$VMIP" == "" ]]; then usage; fi
if [ "$OS" == "" ]; then OS="centos5"; fi
if [ "$VMSIZE" == "" ]; then VMSIZE="15"; fi
if [ "$VMRAM" == "" ]; then VMRAM=512; fi
if [[ "$VMARCH" != "i386" && "$VMARCH" != "x86_64" ]]; then usage; fi

# protection
if [ -f ${VMDIR}/${VMNAME}.img ]; then echo "VM Already Exists"; exit 1; fi

# create the disk
qemu-img create -f qcow2 ${VMDIR}/${VMNAME}.img ${VMSIZE}G
if [ $? -ne 0 ]; then echo "Error creating disk!"; exit 1; fi

# create the virtual machine
case ${OS} in
centos5)
  if [ $VMARCH == "i386" ]; then
    virt-install --name ${VMNAME} --ram=${VMRAM} --vcpus=${VMCPUS} \
    --os-type=linux --os-variant=rhel5.4 --accelerate --hvm \
    --disk path=${VMDIR}/${VMNAME}.img,size=${VMSIZE},format=qcow2,cache=writeback \
    --network=bridge:br3 --location=${WEBROOT}/5/os/i386/ \
    --nographics --extra-args="ks=${WEBROOT}/ks/generic-vm-5.cfg ksdevice=br3 \
    ip=${VMIP} netmask=255.255.254.0 dns=192.168.2.30 gateway=192.168.32.10 \
    console=ttyS0"
  else
    virt-install --name ${VMNAME} --ram=${VMRAM} --vcpus=${VMCPUS} \
    --arch=x86_64 --os-type=linux --os-variant=rhel5.4 --accelerate --hvm \
    --disk path=${VMDIR}/${VMNAME}.img,size=${VMSIZE},format=qcow2,cache=writeback \
    --network=bridge:br3 --location=${WEBROOT}/5/os/x86_64/ \
    --nographics --extra-args="ks=${WEBROOT}/ks/generic-vm-5x86_64.cfg ksdevice=br3 \
    ip=${VMIP} netmask=255.255.254.0 dns=192.168.2.30 gateway=192.168.32.10 \
    console=ttyS0"
  fi
  ;;
centos6)
  if [ $VMARCH != "x86_64" ]; then echo "CentOS 6 requires 64-bit architecture"; fi
  if [ $VMRAM -lt 1024 ]; then VMRAM=1024; fi
  virt-install --name ${VMNAME} --ram=${VMRAM} --vcpus=${VMCPUS} \
  --arch=x86_64 --os-type=linux --os-variant=rhel6 --accelerate --hvm \
  --disk path=${VMDIR}/${VMNAME}.img,size=${VMSIZE},format=qcow2,cache=writeback \
  --network=bridge:br3 --location=${WEBROOT}/6/os/x86_64/ \
  --nographics --extra-args="ks=${WEBROOT}/ks/generic-vm-6.cfg ksdevice=br3 \
  ip=${VMIP} netmask=255.255.254.0 dns=192.168.2.30 gateway=192.168.32.10 \
  console=ttyS0"
  ;;
 *)
  echo "VM Type Error"; exit 1;;
esac

if [ $? -ne 0 ]; then echo "Error creating VM!"; exit 1; fi

echo "Done"
exit 0
