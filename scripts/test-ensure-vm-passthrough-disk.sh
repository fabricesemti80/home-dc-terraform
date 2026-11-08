#!/usr/bin/env bash
# Local test of the config guards in ensure-vm-passthrough-disk.sh using synthetic
# /etc/pve-style qemu-server configs. Touches nothing but a temp dir.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$here/ensure-vm-passthrough-disk.sh
# shellcheck disable=SC1090
source <(awk '/^# BEGIN config guards/{f=1} f{print} /^# END config guards/{f=0}' "$src" | sed '/^check_config_guards$/d')

byid=ata-TEST_SERIAL1 vmid=4096 slot=scsi2
dev=/dev/disk/by-id/$byid
aliases=("$dev" /dev/sdz)
fail=0
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT

# run <name> <expect: ok|refuse|noop> ; configs are written by the caller into $PVE_ROOT/qemu-server
run() {
  local name=$1 expect=$2 out rc got
  out=$( (check_config_guards; rc=$?; echo "current=[$current]"; exit $rc) 2>&1 ); rc=$?
  if (( rc != 0 )); then got=refuse; elif [[ $out == *"current=[scsi2:"* ]]; then got=noop; else got=ok; fi
  if [[ $got == "$expect" ]]; then echo "PASS $name ($got)"; else echo "FAIL $name: expected $expect got $got: $out"; fail=1; fi
}
fresh() { PVE_ROOT=$D/$1; export PVE_ROOT; rm -rf "$PVE_ROOT"; mkdir -p "$PVE_ROOT/qemu-server" "$PVE_ROOT/lxc"; printf 'name: target\nscsi0: local-hdd:vm-4096-disk-0,size=55G\nscsi1: local-hdd:vm-4096-disk-1,size=100G\n' > "$PVE_ROOT/qemu-server/4096.conf"; }

fresh clean;               run "clean config" ok
fresh cur_other; printf 'name: o\nscsi2: %s,backup=0\n' "$dev" > "$PVE_ROOT/qemu-server/4097.conf"; run "disk in OTHER VM current section" refuse
fresh pend_other; printf 'name: o\nscsi0: x:y\n\n[PENDING]\nscsi2: %s,backup=0\n' "$dev" > "$PVE_ROOT/qemu-server/4097.conf"; run "disk in OTHER VM pending-only" refuse
fresh pend_other_alias; printf 'name: o\n\n[PENDING]\nscsi5: /dev/sdz\n' > "$PVE_ROOT/qemu-server/4097.conf"; run "other VM pending-only via sdX alias" refuse
fresh snap_only; printf 'name: o\n\n[snap1]\nscsi2: %s,backup=0\n' "$dev" > "$PVE_ROOT/qemu-server/4097.conf"; run "disk only in OTHER VM snapshot (ignored)" ok
fresh pend_slot; printf 'name: target\nscsi0: a:b\n\n[PENDING]\nscsi2: /dev/disk/by-id/ata-OTHER_DISK,backup=0\n' > "$PVE_ROOT/qemu-server/4096.conf"; run "slot scsi2 pending with a different disk" refuse
fresh cur_slot; printf 'name: target\nscsi2: local-hdd:vm-4096-disk-2,size=1G\n' > "$PVE_ROOT/qemu-server/4096.conf"; run "slot scsi2 current with another volume" refuse
fresh snap_slot; printf 'name: target\nscsi0: a:b\n\n[snap1]\nscsi2: local-hdd:vm-4096-disk-2,size=1G\n' > "$PVE_ROOT/qemu-server/4096.conf"; run "slot scsi2 only in own snapshot (ignored)" ok
fresh pend_del; printf 'name: target\nscsi2: %s\n\n[PENDING]\ndelete: scsi2\n' "$dev" > "$PVE_ROOT/qemu-server/4096.conf"; run "pending delete of scsi2" refuse
fresh same_cur; printf 'name: target\nscsi2: %s,backup=0,serial=SERIAL1\n' "$dev" > "$PVE_ROOT/qemu-server/4096.conf"; run "same VM same slot current (idempotent)" noop
fresh same_pend; printf 'name: target\nscsi0: a:b\n\n[PENDING]\nscsi2: %s,backup=0,serial=SERIAL1\n' "$dev" > "$PVE_ROOT/qemu-server/4096.conf"; run "same VM same slot pending (idempotent)" noop
fresh same_vm_other_slot; printf 'name: target\nscsi4: %s\n' "$dev" > "$PVE_ROOT/qemu-server/4096.conf"; run "same VM disk on a different slot" refuse
fresh lxc; printf 'mp0: %s,mp=/x\n\n[PENDING]\nmp1: x\n' "$dev" > "$PVE_ROOT/lxc/100.conf"; run "disk referenced by an LXC" refuse
exit $fail
