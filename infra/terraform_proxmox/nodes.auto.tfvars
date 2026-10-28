nodes = [
  {
    name         = "k8s-ctrl-01"
    address      = "10.0.40.90"
    controller   = true
    started      = true
    mac_address  = "bc:24:11:79:b5:8f"
    schematic_id = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
    cpu_cores    = 10
    memory_mb    = 16384
    disk_size_gb = 55
    mtu          = 1500
    subnet_mask  = 24
    vm_id        = 4090
    proxmox_node = "pve-00"
    storage_pool = "local-nvme"
  },
  {
    name              = "k8s-wrkr-01-gpu"
    address           = "10.0.40.95"
    controller        = false
    started           = true
    gpu_passthrough   = true
    mac_address       = "bc:24:11:40:00:95"
    schematic_id      = "af8eb82417d3deaa94d2ef19c3b590b0dac1b2549d0b9b35b3da2bc325de75f7"
    cpu_cores         = 4
    memory_mb         = 10240
    disk_size_gb      = 55
    data_disk_size_gb = 100
    mtu               = 1500
    subnet_mask       = 24
    vm_id             = 4095
    proxmox_node      = "pve-00"
    storage_pool      = "local-hdd"
  },
  {
    name              = "k8s-wrkr-02"
    address           = "10.0.40.96"
    controller        = false
    started           = true
    mac_address       = "bc:24:11:40:00:96"
    schematic_id      = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
    cpu_cores         = 4
    memory_mb         = 10240
    disk_size_gb      = 55
    data_disk_size_gb = 100
    mtu               = 1500
    subnet_mask       = 24
    vm_id             = 4096
    proxmox_node      = "pve-00"
    storage_pool      = "local-hdd"
  },
  {
    name              = "k8s-wrkr-03"
    address           = "10.0.40.97"
    controller        = false
    started           = true
    mac_address       = "bc:24:11:40:00:97"
    schematic_id      = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
    cpu_cores         = 4
    memory_mb         = 10240
    disk_size_gb      = 55
    data_disk_size_gb = 100
    mtu               = 1500
    subnet_mask       = 24
    vm_id             = 4097
    proxmox_node      = "pve-00"
    storage_pool      = "local-hdd"
  }
]
