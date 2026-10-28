resource "proxmox_download_file" "debian_template" {
  content_type       = "vztmpl"
  datastore_id       = "local"
  node_name          = "pve-00"
  url                = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
  file_name          = "debian-12-standard_12.12-1_amd64.tar.zst"
  checksum           = "50c85eaaece677a3ebe01cc909b83872e9da2a22c29ae652838afce71e83222fdf40f6accecd7d52b180e912fc1f85ecdf7b3fc4d3027da4d865e509a9e76597"
  checksum_algorithm = "sha512"
}

resource "proxmox_virtual_environment_container" "smoke" {
  description  = "Terraform provider smoke-test container"
  node_name    = "pve-00"
  vm_id        = 4019
  unprivileged = true
  started      = true
  lifecycle {
    ignore_changes = [features, initialization[0].user_account]
  }

  initialization {
    hostname = "terraform-smoke"
    ip_config {
      ipv4 {
        address = "10.0.40.19/24"
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
    size         = 4
  }
  operating_system {
    template_file_id = proxmox_download_file.debian_template.id
    type             = "debian"
  }
  cpu {
    cores = 1
  }
  memory {
    dedicated = 512
  }
}
