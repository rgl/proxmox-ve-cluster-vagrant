#!/bin/bash
set -eux

dmi_sys_vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor)
if [[ "$dmi_sys_vendor" != 'QEMU' ]]; then
    # bail because QEMU is needed to run Virtual Machines.
    exit 0
fi

gateway_ip=$1
fqdn=$(hostname --fqdn)
dn=$(hostname)

# only continue if we are running in the 2nd node (our ceph storage pool
# needs, at minimum two replicas available, for creating/writing to a disk).
if [[ "$dn" != 'pve2' ]]; then
    exit 0
fi

# download the iso to the iso-templates shared storage.
iso_url=https://github.com/rgl/debian-live-builder-vagrant/releases/download/v20200101/debian-live-20200101-amd64.iso
iso_volume=iso-templates:iso/$(basename $iso_url)
iso_path=$(pvesm path $iso_volume)
if [[ ! -f $iso_path ]]; then
    wget -qO $iso_path $iso_url
fi

# create and start a virtual machine.
# see https://pve.proxmox.com/pve-docs/qm.1.html
pve_storage_id='ceph-vm'
for pve_id in 110; do
    pve_disk_size=64M
    pvesm alloc $pve_storage_id $pve_id vm-$pve_id-disk-1 $pve_disk_size
    if [[ "$pve_storage_id" =~ ^ceph-.+ ]]; then
        rbd ls $pve_storage_id
        rbd info $pve_storage_id/vm-$pve_id-disk-1
    fi
    pvesm status
    qm create $pve_id \
        -name debian-live-$pve_id \
        -keyboard pt \
        -onboot 1 \
        -ostype l26 \
        -cpu host \
        -cores 1 \
        -memory 512 \
        -cdrom $iso_volume \
        -scsihw virtio-scsi-pci \
        -virtio0 $pve_storage_id:vm-$pve_id-disk-1,size=$pve_disk_size \
        -net0 model=virtio,bridge=vmbr0 \
        -args '-device virtio-rng-pci'
    qm config $pve_id # show config.
    qm start $pve_id
    qm status $pve_id
    qm showcmd $pve_id
done
