# to make sure the pve1 node is created before the other nodes, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

# to be able to configure hyper-v vm and add extra disks.
ENV['VAGRANT_EXPERIMENTAL'] = 'typed_triggers,disks'

number_of_nodes = 3
service_network_first_node_ip = '10.0.1.201'
cluster_network_first_node_ip = '10.0.2.201'; cluster_network='10.0.2.0'
storage_network_first_node_ip = '10.0.3.201'; storage_network='10.0.3.0'
gateway_ip = '10.0.1.254'
upstream_dns_server = '8.8.8.8'

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
  config.vm.provider :libvirt do |lv, config|
    lv.memory = 3*1024
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs', nfs_version: '4.2', nfs_udp: false
  end

  config.vm.provider :virtualbox do |vb|
    vb.linked_clone = true
    vb.memory = 3*1024
    vb.cpus = 4
    vb.customize ['modifyvm', :id, '--nested-hw-virt', 'on']
    vb.customize ['modifyvm', :id, '--nicpromisc2', 'allow-all']
  end

  config.vm.provider :hyperv do |hv, config|
    hv.linked_clone = true
    hv.enable_virtualization_extensions = true # nested virtualization.
    hv.memory = 3*1024
    hv.cpus = 4
    hv.vlan_id = ENV['HYPERV_VLAN_ID']
    # set the management network adapter.
    # see https://github.com/hashicorp/vagrant/issues/7915
    # see https://github.com/hashicorp/vagrant/blob/10faa599e7c10541f8b7acf2f8a23727d4d44b6e/plugins/providers/hyperv/action/configure.rb#L21-L35
    config.vm.network :private_network,
      bridge: ENV['HYPERV_SWITCH_NAME'] if ENV['HYPERV_SWITCH_NAME']
    config.vm.synced_folder '.', '/vagrant',
      type: 'smb',
      smb_username: ENV['VAGRANT_SMB_USERNAME'] || ENV['USER'],
      smb_password: ENV['VAGRANT_SMB_PASSWORD']
    # further configure the VM (e.g. manage the network adapters).
    config.trigger.before :'VagrantPlugins::HyperV::Action::StartInstance', type: :action do |trigger|
      trigger.ruby do |env, machine|
        # see https://github.com/hashicorp/vagrant/blob/v2.2.10/lib/vagrant/machine.rb#L13
        # see https://github.com/hashicorp/vagrant/blob/v2.2.10/plugins/kernel_v2/config/vm.rb#L716
        bridges = machine.config.vm.networks.select{|type, options| type == :private_network && options.key?(:hyperv__bridge)}.map do |type, options|
          mac_address_spoofing = false
          mac_address_spoofing = options[:hyperv__mac_address_spoofing] if options.key?(:hyperv__mac_address_spoofing)
          [options[:hyperv__bridge], mac_address_spoofing]
        end
        system(
          'PowerShell',
          '-NoLogo',
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'configure-hyperv.ps1',
          machine.id,
          bridges.to_json
        )
      end
    end
  end

  config.vm.define 'gateway' do |config|
    config.vm.box = 'ubuntu-20.04-amd64'
    config.vm.provider :libvirt do |lv|
      lv.memory = 512
    end
    config.vm.provider :virtualbox do |vb|
      vb.memory = 512
    end
    config.vm.provider :hyperv do |hv, override|
      hv.memory = 1024
    end
    config.vm.hostname = 'gateway.example.com'
    config.vm.network :private_network,
      ip: gateway_ip,
      libvirt__forward_mode: 'none',
      libvirt__dhcp_enabled: false,
      hyperv__bridge: 'proxmox-service'
    config.vm.provision :shell,
      path: 'configure-hyperv.sh',
      args: [
        gateway_ip
      ],
      run: 'always'
    certificate_ip_addr = service_ip_addr.clone
    (1..number_of_nodes).each do |n|
      certificate_ip = certificate_ip_addr.to_s; certificate_ip_addr = certificate_ip_addr.succ
      config.vm.provision :shell, path: 'provision-certificate.sh', args: ["pve#{n}.example.com", certificate_ip]
    end
    config.vm.provision :shell, path: 'provision-certificate.sh', args: ['example.com', gateway_ip]
    config.vm.provision :shell, path: 'provision-gateway.sh', args: [gateway_ip, upstream_dns_server]
    config.vm.provision :shell, path: 'provision-postfix.sh'
    config.vm.provision :shell, path: 'provision-dovecot.sh'
  end

  (1..number_of_nodes).each do |n|
    name = "pve#{n}"
    fqdn = "#{name}.example.com"
    service_ip = service_ip_addr.to_s; service_ip_addr = service_ip_addr.succ
    cluster_ip = cluster_ip_addr.to_s; cluster_ip_addr = cluster_ip_addr.succ
    storage_ip = storage_ip_addr.to_s; storage_ip_addr = storage_ip_addr.succ
    config.vm.define name do |config|
      config.vm.hostname = fqdn
      config.vm.provider :libvirt do |lv|
        lv.storage :file, :size => '30G'
      end
      config.vm.provider :virtualbox do |vb, override|
        override.vm.disk :disk, size: '30GB', name: 'data'
      end
      config.vm.provider :hyperv do |hv, override|
        override.vm.disk :disk, size: '30GB', name: 'data'
      end
      config.vm.network :private_network,
        ip: service_ip,
        auto_config: false,
        libvirt__forward_mode: 'none',
        libvirt__dhcp_enabled: false,
        hyperv__bridge: 'proxmox-service',
        hyperv__mac_address_spoofing: true
      config.vm.network :private_network,
        ip: cluster_ip,
        auto_config: false,
        libvirt__forward_mode: 'none',
        libvirt__dhcp_enabled: false,
        hyperv__bridge: 'proxmox-cluster'
      config.vm.network :private_network,
        ip: storage_ip,
        auto_config: false,
        libvirt__forward_mode: 'none',
        libvirt__dhcp_enabled: false,
        hyperv__bridge: 'proxmox-storage'
      config.vm.provision :shell,
        path: 'provision.sh',
        args: [
          n,
          service_ip,
          cluster_network_first_node_ip,
          cluster_network,
          cluster_ip,
          storage_ip,
          gateway_ip
        ]
      config.vm.provision :reload
      config.vm.provision :shell, path: 'provision-pveproxy-certificate.sh', args: service_ip
      config.vm.provision :shell, path: 'provision-storage.sh', args: [
          storage_network_first_node_ip,
          storage_network,
          storage_ip,
          storage_monitor_ips
        ]
      config.vm.provision :shell, path: 'provision-alpine-template-container.sh', args: [service_ip, gateway_ip]
      config.vm.provision :shell, path: 'provision-debian-live-virtual-machine.sh', args: gateway_ip
      config.vm.provision :shell, path: 'summary.sh', args: service_ip
    end
  end
end
