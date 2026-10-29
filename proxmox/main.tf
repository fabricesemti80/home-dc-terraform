provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = true
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
}
