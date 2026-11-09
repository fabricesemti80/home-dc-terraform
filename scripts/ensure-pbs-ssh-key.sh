#!/usr/bin/env bash
set -euo pipefail
# Make the dedicated PBS key the only key accepted for root in LXC 4020.
# The key (id_proxmox_pbs_0) is declared once, as a public key, in nix-hosts
# (users/fs.nix, sshKeysByHost.pbs); Home Manager writes it to ~/.ssh/id_proxmox_pbs_0.pub
# and its private half lives in the 1Password SSH agent.
#
# Runs through pve-00 with `pct` (root SSH to the host, key id_pve_00 from the agent), so it
# works even when no key is installed in the container and can never lock you out of it.
# Idempotent: rewrites /root/.ssh/authorized_keys with exactly this one key.
#
# Usage: ensure-pbs-ssh-key.sh [public-key-file]   (default ~/.ssh/id_proxmox_pbs_0.pub)

host=pve-00
vmid=4020
key_file="${1:-$HOME/.ssh/id_proxmox_pbs_0.pub}"

[[ -r $key_file ]] || { echo "ERROR: cannot read $key_file" >&2; exit 1; }
key="$(head -n 1 "$key_file" | tr -d '\r')"
[[ $key == "ssh-ed25519 "* ]] || { echo "ERROR: $key_file is not a single ssh-ed25519 public key" >&2; exit 1; }

printf '%s\n' "$key" |
  ssh "$host" "pct exec $vmid -- sh -c 'umask 077 && mkdir -p /root/.ssh && cat > /root/.ssh/authorized_keys.new && mv /root/.ssh/authorized_keys.new /root/.ssh/authorized_keys'"
