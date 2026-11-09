#!/usr/bin/env bash
set -euo pipefail
# Install the PBS setup script into LXC 4020 and run it, going through the Proxmox
# host (root SSH to pve-00, key id_pve_00 from the 1Password agent, see ~/.ssh config)
# with `pct`. The container itself needs no SSH key and no SSH access.
# The passwords travel over stdin only, never on a command line.
#
# Required environment: PBS_ADMIN_PASSWORD, PBS_BACKUP_PASSWORD.

: "${PBS_ADMIN_PASSWORD:?set PBS_ADMIN_PASSWORD}"
: "${PBS_BACKUP_PASSWORD:?set PBS_BACKUP_PASSWORD}"

host=pve-00
vmid=4020
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/configure-pbs.sh"

ssh "$host" "pct exec $vmid -- tee /root/configure-pbs.sh > /dev/null" < "$script"

printf '%s\n%s\n' "$PBS_ADMIN_PASSWORD" "$PBS_BACKUP_PASSWORD" |
  ssh "$host" "pct exec $vmid -- bash -c 'IFS= read -r a; IFS= read -r b; PBS_ADMIN_PASSWORD=\$a PBS_BACKUP_PASSWORD=\$b bash /root/configure-pbs.sh'"
