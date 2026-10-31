provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = true
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
}

# Authenticates with DOPPLER_TOKEN from the environment (see scripts/tofu.sh).
provider "doppler" {}
