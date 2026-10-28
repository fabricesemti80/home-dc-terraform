#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
  export OP_SERVICE_ACCOUNT_TOKEN="$(security find-generic-password -a "$USER" -s home-dc-proxmox-op -w)"
fi
export OP_BIOMETRIC_UNLOCK_ENABLED=false
export TF_VAR_proxmox_token_id="$(op read 'op://iac/pve-00-terraform-api-token/username')"
export TF_VAR_proxmox_token_secret="$(op read 'op://iac/pve-00-terraform-api-token/credential')"
exec tofu "$@"
