resource "proxmox_virtual_environment_container" "pbs" {
  description  = "PBS LXC (Community Scripts installation)"
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

resource "random_password" "pbs_admin" {
  length  = 24
  special = false
}

resource "random_password" "pbs_backup" {
  length  = 24
  special = false
}

# Installs and configures PBS inside the LXC (NFS datastore, users, ACLs).
# configure-pbs.sh is idempotent; this re-runs when it or the container changes.
resource "terraform_data" "pbs_setup" {
  triggers_replace = [
    proxmox_virtual_environment_container.pbs.id,
    filesha256("${path.module}/../scripts/configure-pbs.sh"),
  ]

  # Features (mount=nfs) need root on pve-00; the API token cannot set them.
  provisioner "local-exec" {
    command = "bash '${path.module}/../scripts/ensure-lxc-nesting.sh' 4020 mount=nfs"
  }

  connection {
    type        = "ssh"
    host        = "10.0.40.20"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_proxmox"))
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${path.module}/../scripts/configure-pbs.sh"
    destination = "/root/configure-pbs.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "PBS_ADMIN_PASSWORD='${random_password.pbs_admin.result}' PBS_BACKUP_PASSWORD='${random_password.pbs_backup.result}' bash /root/configure-pbs.sh",
    ]
  }
}

output "pbs_admin_password" {
  description = "Password for pbs-admin@pbs (web UI https://10.0.40.20:8007)"
  value       = random_password.pbs_admin.result
  sensitive   = true
}

output "pbs_backup_password" {
  description = "Password for pve-backup@pbs (use when adding PBS storage in PVE)"
  value       = random_password.pbs_backup.result
  sensitive   = true
}

resource "doppler_secret" "pbs_admin_password" {
  project = "home-dc-terraform"
  config  = "prd"
  name    = "PBS_ADMIN_PASSWORD"
  value   = random_password.pbs_admin.result
}

resource "doppler_secret" "pbs_backup_password" {
  project = "home-dc-terraform"
  config  = "prd"
  name    = "PBS_BACKUP_PASSWORD"
  value   = random_password.pbs_backup.result
}
