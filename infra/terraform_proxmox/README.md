# Proxmox/Talos infrastructure

This is a new, independent OpenTofu state for the standalone `pve-00` host. It does not import or edit the legacy Proxmox/Talos state in `../home-dc-kubernetes`; that deployment and its state stay in that repository. All resources defined here are new resources owned by this root.

`scripts/tofu.sh` reads the PVE API token from the `iac` 1Password vault item `pve-00-terraform-api-token`. No credentials are committed.

## Deployment tasks

```bash
task pbs-plan
task pbs-apply
task nodes-plan
task nodes-apply
```

- PBS: LXC 4020, `10.0.40.20/24`, untagged on `vmbr0`, `local-nvme`, 4 vCPU / 8 GiB. The PVE uplink's native/access network must be VLAN 40. `pbs-apply` creates and starts a Debian LXC target; it does not run the Community Scripts installer or install PBS.
- Talos VMs: `nodes-plan`/`nodes-apply` target `module.talos` and its Proxmox dependencies only. Controller 4090 is configured to start on `local-nvme`; workers 4095–4097 are configured to start on `local-hdd`. Boot ISOs are Talos `v1.13.8` (matching the Kubernetes repo's `talos/app/talenv.yaml`) and cloud-init images use `nfs-proxmox-iso`.
- Boot the installed `scsi0` disk **before** the attached Talos ISO (`ide3`). Assumption: on a fresh guest with an unbootable disk, SeaBIOS falls through to the ISO for initial installation. Once Talos installs, ISO-first boot halts the guest in installer mode; never restore that order for installed nodes. This is an in-place VM configuration update, not a disk replacement.

  **Validation:** Run `task nodes-plan`, inspect `tfplan-nodes` and require no VM replacement, disk, network or PCI changes. For the existing guests the reviewed plan showed 0 add, 4 in-place updates, 0 destroy: boot order only, plus the provider normalizing an empty `machine` field to `null` on VM 4096. If the operator changes VM 4096's boot order manually first, regenerate and inspect the plan before applying. Apply the exact reviewed plan with `task nodes-apply-reviewed` (not a fresh unreviewed plan). Verify `qm config <vmid>` shows `boot: order=scsi0;ide3` for 4090/4095/4096/4097, then reboot only halted VM 4096 and require all Kubernetes nodes `Ready`; schedule any other VM reboot separately.

  **Rollback:** If a fresh, uninstalled guest cannot fall through to the ISO, boot it from the ISO for installation and reapply disk-first order before its first reboot. Do not revert installed nodes to ISO-first or remove their disks; inspect the Proxmox console before recovery. Keep the ISO attached as a rescue option.

- Each Talos VM has a single NIC untagged on `vmbr0` in VLAN 40. GPU worker 4095 (`k8s-wrkr-01-gpu`) has P2000 GPU/audio passthrough; its Talos image uses the NVIDIA **580-series LTS** driver/toolkit schematic `af8eb82417d3deaa94d2ef19c3b590b0dac1b2549d0b9b35b3da2bc325de75f7` because production 595 does not support this GPU. Accept NVIDIA's driver EULA before use and verify driver/runtime support in the guest.
- Before applying a worker GPU passthrough handoff, shut down both donor and recipient VMs in Proxmox. Host-PCI changes can reboot running VMs, and the VM updates are independent; `started = true` may start them again during apply. This is an operator step, not automated.
- Talos tasks provision VMs only; they do not configure Talos or bootstrap Kubernetes. They do not mutate `home-dc-kubernetes` files or state.
- Each worker VM receives a dedicated second data disk (`scsi1`) on `local-hdd`, default 100 GiB, controlled per node by `data_disk_size_gb` and `data_disk_storage_pool`. Controllers have no data disk. The existing system disk (`scsi0`) is unchanged.
- Talos machine config in `home-dc-kubernetes` selects a non-system disk for a worker user volume, mounted at `/var/mnt/local-path-provisioner`. Confirm each VM has exactly one non-system disk before applying Talos; this Terraform root only provisions the guest disks.
- The PVE API token cannot change feature flags on privileged LXCs (HTTP 403). `ensure-lxc-nesting` uses root SSH and merges `nesting=1` into the existing feature list, preserving all other flags; it reboots a container only when nesting is absent. Terraform ignores feature-flag drift; the helper is part of `pbs-apply`, `smoke`, and full apply tasks.
- Smoke and PBS LXC SSH use the root key from `~/.ssh/id_proxmox.pub`; no password is configured. `initialization.user_account` applies only at container creation, so existing LXCs were seeded through `pct exec`. Key rotation on existing LXCs is a manual authorized-keys update.
- Staged tasks use `-target`, so OpenTofu warns that a partial plan may omit other stacks; use `task plan` to review remaining work. Successful applies print direct SSH commands and host-key fingerprints. The PBS web UI is available at `https://10.0.40.20:8007` after installing PBS.
- Talos guidance lists each configured IP and VMID, labels workers as configured started, and distinguishes insecure maintenance access from authenticated `talosctl` after config/bootstrap. This root creates no `talosconfig` or VIP.
- Smoke LXC 4019 runs Debian 12 at `10.0.40.19/24`, untagged on `vmbr0`. Its Proxmox standard LXC template is pinned by SHA-512.

`task plan-preview` creates a non-applying full-stack plan. `task plan` saves a full-stack plan; `task apply` presents a full plan and requires interactive confirmation. Full-stack local state, saved plans, and provider caches are ignored by Git.

## Capacity, backup, and validation

- Data-disk sizing assumes `local-hdd` has at least 300 GiB free for the three 100 GiB worker disks plus headroom for snapshots and Proxmox metadata. Confirm free space on `pve-00` before `nodes-apply`.
- Rollback before storing any workload data: restore the prior Terraform configuration and review a scoped plan. Once a worker data disk has PVC data, **never** remove it or its Terraform state to roll back without an independently verified off-host backup and restore.
- Validate a fresh plan before applying: it may add three `scsi1` disks, remove four obsolete VLAN 70 NICs and replace the GPU worker's Talos ISO reference with the 580-series LTS schematic. Stop on any VM replacement or `scsi0` resize/deletion.
- Removing the secondary NIC or changing the boot ISO may require a VM stop/start. Schedule a maintenance window, keep the old saved state and apply only the plan actually reviewed.
