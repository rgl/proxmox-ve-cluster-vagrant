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

# download the alpine iso to the iso-templates shared storage.
alpine_iso=alpine-virt-3.7.0-x86_64.iso
alpine_iso_volume=iso-templates:iso/$alpine_iso
alpine_iso_path=$(pvesm path $alpine_iso_volume)
if [[ ! -f $alpine_iso_path ]]; then
    wget -qO $alpine_iso_path http://dl-cdn.alpinelinux.org/alpine/v3.7/releases/x86_64/$alpine_iso
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
        -name alpine-$pve_id \
        -keyboard pt \
        -onboot 1 \
        -ostype l26 \
        -cpu host \
        -cores 1 \
        -memory 64 \
        -cdrom $alpine_iso_volume \
        -scsihw virtio-scsi-pci \
        -virtio0 $pve_storage_id:vm-$pve_id-disk-1,size=$pve_disk_size \
        -net0 model=virtio,bridge=vmbr0
    qm config $pve_id # show config.
    qm start $pve_id
    qm status $pve_id
    qm showcmd $pve_id
done
