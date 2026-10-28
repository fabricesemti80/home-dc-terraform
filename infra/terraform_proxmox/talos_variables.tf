variable "proxmox_endpoint" {
  type    = string
  default = "https://10.0.40.10:8006"
}

variable "proxmox_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "nodes" {
  type = list(object({
    name                  = string
    address               = string
    controller            = bool
    gpu_passthrough       = optional(bool, false)
    started               = optional(bool)
    on_boot               = optional(bool)
    schematic_id          = string
    proxmox_node          = string
    vm_id                 = number
    cpu_cores             = number
    memory_mb             = number
    disk_size_gb          = number
    mac_address           = optional(string, "")
    mac_address_secondary = optional(string, "")
    mtu                   = optional(number, 1500)
    subnet_mask           = optional(number, 24)
    storage_pool          = optional(string, "local-nvme")
  }))
}

variable "gateway" {
  type    = string
  default = "10.0.40.1"
}

variable "talos_version" {
  type    = string
  default = "v1.12.0"
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "1.0.0.1"]
}

variable "talos_image_type" {
  type    = string
  default = "nocloud"
}
