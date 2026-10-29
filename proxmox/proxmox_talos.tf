resource "proxmox_hardware_mapping_pci" "p2000_gpu" {
  name = "p2000-gpu"
  map = [{
    node         = "pve-00"
    path         = "0000:5b:00.0"
    id           = "10de:1c30"
    subsystem_id = "1028:11b3"
    iommu_group  = 2
  }]
}

resource "proxmox_hardware_mapping_pci" "p2000_audio" {
  name = "p2000-audio"
  map = [{
    node         = "pve-00"
    path         = "0000:5b:00.1"
    id           = "10de:10f1"
    subsystem_id = "1028:11b3"
    iommu_group  = 2
  }]
}

module "talos" {
  source = "./modules/talos"

  nodes             = var.nodes
  talos_version     = var.talos_version
  talos_image_type  = var.talos_image_type
  gateway           = var.gateway
  dns_servers       = var.dns_servers
  gpu_mapping       = proxmox_hardware_mapping_pci.p2000_gpu.name
  gpu_audio_mapping = proxmox_hardware_mapping_pci.p2000_audio.name
}
