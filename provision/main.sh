#!/bin/bash
set -eux

node_id=$1; shift
ip=$1; shift
cluster_network_first_node_ip=$1; shift
cluster_network=$1; shift
cluster_ip=$1; shift
storage_ip=$1; shift
gateway_ip=$1; shift
fqdn=$(hostname --fqdn)
domain=$(hostname --domain)
dn=$(hostname)

# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive

# update the package cache.
apt-get update

# configure the network.
ifdown vmbr0
cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    # vagrant network.

auto eth1
iface eth1 inet manual
    # service network.

auto eth2
iface eth2 inet static
    # corosync network.
    address $cluster_ip
    netmask 255.255.255.0

auto eth3
iface eth3 inet static
    # storage network.
    address $storage_ip
    netmask 255.255.255.0

auto vmbr0
iface vmbr0 inet static
    # service network.
    address $ip
    netmask 255.255.255.0
    bridge_ports eth1
    bridge_stp off
    bridge_fd 0
EOF
cat >>/etc/dhcp/dhclient.conf <<EOF
# make sure resolv.conf will always have our gateway dns server.
supersede domain-name-servers $gateway_ip;
EOF
cat >/etc/resolv.conf <<EOF
nameserver $gateway_ip
EOF
cat >/etc/hosts <<EOF
127.0.0.1 localhost.localdomain localhost
$ip $fqdn $dn pvelocalhost
EOF
sed 's,\\,\\\\,g' >/etc/issue <<'EOF'

     _ __  _ __ _____  ___ __ ___   _____  __ __   _____
    | '_ \| '__/ _ \ \/ / '_ ` _ \ / _ \ \/ / \ \ / / _ \
    | |_) | | | (_) >  <| | | | | | (_) >  <   \ V /  __/
    | .__/|_|  \___/_/\_\_| |_| |_|\___/_/\_\   \_/ \___|
    | |
    |_|

EOF
cat >>/etc/issue <<EOF
    https://$ip:8006/
    https://$fqdn:8006/

EOF
ifup vmbr0
ifup eth2
ifup eth3
iptables-save # show current rules.
killall agetty | true # force them to re-display the issue file.

# configure postfix to relay emails through our gateway.
echo $domain >/etc/mailname
postconf -e 'myorigin = /etc/mailname'
postconf -e 'mydestination = '
postconf -e "relayhost = $domain"
postconf -e 'inet_protocols = ipv4'
systemctl reload postfix
# send test email.
sendmail root <<EOF
Subject: Hello World from `hostname --fqdn` at `date --iso-8601=seconds`

Hello World! 
EOF

# disable the "You do not have a valid subscription for this server. Please visit www.proxmox.com to get a list of available options."
# message that appears each time you logon the web-ui.
# NB this file is restored when you (re)install the pve-manager package.
echo 'Proxmox.Utils.checked_command = function(o) { o(); };' >>/usr/share/pve-manager/js/pvemanagerlib.js

# install vim.
apt-get install -y --no-install-recommends vim
cat >/etc/vim/vimrc.local <<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF

# configure the shell.
cat >/etc/profile.d/login.sh <<'EOF'
[[ "$-" != *i* ]] && return
export EDITOR=vim
export PAGER=less
alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF

cat >/etc/inputrc <<'EOF'
set input-meta on
set output-meta on
set show-all-if-ambiguous on
set completion-ignore-case on
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
EOF

# configure the motd.
# NB this was generated at http://patorjk.com/software/taag/#p=display&f=Big&t=proxmox%20ve.
#    it could also be generated with figlet.org.
cat >/etc/motd <<'EOF'

     _ __  _ __ _____  ___ __ ___   _____  __ __   _____
    | '_ \| '__/ _ \ \/ / '_ ` _ \ / _ \ \/ / \ \ / / _ \
    | |_) | | | (_) >  <| | | | | | (_) >  <   \ V /  __/
    | .__/|_|  \___/_/\_\_| |_| |_|\___/_/\_\   \_/ \___|
    | |
    |_|

EOF

if [ "$cluster_ip" == "$cluster_network_first_node_ip" ]; then
    # configure the keyboard.
    echo 'keyboard: pt' >>/etc/pve/datacenter.cfg

    # list the gateway nfs shares.
    pvesm scan nfs $gateway_ip

    # add the iso-templates shared storage pool.
    pvesm add nfs iso-templates \
        --server $gateway_ip \
        --export /srv/nfs/iso-templates \
        --options vers=3 \
        --content iso,vztmpl

    # add the snippets shared storage pool.
    pvesm add nfs snippets \
        --server $gateway_ip \
        --export /srv/nfs/snippets \
        --options vers=3 \
        --content snippets
fi

# create the cluster or add the node to the cluster.
# see https://pve.proxmox.com/wiki/Cluster_Manager
# see https://pve.proxmox.com/pve-docs/pve-admin-guide.html#_cluster_network
if [ "$cluster_ip" == "$cluster_network_first_node_ip" ]; then
    pvecm create example -nodeid $node_id -link0 $cluster_ip
else
    apt-get install -y --no-install-recommends expect
    # add the node to the cluster by automatically entering the root password and accept the host SSH key fingerprint. e.g.:
    #   pve2: Please enter superuser (root) password for '10.2.0.201':
    #   pve2: Etablishing API connection with host '10.2.0.201'
    #   pve2: The authenticity of host '10.2.0.201' can't be established.
    #   pve2: X509 SHA256 key fingerprint is 4B:6A:76:6F:32:31:A5:52:D4:C9:D3:94:23:CF:DD:35:AC:6D:AC:8D:81:42:D6:51:DA:E2:CC:C9:BD:92:0C:61.
    #   pve2: Are you sure you want to continue connecting (yes/no)? 
    expect <<EOF
spawn pvecm add $cluster_network_first_node_ip -nodeid $node_id -link0 $cluster_ip
expect -re "Please enter superuser (root) password for .+:"; send "vagrant\\r"
expect "Are you sure you want to continue connecting (yes/no)? "; send "yes\\r"
expect eof
EOF
fi
pvecm status || true
pvecm nodes
