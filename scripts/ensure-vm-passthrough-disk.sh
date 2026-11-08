#!/usr/bin/env bash
# Attach one whole host SSD to a VM as raw passthrough (qm set --scsiN /dev/disk/by-id/...).
#
# Why this is a script and not a provider `disk` block: Proxmox only lets root@pam
# (a real root session, not an API token, not even a token of root@pam) assign
# host block devices to a VM. This root authenticates with an API token, so the
# attachment is done over root SSH to the Proxmox host, like ensure-lxc-nesting.sh.
#
# usage: ensure-vm-passthrough-disk.sh <ssh-host> <vmid> <scsiN> <by-id-name>
#   DRY_RUN=1   run every guard and print the qm command, but never run it.
#
# Behaviour (idempotent, never destructive):
#   - already attached to this VM on this slot            -> no-op, exit 0
#   - slot used by anything else / disk used by another VM -> refuse, exit 1
#   - disk (or a partition) mounted, swap-active, in a ZFS pool, an LVM PV, or
#     held open by a device-mapper / md device             -> refuse, exit 1
#   - otherwise `qm set` adds the disk. It never wipes, formats or detaches
#     anything. Old signatures on the SSD are cleared (guarded) by the
#     home-dc-proxmox Ansible role, not here.
#   - a running VM may keep the new disk as a *pending* change until it is
#     stopped and started (not rebooted from inside the guest); the script
#     reports this and does not restart anything.
set -euo pipefail

if [[ $# -ne 4 ]]; then
  printf 'usage: %s <ssh-host> <vmid> <scsiN> <by-id-name>\n' "$0" >&2
  exit 2
fi
host=$1 vmid=$2 slot=$3 byid=$4

[[ $host =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'invalid ssh host: %s\n' "$host" >&2; exit 2; }
[[ $vmid =~ ^[0-9]{3,9}$ ]] || { printf 'invalid vmid: %s\n' "$vmid" >&2; exit 2; }
# scsi0/scsi1 belong to the system and data disks; never touch them.
[[ $slot =~ ^scsi([2-9]|[12][0-9]|30)$ ]] || { printf 'slot must be scsi2..scsi30: %s\n' "$slot" >&2; exit 2; }
[[ $byid =~ ^[A-Za-z0-9][A-Za-z0-9._:+-]*$ ]] || { printf 'invalid by-id name: %s\n' "$byid" >&2; exit 2; }
[[ $byid =~ -part[0-9]+$ ]] && { printf 'refusing a partition, pass the whole disk: %s\n' "$byid" >&2; exit 2; }

# The guest serial is the drive serial (last "_"-separated token of the by-id name),
# so Talos can identify the disk reliably regardless of size or enumeration order.
serial=${byid##*_}
serial=${serial//[^A-Za-z0-9._-]/}
serial=${serial:0:20}

remote=$(cat <<'REMOTE'
set -euo pipefail
vmid=$1 slot=$2 byid=$3 serial=$4 dry=$5
dev=/dev/disk/by-id/$byid

[[ -b $dev ]] || { echo "ERROR: $dev is not a block device on this host" >&2; exit 1; }
real=$(readlink -f "$dev")
[[ $(lsblk -dno TYPE "$real") == disk ]] || { echo "ERROR: $real is not a whole disk" >&2; exit 1; }
[[ -f /etc/pve/qemu-server/$vmid.conf ]] || { echo "ERROR: VM $vmid does not exist on this host" >&2; exit 1; }

# Every path that may name this disk: by-id link, resolved node, and all other by-id aliases.
aliases=("$dev" "$real")
for l in /dev/disk/by-id/*; do
  [[ $(readlink -f "$l") == "$real" ]] && aliases+=("$l")
done

# Guard 1: nothing on the disk may be in use.
if [[ -n $(lsblk -nro MOUNTPOINTS "$real" | tr -d '[:space:]') ]]; then
  echo "ERROR: $real (or a partition) is mounted" >&2; exit 1
fi
if swapon --noheadings --show=NAME 2>/dev/null | grep -q "^${real}"; then
  echo "ERROR: swap is active on $real" >&2; exit 1
fi
if [[ -n $(lsblk -nro TYPE "$real" | grep -vxE 'disk|part' || true) ]]; then
  echo "ERROR: device-mapper/md/other device stacked on $real" >&2; exit 1
fi
if command -v zpool >/dev/null && zpool status -LP 2>/dev/null | grep -qE "${real}(p?[0-9]+)?([[:space:]]|$)"; then
  echo "ERROR: $real is part of a ZFS pool" >&2; exit 1
fi
if command -v pvs >/dev/null && pvs --noheadings -o pv_name 2>/dev/null | grep -qE "${real}(p?[0-9]+)?[[:space:]]*$"; then
  echo "ERROR: $real is an LVM physical volume" >&2; exit 1
fi

# Guard 2: referenced by any VM or container config?
current=
for conf in /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf /etc/pve/nodes/*/qemu-server/*.conf /etc/pve/nodes/*/lxc/*.conf; do
  [[ -f $conf ]] || continue
  id=$(basename "$conf" .conf)
  # Only the active section of the config (snapshot and [PENDING] sections follow a "[name]" header).
  active=$(awk '/^\[/{exit} {print}' "$conf")
  for a in "${aliases[@]}"; do
    hit=$(printf '%s\n' "$active" | grep -E "^[a-z]+[0-9]*: ${a}(,|$)" || true)
    [[ -n $hit ]] || continue
    if [[ $id == "$vmid" && $hit == "$slot:"* ]]; then
      current=$hit
    else
      echo "ERROR: $byid is already referenced by $conf ($hit)" >&2; exit 1
    fi
  done
done

if [[ -n $current ]]; then
  echo "OK: $byid already attached to VM $vmid as $slot ($current); nothing to do."
  qm pending "$vmid" 2>/dev/null | grep -E "^(new|del)[[:space:]]+: ?${slot}" >/dev/null \
    && echo "NOTE: $slot has a pending change; stop and start VM $vmid to apply it." || true
  exit 0
fi

# Guard 3: the slot must be free in the active config and in pending changes.
if awk '/^\[/{exit} {print}' "/etc/pve/qemu-server/$vmid.conf" | grep -qE "^${slot}:"; then
  echo "ERROR: VM $vmid slot $slot is already used by something else:" >&2
  awk '/^\[/{exit} {print}' "/etc/pve/qemu-server/$vmid.conf" | grep -E "^${slot}:" >&2
  exit 1
fi

opts="$dev,backup=0,discard=on,ssd=1,serial=$serial"
if [[ $dry == 1 ]]; then
  echo "DRY RUN: would run: qm set $vmid --$slot $opts"
  exit 0
fi
echo "Attaching $byid to VM $vmid as $slot (raw passthrough, excluded from backups)."
qm set "$vmid" "--$slot" "$opts"
status=$(qm status "$vmid" | awk '{print $2}')
if [[ $status == running ]]; then
  if qm pending "$vmid" 2>/dev/null | grep -qE "^new[[:space:]]+: ?${slot}"; then
    echo "NOTE: VM $vmid is running and $slot is PENDING. Schedule a maintenance stop/start (not a guest reboot) to attach it."
  else
    echo "NOTE: VM $vmid is running; $slot was hot-plugged. Verify in the guest; a stop/start is still advised before relying on it."
  fi
fi
REMOTE
)

ssh -o BatchMode=yes "$host" bash -s -- "$vmid" "$slot" "$byid" "$serial" "${DRY_RUN:-0}" <<<"$remote"
