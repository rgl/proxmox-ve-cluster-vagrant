#!/bin/bash
set -eux

ip=$1

# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive

# update the package cache.
apt-get update

# install tcpdump to locally being able to capture network traffic.
apt-get install -y tcpdump

# install dumpcap to remotely being able to capture network traffic using wireshark.
groupadd --system wireshark
usermod -a -G wireshark vagrant
cat >/usr/local/bin/dumpcap <<'EOF'
#!/bin/sh
# NB -P is to force pcap format (default is pcapng).
# NB if you don't do that, wireshark will fail with:
#       Capturing from a pipe doesn't support pcapng format.
exec /usr/bin/dumpcap -P "$@"
EOF
chmod +x /usr/local/bin/dumpcap
echo 'wireshark-common wireshark-common/install-setuid boolean true' | debconf-set-selections
apt-get install -y --no-install-recommends wireshark-common

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


#
# setup NAT.
# see https://help.ubuntu.com/community/IptablesHowTo

apt-get install -y iptables iptables-persistent

# enable IPv4 forwarding.
sysctl net.ipv4.ip_forward=1
sed -i -E 's,^\s*#?\s*(net.ipv4.ip_forward=).+,\11,g' /etc/sysctl.conf

# NAT through enp0s3 (formerly and traditionally eth0).
iptables -t nat -A POSTROUTING -s "$ip/24" ! -d "$ip/24" -o enp0s3 -j MASQUERADE

# load iptables rules on boot.
iptables-save >/etc/iptables/rules.v4


#
# provision the DNS/DHCP server.
# see http://www.thekelleys.org.uk/dnsmasq/docs/setup.html
# see http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html

apt-get install -y dnsutils dnsmasq
systemctl stop systemd-resolved
systemctl disable systemd-resolved
cat >/etc/resolv.conf <<'EOF'
nameserver 127.0.0.1
EOF
cat >/etc/dnsmasq.d/local.conf <<EOF
interface=enp0s8
dhcp-range=10.1.0.2,10.1.0.200,1m
host-record=example.com,$ip
host-record=pve1.example.com,10.1.0.201
host-record=pve2.example.com,10.1.0.202
host-record=pve3.example.com,10.1.0.203
server=8.8.8.8
EOF
systemctl restart dnsmasq


#
# provision the NFS server.
# see exports(5).

apt-get install -y nfs-kernel-server
install -d -o nobody -g nogroup -m 700 /srv/nfs/iso-templates
install -d -o nobody -g nogroup -m 700 /srv/nfs/snippets
install -d -m 700 /etc/exports.d
echo "/srv/nfs/iso-templates $ip/24(fsid=0,rw,no_subtree_check)" >/etc/exports.d/iso-templates.exports
echo "/srv/nfs/snippets $ip/24(fsid=0,rw,no_subtree_check)" >/etc/exports.d/snippets.exports
exportfs -a

# test access to the NFS server using NFSv3 (UDP and TCP) and NFSv4 (TCP).
showmount -e $ip
rpcinfo -u $ip nfs 3
rpcinfo -t $ip nfs 3
rpcinfo -t $ip nfs 4


#
# create a ssh key-pair and copy it to the host so it can be used in
# cloud-init configurations to allow us to login with an ssh key.

ssh-keygen -f ~/.ssh/id_rsa -t rsa -b 2048 -C "$USER@$(hostname)" -N ''
cp ~/.ssh/id_rsa.pub "/vagrant/shared/$(hostname)-$USER-rsa-ssh-key.pub"
