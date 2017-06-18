This is a 3-node proxmox-ve cluster wrapped in a vagrant environment.

Each node has the following components and is connected to the following networks:

![](cluster.png)

# Usage

Build and install the [proxmox-ve Base Box](https://github.com/rgl/proxmox-ve).

Add the following entries to your `/etc/hosts` file:

```
10.1.0.201 pve1.example.com
10.1.0.202 pve2.example.com
10.1.0.203 pve3.example.com
```

Install the following Vagrant plugins:

```bash
vagrant plugin install vagrant-reload   # see https://github.com/aidanns/vagrant-reload
vagrant plugin install vagrant-triggers # see https://github.com/emyl/vagrant-triggers
```

Run `vagrant up` to launch the 3-node cluster.

Access the Proxmox Web Administration endpoint at either one of the nodes, e.g., at [https://pve1.example.com:8006](https://pve1.example.com:8006).

Login as `root` and use the `vagrant` password.

# Reference

 * [Proxmox VE Cluster Manager](https://pve.proxmox.com/wiki/Cluster_Manager)
 * [Proxmox VE Ceph Server](https://pve.proxmox.com/wiki/Ceph_Server)
 * [Proxmox VE RADOS Block Device (RBD) Storage Pool Type](https://pve.proxmox.com/wiki/Storage:_RBD)
