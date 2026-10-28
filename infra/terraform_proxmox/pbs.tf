resource "proxmox_virtual_environment_container" "pbs" {
  description  = "PBS community-script LXC target"
  node_name    = "pve-00"
  vm_id        = 4020
  unprivileged = false
  started      = true
  lifecycle {
    ignore_changes = [features, initialization[0].user_account]
  }

  initialization {
    hostname = "pbs"
    ip_config {
      ipv4 {
        address = "10.0.40.20/24"
        gateway = "10.0.40.1"
      }
    }
    user_account {
      keys = [trimspace(file(pathexpand("~/.ssh/id_proxmox.pub")))]
    }
  }
  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }
  disk {
    datastore_id = "local-nvme"
    size         = 32
  }
  operating_system {
    template_file_id = proxmox_download_file.debian_template.id
    type             = "debian"
  }
  cpu {
    cores = 4
  }
  memory {
    dedicated = 8192
  }
}
