#!/bin/bash
set -eux

ip=$1
gateway_ip=$2
fqdn=$(hostname --fqdn)
dn=$(hostname)

# only continue if we are running in the 2nd node (our ceph storage pool
# needs, at minimum two replicas available, for creating/writing to a disk).
if [[ "$dn" != 'pve2' ]]; then
    exit 0
fi

# update the available container templates.
# NB this downloads the https://www.turnkeylinux.org catalog.
pveam update
pveam available # show templates.

# download the alpine template to the iso-templates shared storage.
pve_template=alpine-3.10-default_20190626_amd64.tar.xz
pveam download iso-templates $pve_template

# create and start a container.
pve_storage_id='ceph-lxc'
for pve_id in 100; do
    pve_ip=$(echo $ip | sed -E "s,\.[0-9]+\$,.$pve_id,")
    pve_disk_size=32M
    pvesm alloc $pve_storage_id $pve_id vm-$pve_id-disk-1 $pve_disk_size
    if [[ "$pve_storage_id" =~ ^ceph-.+ ]]; then
        rbd map $pve_storage_id/vm-$pve_id-disk-1
        rbd showmapped
        rbd ls $pve_storage_id
        rbd info $pve_storage_id/vm-$pve_id-disk-1
    fi
    pvesm status
    mkfs.ext4 $(pvesm path $pve_storage_id:vm-$pve_id-disk-1)
    if [[ "$pve_storage_id" =~ ^ceph-.+ ]]; then
        rbd unmap $pve_storage_id/vm-$pve_id-disk-1
    fi
    pct create $pve_id \
        iso-templates:vztmpl/$pve_template \
        -onboot 1 \
        -ostype alpine \
        -hostname alpine-$pve_id \
        -cores 1 \
        -memory 32 \
        -swap 0 \
        -rootfs $pve_storage_id:vm-$pve_id-disk-1,size=$pve_disk_size \
        -net0 name=eth0,bridge=vmbr0,gw=$gateway_ip,ip=$pve_ip/24
    pct config $pve_id # show config.
    pct start $pve_id
    pct exec $pve_id sh <<EOF
set -eux
apk() {
    while true; do
        /sbin/apk \$@ && break
        sleep 5
    done
}
apk update
apk add nginx
adduser -D -u 1000 -g www www
mkdir /www
cat >/etc/nginx/nginx.conf <<'EOC'
user www;
worker_processes 1;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    access_log /var/log/nginx/access.log;
    keepalive_timeout 3000;
    server {
        listen 80;
        root /www;
        index index.html;
        server_name localhost;
        client_max_body_size 4m;
        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
              root /var/lib/nginx/html;
        }
    }
}
EOC
cat >/www/index.html <<'EOC'
<!doctype html>
<html>
<head>
    <title>server $pve_id</title>
</head>
<body>
    this is server $pve_id
</body>
</html>
EOC
rc-service nginx start
rc-update add nginx default
EOF
    wget -qO- $pve_ip
    pct exec $pve_id -- cat /etc/alpine-release
    pct exec $pve_id -- passwd -d root                          # remove the root password.
    pct exec $pve_id -- sh -c "echo 'root:vagrant' | chpasswd"  # or change it to vagrant.
    pct exec $pve_id -- ip addr
    pct exec $pve_id -- route -n
    pct exec $pve_id -- ping $ip -c 2
    pct status $pve_id
done
