nodes = [
  {
    name                  = "k8s-ctrl-01"
    address               = "10.0.40.90"
    controller            = true
    started               = true
    mac_address           = "bc:24:11:79:b5:8f"
    mac_address_secondary = "bc:24:11:ce:0c:fb"
    schematic_id          = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
    cpu_cores             = 10
    memory_mb             = 16384
    disk_size_gb          = 55
    mtu                   = 1500
    subnet_mask           = 24
    vm_id                 = 4090
    proxmox_node          = "pve-00"
    storage_pool          = "local-nvme"
  },
  {
    name                  = "k8s-wrkr-01-gpu"
    address               = "10.0.40.95"
    controller            = false
    started               = true
    gpu_passthrough       = true
    mac_address           = "bc:24:11:40:00:95"
    mac_address_secondary = "bc:24:11:70:00:95"
    schematic_id          = "26124abcbd408be693df9fe852c80ef1e6cc178e34d7d7d8430a28d1130b4227"
    cpu_cores             = 4
    memory_mb             = 10240
    disk_size_gb          = 55
    mtu                   = 1500
    subnet_mask           = 24
    vm_id                 = 4095
    proxmox_node          = "pve-00"
    storage_pool          = "local-hdd"
  },
  {
    name                  = "k8s-wrkr-02"
    address               = "10.0.40.96"
    controller            = false
    started               = true
    mac_address           = "bc:24:11:40:00:96"
    mac_address_secondary = "bc:24:11:70:00:96"
    schematic_id          = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
    cpu_cores             = 4
    memory_mb             = 10240
    disk_size_gb          = 55
    mtu                   = 1500
    subnet_mask           = 24
    vm_id                 = 4096
    proxmox_node          = "pve-00"
    storage_pool          = "local-hdd"
  },
  {
    name                  = "k8s-wrkr-03"
    address               = "10.0.40.97"
    controller            = false
    started               = true
    mac_address           = "bc:24:11:40:00:97"
    mac_address_secondary = "bc:24:11:70:00:97"
    schematic_id          = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
    cpu_cores             = 4
    memory_mb             = 10240
    disk_size_gb          = 55
    mtu                   = 1500
    subnet_mask           = 24
    vm_id                 = 4097
    proxmox_node          = "pve-00"
    storage_pool          = "local-hdd"
  }
]

