variable "nodes" {
  type = list(object({
    name                   = string
    address                = string
    controller             = bool
    gpu_passthrough        = optional(bool, false)
    started                = optional(bool)
    on_boot                = optional(bool)
    schematic_id           = string
    proxmox_node           = string
    vm_id                  = number
    cpu_cores              = number
    memory_mb              = number
    disk_size_gb           = number
    data_disk_size_gb      = optional(number, 100)
    data_disk_storage_pool = optional(string, "local-hdd")
    mac_address            = optional(string, "")
    mtu                    = optional(number, 1500)
    subnet_mask            = optional(number, 24)
    storage_pool           = optional(string, "local-nvme")
  }))
}

variable "talos_version" {
  type = string
}

variable "talos_image_type" {
  type = string
}

variable "gateway" {
  type = string
}

variable "dns_servers" {
  type = list(string)
}

variable "gpu_mapping" {
  type = string
}

variable "gpu_audio_mapping" {
  type = string
}
