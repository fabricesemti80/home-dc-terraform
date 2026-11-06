#!/usr/bin/env bash
# Convert the cloud-init Debian bootstrap of Trinity (VMID 4050) to NixOS.
# Refuses unless the target is provably the fresh, not-yet-installed Trinity VM.
# `--auto` (used by `task proxmox:apply`): skip quietly when Trinity does not exist
# or already runs NixOS; still fail on any identity mismatch.
set -euo pipefail
auto=0; [[ ${1:-} == --auto ]] && auto=1

repo_root=$(cd "$(dirname "$0")/.." && pwd)
nix_hosts=$(cd "$repo_root/../nix-hosts" && pwd)
host=10.0.40.50
key=$HOME/.ssh/id_proxmox
ssh_opts=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

config=$(ssh -o BatchMode=yes pve-00 'qm config 4050' 2>/dev/null) || {
  if (( auto )); then echo 'Trinity VM 4050 not present; skipping NixOS install.'; exit 0; fi
  echo 'VMID 4050 not found on pve-00; run task proxmox:trinity-deploy first.' >&2; exit 1; }
[[ $config == *'name: trinity'* && $config == *'size=80G'* ]] || {
  echo 'VM 4050 is not the expected Trinity (name trinity, 80 GiB disk); refusing.' >&2; exit 1; }
mac=$(sed -n 's/^net0: virtio=\([^,]*\),.*/\1/p' <<<"$config" | tr '[:upper:]' '[:lower:]')
[[ -n $mac ]] || { echo 'Cannot read Trinity MAC from Proxmox.' >&2; exit 1; }

# Fail fast if Trinity is already installed (reachable as fs on NixOS).
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "fs@$host" 'test -e /etc/NIXOS' 2>/dev/null; then
  if (( auto )); then echo 'Trinity already runs NixOS; nothing to install.'; exit 0; fi
  echo 'Trinity already runs NixOS; refusing to reinstall. Use task proxmox:trinity-configure.' >&2
  exit 1
fi

echo "Waiting for bootstrap SSH on debian@$host (cloud-init, up to 5 minutes)..."
for _ in $(seq 60); do
  ssh "${ssh_opts[@]}" "debian@$host" true 2>/dev/null && break
  sleep 5
done
ssh "${ssh_opts[@]}" "debian@$host" true || {
  echo "debian@$host is unreachable; check VM 4050 console and cloud-init settings." >&2; exit 1; }
ssh "${ssh_opts[@]}" "debian@$host" 'sudo cloud-init status --wait >/dev/null 2>&1 || true'

# Target identity and state: Debian bootstrap, never an installed NixOS, Trinity's NIC.
guest_macs=$(ssh "${ssh_opts[@]}" "debian@$host" 'cat /sys/class/net/*/address')
if ssh "${ssh_opts[@]}" "debian@$host" 'test -e /etc/NIXOS'; then
  echo 'Trinity already runs NixOS; refusing to reinstall. Use task proxmox:trinity-configure.' >&2
  exit 1
fi
grep -qx "$mac" <<<"$guest_macs" || {
  echo "SSH target at $host is not Trinity (MAC $mac not found); refusing." >&2; exit 1; }
ssh "${ssh_opts[@]}" "debian@$host" 'test "$(lsblk -bdno SIZE /dev/sda)" = 85899345920' || {
  echo 'Target /dev/sda is not the expected 80 GiB disk; refusing.' >&2; exit 1; }

echo "Verified Trinity bootstrap (VM 4050, MAC $mac, /dev/sda 80 GiB). Installing NixOS..."
cd "$nix_hosts"
nix run github:nix-community/nixos-anywhere -- \
  --flake path:.#trinity --build-on remote --copy-host-keys \
  -i "$key" --ssh-option IdentitiesOnly=yes "debian@$host"

# The host key identity changes with the install; drop any stale entry.
ssh-keygen -R "$host" >/dev/null 2>&1 || true
echo "Trinity installed. Connect with: task proxmox:trinity-ssh"
