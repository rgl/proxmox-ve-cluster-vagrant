# to make sure the pve1 node is created before the other nodes, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

number_of_nodes = 3
service_network_first_node_ip = '10.1.0.201'
cluster_network_first_node_ip = '10.2.0.201'; cluster_network='10.2.0.0'
storage_network_first_node_ip = '10.3.0.201'; storage_network='10.3.0.0'

require 'ipaddr'
service_ip_addr = IPAddr.new service_network_first_node_ip
cluster_ip_addr = IPAddr.new cluster_network_first_node_ip
storage_ip_addr = IPAddr.new storage_network_first_node_ip

storage_monitor_ip_addr = storage_ip_addr
storage_monitor_ips = (1..number_of_nodes).map do |n|
  storage_monitor_ip = storage_monitor_ip_addr.to_s
  storage_monitor_ip_addr = storage_monitor_ip_addr.succ
  storage_monitor_ip
end.join(';')

Vagrant.configure('2') do |config|
  config.vm.box = 'proxmox-ve-amd64'
  config.vm.provider :libvirt do |lv|
    lv.memory = 3*1024
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = true
    lv.keymap = 'pt'
  end
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
    storage_ip = storage_ip_addr.to_s; storage_ip_addr = storage_ip_addr.succ
    config.vm.define name do |config|
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: service_ip, auto_config: false
      config.vm.network :private_network, ip: cluster_ip, auto_config: false
      config.vm.network :private_network, ip: storage_ip, auto_config: false
      config.vm.provider :libvirt do |lv|
        lv.storage :file, :size => '30G'
      end
      config.vm.provider :virtualbox do |vb, override|
        storage_disk_filename = "#{name}_sdb.vmdk"
        override.trigger.before :up do
          unless File.exist? storage_disk_filename
            info "Creating the #{name} #{storage_disk_filename} storage disk..."
            run "VBoxManage createhd --filename #{storage_disk_filename} --size #{30*1024}"
          end
        end
        vb.customize ['storageattach', :id, '--storagectl', 'SATA Controller', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', storage_disk_filename]
      end
      config.vm.provision :shell,
        path: 'provision.sh',
        args: [
          service_ip,
          cluster_network_first_node_ip,
          cluster_network,
          cluster_ip,
          storage_ip
        ]
      config.vm.provision :reload
      config.vm.provision :shell, path: 'provision-pveproxy-certificate.sh', args: service_ip
      config.vm.provision :shell, path: 'provision-storage.sh', args: [
          storage_network_first_node_ip,
          storage_network,
          storage_ip,
          storage_monitor_ips
        ]
      config.vm.provision :shell, path: 'summary.sh', args: service_ip
    end
  end
end
