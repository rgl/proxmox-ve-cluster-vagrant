#!/bin/bash
set -eux

storage_network_first_node_ip=$1
storage_network="$2/24"
storage_ip=$3
storage_monitor_ips=$4

dmi_sys_vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor)
if [ "$dmi_sys_vendor" == 'QEMU' ]; then
    osd_disk_device='/dev/sdb'
else
    osd_disk_device='/dev/sdb'
fi

# install ceph.
yes | pveceph install

# create the ceph cluster.
# see https://pve.proxmox.com/wiki/Ceph_Server
# see https://pve.proxmox.com/wiki/Storage:_RBD
# see https://pve.proxmox.com/pve-docs/chapter-pvesm.html
# see https://pve.proxmox.com/pve-docs/pveceph.1.html
# see https://pve.proxmox.com/pve-docs/pvesm.1.html
# run pveceph help createpool
if [ "$storage_ip" == "$storage_network_first_node_ip" ]; then
    # initialize ceph.
    pveceph init --network $storage_network
    pveceph createmon
    mkdir /etc/pve/priv/ceph

    # create a storage pool for lxc containers.
    pve_pool_name='ceph-lxc'
    pveceph createpool $pve_pool_name \
        --size 3 \
        --min_size 2 \
        --pg_num 64
    pvesm add rbd $pve_pool_name \
        --monhost $storage_monitor_ips \
        --content rootdir \
        --krbd 1 \
        --pool $pve_pool_name \
        --username admin

    # create a storage pool for virtual machines.
    pve_pool_name='ceph-vm'
    pveceph createpool $pve_pool_name \
        --size 3 \
        --min_size 2 \
        --pg_num 64
    pvesm add rbd $pve_pool_name \
        --monhost $storage_monitor_ips \
        --content images \
        --krbd 0 \
        --pool $pve_pool_name \
        --username admin
else
    pveceph createmon
fi

# wait for ceph to be ready.
# TODO find a better way.
# NB without this, the pveceph createosd command will fail with:
#       got timeout
sleep 5

# create an OSD in a disk.
pveceph createosd $osd_disk_device
