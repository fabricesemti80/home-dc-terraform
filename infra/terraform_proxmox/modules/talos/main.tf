terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116"
    }
  }
}

resource "proxmox_download_file" "talos_iso" {
  for_each = {
    for combo in flatten([
      for node in var.nodes : [
        for schematic in [node.schematic_id] : {
          schematic_id = schematic
          proxmox_node = node.proxmox_node
        }
      ]
    ]) : "${combo.proxmox_node}-${combo.schematic_id}" => combo...
  }

  content_type = "iso"
  datastore_id = "nfs-proxmox-iso"
  node_name    = each.value[0].proxmox_node
  url          = "https://factory.talos.dev/image/${each.value[0].schematic_id}/${var.talos_version}/${var.talos_image_type}-amd64.iso"
  file_name    = "talos-${each.value[0].schematic_id}.img"
  overwrite    = false
}
moved {
  from = proxmox_virtual_environment_vm.talos_node["k8s-wrkr-02-gpu"]
  to   = proxmox_virtual_environment_vm.talos_node["k8s-wrkr-02"]
}
moved {
  from = proxmox_virtual_environment_vm.talos_node["k8s-wrkr-01"]
  to   = proxmox_virtual_environment_vm.talos_node["k8s-wrkr-01-gpu"]
}

resource "proxmox_virtual_environment_vm" "talos_node" {
  for_each = { for node in var.nodes : node.name => node }

  name        = each.value.name
  description = "Talos ${each.value.controller ? "Control Plane" : "Worker"} Node"
  node_name   = each.value.proxmox_node
  vm_id       = each.value.vm_id
  machine     = each.value.gpu_passthrough ? "q35" : null
  on_boot     = coalesce(try(each.value.on_boot, null), each.value.controller)
  started     = try(each.value.started, true)

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }
  memory {
    dedicated = each.value.memory_mb
  }
  disk {
    datastore_id = each.value.storage_pool
    interface    = "scsi0"
    size         = each.value.disk_size_gb
  }
  cdrom {
    file_id   = proxmox_download_file.talos_iso["${each.value.proxmox_node}-${each.value.schematic_id}"].id
    interface = "ide3"
  }
  network_device {
    bridge      = "vmbr0"
    mac_address = each.value.mac_address != "" ? each.value.mac_address : null
    mtu         = each.value.mtu
  }
  network_device {
    bridge      = "vmbr0"
    vlan_id     = 70
    mac_address = each.value.mac_address_secondary != "" ? each.value.mac_address_secondary : null
    mtu         = each.value.mtu
  }
  dynamic "hostpci" {
    for_each = each.value.gpu_passthrough ? [1] : []
    content {
      device  = "hostpci0"
      mapping = var.gpu_mapping
      pcie    = true
    }
  }

  dynamic "hostpci" {
    for_each = each.value.gpu_passthrough ? [1] : []
    content {
      device  = "hostpci1"
      mapping = var.gpu_audio_mapping
      pcie    = true
    }
  }
  boot_order = ["ide3", "scsi0"]
  agent {
    enabled = false
  }

  initialization {
    datastore_id = "nfs-proxmox-iso"
    ip_config {
      ipv4 {
        address = "${each.value.address}/${each.value.subnet_mask}"
        gateway = var.gateway
      }
    }
    ip_config {
      ipv4 {
        address = "10.0.70.${split(".", each.value.address)[3]}/24"
      }
    }
    dns {
      servers = var.dns_servers
    }
    user_account {
      username = "talos"
      password = "disabled"
    }
  }

  lifecycle {
    ignore_changes = [disk[0].file_id]
  }
}
