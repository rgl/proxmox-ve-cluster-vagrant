#!/bin/bash
set -eux

ip=$1
domain=$(hostname --fqdn)
dn=$(hostname)
ca_file_name='example-ca'

pushd /vagrant/shared/$ca_file_name

# install the certificate.
# see https://pve.proxmox.com/wiki/HTTPS_Certificate_Configuration_(Version_4.x_and_newer)
cp $domain-key.pem "/etc/pve/nodes/$dn/pveproxy-ssl.key"
cp $domain-crt.pem "/etc/pve/nodes/$dn/pveproxy-ssl.pem"
systemctl restart pveproxy
# dump the TLS connection details and certificate validation result.
(printf 'GET /404 HTTP/1.0\r\n\r\n'; sleep .1) | openssl s_client -CAfile $ca_file_name-crt.pem -connect $domain:8006 -servername $domain
