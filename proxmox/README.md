# Proxmox/Talos infrastructure

This is the active, independent OpenTofu root for the standalone `pve-00` host. Its state is `proxmox/terraform.tfstate`. The Kubernetes repository was not modified; its old Proxmox and service-host state snapshots are kept separately under `state-archive/` and are not loaded by these tasks.

`scripts/tofu.sh` runs OpenTofu through `doppler run` against Doppler project `home-dc-terraform`, config `prd` (PVE API token as `PROXMOX_TOKEN_ID`/`PROXMOX_TOKEN_SECRET`; generated PBS passwords are written back as `PBS_ADMIN_PASSWORD`/`PBS_BACKUP_PASSWORD`). The only secret outside Doppler is the Doppler service token in the macOS keychain item `home-dc-doppler-tf`. No credentials are committed.

## Deployment tasks

```bash
task pbs-plan
task pbs-apply
task nodes-plan
task nodes-apply
```

- PBS: LXC 4020, `10.0.40.20/24`, untagged on `vmbr0`, `local-nvme`, 4 vCPU / 8 GiB, Debian 13 (Trixie) as PBS 4 requires. `pbs-apply` creates the LXC and fully configures PBS with no manual step: `terraform_data.pbs_setup` enables the `mount=nfs` feature (root SSH to `pve-00`), copies `scripts/configure-pbs.sh` into the LXC over SSH (`~/.ssh/id_proxmox`) and runs it. The script is idempotent and re-runs whenever it or the container changes.
- The script runs the Community Scripts PBS installer, disables the subscription-only enterprise apt repo, mounts the NAS export `10.0.40.2:/proxmox-pbs-datastore`, creates the `home-dc` datastore (a fresh directory; the legacy datastore is untouched), and creates `pbs-admin@pbs` (Admin on `/`) and `pve-backup@pbs` (DatastoreBackup + DatastoreAudit on `/datastore/home-dc`). Passwords are `random_password` resources; they are written to Doppler (`PBS_ADMIN_PASSWORD`, `PBS_BACKUP_PASSWORD`) and available through `tofu output -raw pbs_admin_password` / `pbs_backup_password`. The script can also be run by hand in the LXC, prompting for the passwords.
- Log in to `https://10.0.40.20:8007` as user `pbs-admin`, realm **Proxmox Backup authentication server**. `root@pam` has no password.
- Remaining manual step: add a PBS storage in the PVE UI (server `10.0.40.20`, datastore `home-dc`, user `pve-backup@pbs`, the generated password, and the TLS fingerprint printed at the end of the script run). No scheduled backup job is created; choose its guests, schedule, and retention separately.
- PBS upstream documents directory datastores on ext4, XFS, and ZFS, but does not document NFS. This homelab already has a legacy PBS datastore on the NAS; the script creates a separate datastore and leaves the legacy 339 GiB store untouched. Verify GC and restore behavior before relying on NFS as the only backup copy.
- Talos VMs: `nodes-plan` creates a full-stack review plan in `tfplan-nodes`; `nodes-apply` applies exactly that saved plan. Controller 4090 is configured to start on `local-nvme`; workers 4095–4097 are configured to start on `local-hdd`. Boot ISOs are Talos `v1.13.8` (matching the Kubernetes repo's `talos/app/talenv.yaml`) and cloud-init images use `nfs-proxmox-iso`.
- Boot the installed `scsi0` disk **before** the attached Talos ISO (`ide3`). Assumption: on a fresh guest with an unbootable disk, SeaBIOS falls through to the ISO for initial installation. Once Talos installs, ISO-first boot halts the guest in installer mode; never restore that order for installed nodes. This is an in-place VM configuration update, not a disk replacement.

  **Validation:** `task nodes-plan` creates a full-stack plan in `tfplan-nodes`; apply only with `task nodes-apply` after review. The current one-time normalization is expected to set machine type `pc` on non-GPU VMs 4090, 4096, and 4097 (4096 currently has a blank value); GPU VM 4095 remains `q35`. The reviewed plan should show 0 add, 3 in-place changes, and 0 destroy, with no disk, network, or PCI changes. Schedule a maintenance stop/start for the three non-GPU VMs. Regenerate and review a fresh plan if configuration or state changes.

  **Rollback:** If a fresh, uninstalled guest cannot fall through to the ISO, boot it from the ISO for installation and reapply disk-first order before its first reboot. Do not revert installed nodes to ISO-first or remove their disks; inspect the Proxmox console before recovery. Keep the ISO attached as a rescue option.

- Each Talos VM has a single NIC untagged on `vmbr0` in VLAN 40. GPU worker 4095 (`k8s-wrkr-01-gpu`) has P2000 GPU/audio passthrough; its Talos image uses the NVIDIA **580-series LTS** driver/toolkit schematic `af8eb82417d3deaa94d2ef19c3b590b0dac1b2549d0b9b35b3da2bc325de75f7` because production 595 does not support this GPU. Accept NVIDIA's driver EULA before use and verify driver/runtime support in the guest.
- Before applying a worker GPU passthrough handoff, shut down both donor and recipient VMs in Proxmox. Host-PCI changes can reboot running VMs, and the VM updates are independent; `started = true` may start them again during apply. This is an operator step, not automated.
- Talos tasks provision VMs only; they do not configure Talos or bootstrap Kubernetes. They do not mutate `home-dc-kubernetes` files or state.
- Each worker VM receives a dedicated second data disk (`scsi1`) on `local-hdd`, default 100 GiB, controlled per node by `data_disk_size_gb` and `data_disk_storage_pool`. Controllers have no data disk. The existing system disk (`scsi0`) is unchanged.
- Talos machine config in `home-dc-kubernetes` selects a non-system disk for a worker user volume, mounted at `/var/mnt/local-path-provisioner`. Confirm each VM has exactly one non-system disk before applying Talos; this Terraform root only provisions the guest disks.
- The privileged PBS LXC needs `nesting=1` and `mount=nfs`. The PVE API token cannot change feature flags on an existing privileged LXC (HTTP 403), so the root-SSH helper adds them after creation and reboots only when a feature changes.
- PBS LXC SSH uses the root key from `~/.ssh/id_proxmox.pub`; no password is configured. `initialization.user_account` applies only at container creation, so existing LXCs were seeded through `pct exec`. Key rotation on existing LXCs is a manual authorized-keys update.
- PBS and Talos tasks use `-target` for isolated container operations and emit the standard targeting warning. `pbs-apply` targets the container, `terraform_data.pbs_setup` and the two PBS `doppler_secret` resources, and prompts for approval, so it needs a terminal. Talos tasks use a full-stack reviewed plan; successful applies print direct SSH commands and host-key fingerprints.
- Talos guidance lists each configured IP and VMID, labels workers as configured started, and distinguishes insecure maintenance access from authenticated `talosctl` after config/bootstrap. This root creates no `talosconfig` or VIP.

`task proxmox:tf:plan` creates a full Proxmox plan; `task proxmox:tf:apply` prompts before applying. `task plan-preview` creates a non-applying Proxmox plan; `task apply-existing-plan` applies the explicitly reviewed `proxmox/tfplan`. State, saved plans, and provider caches are ignored by Git.

## Capacity, backup, and validation

- Data-disk sizing assumes `local-hdd` has at least 300 GiB free for the three 100 GiB worker disks plus headroom for snapshots and Proxmox metadata. Confirm free space on `pve-00` before `nodes-apply`.
- Rollback before storing any workload data: restore the prior Terraform configuration and review a scoped plan. Once a worker data disk has PVC data, **never** remove it or its Terraform state to roll back without an independently verified off-host backup and restore.
- Validate a fresh plan before applying: it may add three `scsi1` disks, remove four obsolete VLAN 70 NICs and replace the GPU worker's Talos ISO reference with the 580-series LTS schematic. Stop on any VM replacement or `scsi0` resize/deletion.
- Removing the secondary NIC or changing the boot ISO may require a VM stop/start. Schedule a maintenance window, keep the old saved state and apply only the plan actually reviewed.
