# Trinity is created from a pinned Debian cloud image that cloud-init configures
# with a static address and the operator's SSH key. `task proxmox:trinity-install`
# then converts that bootstrap OS to NixOS with nixos-anywhere. Terraform owns only
# the VM hardware and bootstrap disk; the guest OS is owned by nix-hosts.
resource "proxmox_download_file" "trinity_debian_image" {
  content_type       = "import"
  datastore_id       = "nfs-proxmox-iso"
  node_name          = "pve-00"
  url                = "https://cloud.debian.org/images/cloud/trixie/20261103-2651/debian-13-generic-amd64-20261103-2651.qcow2"
  file_name          = "debian-13-generic-amd64-20261103-2651.qcow2"
  checksum           = "1207e6e3efaff8ee77ab7a32c156a3eea6a9e53f94cfc48efbd1f49ba554ca36ac62ab27395aa813a1775a8c0a393b1a1ce5377d9e5670f6113e3110c57fee4b"
  checksum_algorithm = "sha512"
}

resource "proxmox_virtual_environment_vm" "trinity" {
  name        = "trinity"
  description = "Headless NixOS services VM (bootstrapped from Debian cloud-init)"
  node_name   = "pve-00"
  vm_id       = 4050
  machine     = "q35"
  bios        = "ovmf"
  started     = true
  on_boot     = true

  cpu {
    cores = 4
    type  = "host"
  }
  memory {
    dedicated = 8192
  }
  disk {
    datastore_id = "local-nvme"
    interface    = "scsi0"
    import_from  = proxmox_download_file.trinity_debian_image.id
    size         = 80
    discard      = "on"
  }
  efi_disk {
    datastore_id = "local-nvme"
    type         = "4m"
  }
  initialization {
    datastore_id = "local-nvme"
    ip_config {
      ipv4 {
        address = "10.0.40.50/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
    user_account {
      username = "debian"
      keys     = [trimspace(file(pathexpand("~/.ssh/id_proxmox.pub")))]
    }
  }
  network_device {
    bridge = "vmbr0"
  }
  boot_order = ["scsi0"]
  agent {
    enabled = true
    # The Debian bootstrap image does not run the agent; cap provider waits so
    # apply/refresh never block for the default 15 minutes.
    timeout = "1m"
    wait_for_ip {
      disabled = true
    }
  }

  # After nixos-anywhere replaces the OS, a later apply must never touch the host.
  lifecycle {
    ignore_changes = [started, disk, initialization, efi_disk, boot_order]
  }
}
