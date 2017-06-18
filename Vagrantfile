number_of_nodes = 3
service_network_first_node_ip = '10.1.0.201'
cluster_network_first_node_ip = '10.2.0.201'; cluster_network='10.2.0.0'

require 'ipaddr'
service_ip_addr = IPAddr.new service_network_first_node_ip
cluster_ip_addr = IPAddr.new cluster_network_first_node_ip

Vagrant.configure('2') do |config|
  config.vm.box = 'proxmox-ve-amd64'
  config.vm.provider :virtualbox do |vb|
    vb.linked_clone = true
    vb.memory = 3*1024
    vb.cpus = 4
  end
  (1..number_of_nodes).each do |n|
    name = "pve#{n}"
    fqdn = "#{name}.example.com"
    service_ip = service_ip_addr.to_s; service_ip_addr = service_ip_addr.succ
    cluster_ip = cluster_ip_addr.to_s; cluster_ip_addr = cluster_ip_addr.succ
    config.vm.define name do |config|
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: service_ip, auto_config: false
      config.vm.network :private_network, ip: cluster_ip, auto_config: false
      config.vm.provision :shell,
        path: 'provision.sh',
        args: [
          service_ip,
          cluster_network_first_node_ip,
          cluster_network,
          cluster_ip
        ]
      config.vm.provision :reload
      config.vm.provision :shell, path: 'summary.sh', args: service_ip
    end
  end
end
