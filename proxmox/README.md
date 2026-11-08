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
- PBS monitoring credential: run `task pbs-monitoring-plan`, review its output, then `task pbs-monitoring-apply` to provision the separate `prometheus@pbs!victoriametrics` token. It assigns only the built-in `Audit` role to the user and token at `/` with propagation enabled; PBS intersects their permissions. The plan reports missing or non-propagating grants, and apply restores propagation. The task stores `PBS_MONITORING_TOKEN_ID` and `PBS_MONITORING_TOKEN_SECRET` in Doppler `home-dc-terraform/prd`, never in Terraform state, command arguments, logs or Git. It does not run the PBS installer, restart services, alter the datastore or schedule jobs. Use the verified PBS certificate and DNS identity when connecting; the IP is not present in its certificate SAN. Check token permissions with `proxmox-backup-manager user permissions` and verify actual exporter metrics against PBS 4.2.8; repeat apply must report no changes. If creation is interrupted, stop on partial state and reconcile deliberately. Rotate before its one-year expiry by creating a second audit-only token, switching the exporter, confirming scrapes, and only then revoking the old token; remove only the monitoring token and its ACLs for rollback.
- Talos VMs: `nodes-plan` creates a full-stack review plan in `tfplan-nodes`; `nodes-apply` applies exactly that saved plan. Controller 4090 is configured to start on `local-nvme`; workers 4095–4097 are configured to start on `local-hdd`. Boot ISOs are Talos `v1.13.8` (matching the Kubernetes repo's `talos/app/talenv.yaml`) and cloud-init images use `nfs-proxmox-iso`.
- Boot the installed `scsi0` disk **before** the attached Talos ISO (`ide3`). Assumption: on a fresh guest with an unbootable disk, SeaBIOS falls through to the ISO for initial installation. Once Talos installs, ISO-first boot halts the guest in installer mode; never restore that order for installed nodes. This is an in-place VM configuration update, not a disk replacement.

  **Validation:** `task nodes-plan` creates a full-stack plan in `tfplan-nodes`; apply only with `task nodes-apply` after review. The current one-time normalization is expected to set machine type `pc` on non-GPU VMs 4090, 4096, and 4097 (4096 currently has a blank value); GPU VM 4095 remains `q35`. The reviewed plan should show 0 add, 3 in-place changes, and 0 destroy, with no disk, network, or PCI changes. Schedule a maintenance stop/start for the three non-GPU VMs. Regenerate and review a fresh plan if configuration or state changes.

  **Rollback:** If a fresh, uninstalled guest cannot fall through to the ISO, boot it from the ISO for installation and reapply disk-first order before its first reboot. Do not revert installed nodes to ISO-first or remove their disks; inspect the Proxmox console before recovery. Keep the ISO attached as a rescue option.

- Each Talos VM has a single NIC untagged on `vmbr0` in VLAN 40. GPU worker 4095 (`k8s-wrkr-01-gpu`) has P2000 GPU/audio passthrough; its Talos image uses the NVIDIA **580-series LTS** driver/toolkit schematic `af8eb82417d3deaa94d2ef19c3b590b0dac1b2549d0b9b35b3da2bc325de75f7` because production 595 does not support this GPU. Accept NVIDIA's driver EULA before use and verify driver/runtime support in the guest.
- Before applying a worker GPU passthrough handoff, shut down both donor and recipient VMs in Proxmox. Host-PCI changes can reboot running VMs, and the VM updates are independent; `started = true` may start them again during apply. This is an operator step, not automated.
- Talos tasks provision VMs only; they do not configure Talos or bootstrap Kubernetes. They do not mutate `home-dc-kubernetes` files or state.
- Each worker VM receives a dedicated second data disk (`scsi1`) on `local-hdd`, default 100 GiB, controlled per node by `data_disk_size_gb` and `data_disk_storage_pool`. Controllers have no data disk. The existing system disk (`scsi0`) is unchanged.
- Talos machine config in `home-dc-kubernetes` selects a non-system disk for a worker user volume, mounted at `/var/mnt/local-path-provisioner`. Each worker now has **two** non-system disks (see [Raw SSD passthrough](#raw-ssd-passthrough-for-longhorn-scsi2)): the 100 GiB `local-hdd` data disk (`scsi1`) and, when `passthrough_disk_by_id` is set, a ~465 GiB whole SSD (`scsi2`). Talos must therefore select disks by size/serial and never by "the only non-system disk"; the local-path `diskSelector` must match only the 100 GiB disk. This Terraform root only provisions the guest disks.
- The privileged PBS LXC needs `nesting=1` and `mount=nfs`. The PVE API token cannot change feature flags on an existing privileged LXC (HTTP 403), so the root-SSH helper adds them after creation and reboots only when a feature changes.
- PBS LXC SSH uses the root key from `~/.ssh/id_proxmox.pub`; no password is configured. `initialization.user_account` applies only at container creation, so existing LXCs were seeded through `pct exec`. Key rotation on existing LXCs is a manual authorized-keys update.
- PBS and Talos tasks use `-target` for isolated container operations and emit the standard targeting warning. `pbs-apply` targets the container, `terraform_data.pbs_setup` and the two PBS `doppler_secret` resources, and prompts for approval, so it needs a terminal. Talos tasks use a full-stack reviewed plan; successful applies print direct SSH commands and host-key fingerprints.
- Talos guidance lists each configured IP and VMID, labels workers as configured started, and distinguishes insecure maintenance access from authenticated `talosctl` after config/bootstrap. This root creates no `talosconfig` or VIP.

## Raw SSD passthrough for Longhorn (`scsi2`)

Each worker can get one whole host SSD as a raw passthrough disk for Longhorn, selected per node with the optional `passthrough_disk_by_id` field of `nodes` (default: none, so controllers and other workers are unaffected). `nodes.auto.tfvars` is git-ignored, so add the field to the three worker entries locally:

| VM | Node | `passthrough_disk_by_id` |
| --- | --- | --- |
| 4095 | `k8s-wrkr-01-gpu` | `ata-CT500MX500SSD1_2344E8836BF7` |
| 4096 | `k8s-wrkr-02` | `ata-CT500MX500SSD1_2344E8836D00` |
| 4097 | `k8s-wrkr-03` | `ata-CT500MX500SSD1_2349E8875927` |

Always the bare name under `/dev/disk/by-id/` (never `sdX`, never a `-partN` partition; validated). Each id may be used by one node only, and only on workers. The guest sees a ~465 GiB disk (`scsi2`, `ssd=1`, `discard=on`, `backup=0` so PBS jobs never copy it, guest serial = the drive serial, e.g. `2344E8836BF7`). The 100 GiB data disk (`scsi1`) and the 55 GiB system disk (`scsi0`) are not touched.

**Why a script and not a provider `disk` block.** Proxmox only lets a real `root@pam` session assign host block devices ("only root can pass arbitrary filesystem paths"); API tokens are rejected, including a token owned by `root@pam`. This root authenticates with an API token and holds no root password, so the provider's `disk { path_in_datastore = "/dev/disk/by-id/..." }` cannot work here. Following the PBS pattern, `terraform_data.passthrough_disk` (in `modules/talos`) runs `scripts/ensure-vm-passthrough-disk.sh` over root SSH to the node (`ssh pve-00`, same access as `ensure-lxc-nesting.sh`). The script:

- is idempotent: if the disk is already attached to that VM on `scsi2` it does nothing;
- refuses when the by-id link is missing or not a whole disk, any partition is mounted, swap is active, the disk is in a ZFS pool, an LVM PV or has a device-mapper/md device on it, the disk is referenced by any other VM or LXC config, or `scsi2` is already in use by something else;
- only ever runs `qm set <vmid> --scsi2 /dev/disk/by-id/...`; it never wipes, formats, detaches, stops or restarts. Old signatures on the SSDs are cleared by the guarded Ansible role in `home-dc-proxmox`, not here. `DRY_RUN=1 scripts/ensure-vm-passthrough-disk.sh pve-00 4096 scsi2 ata-CT500MX500SSD1_2344E8836D00` runs all guards read-only and prints the command.

**No drift / no replacement.** The provider reads every disk of a VM into state, so an unmanaged `scsi2` would make each plan propose removing that disk block (verified with a synthetic state that contained `scsi2`). The VM resource therefore uses `lifecycle { ignore_changes = [disk] }` (previously `[disk[0].file_id]`). Consequence: Terraform no longer reports or applies changes to `scsi0`/`scsi1` (for example a size change in `disk_size_gb`/`data_disk_size_gb`) on existing VMs; initial creation still honours them. Resize or replace disks deliberately (for example `qm resize` or `-replace`) and review the plan by hand.

**Plan evidence** (`task nodes-plan`, against the live API with a refreshed state): `Plan: 3 to add, 0 to change, 0 to destroy.`, the three adds being `module.talos.terraform_data.passthrough_disk["k8s-wrkr-01-gpu"|"k8s-wrkr-02"|"k8s-wrkr-03"]`. No `proxmox_virtual_environment_vm` is changed or replaced.

**Operator steps (not run by this change).**

1. Make sure `home-dc-proxmox` has wiped the old signatures on the three SSDs (or that they are acceptable to attach as they are; Longhorn/Talos will not claim a disk with foreign signatures).
2. `task nodes-plan`, review (3 adds, 0 changes, 0 destroys), run the `DRY_RUN=1` command above for each node.
3. Maintenance window: drain and shut down each worker (`qm shutdown`) before `task nodes-apply` so `qm set` records the disk in the stopped VM's config; `nodes-apply` does not start them. Then `qm start` each worker. A running VM may instead hot-plug or hold `scsi2` as a pending change, which needs a full stop/start (not a guest reboot); the script prints which one happened.
4. Verify in the guest with `talosctl get disks` that a ~465 GiB disk with the expected serial is present and that the 100 GiB data disk is unchanged.

**Rollback.** Before Longhorn stores data: shut down the VM, `qm set <vmid> --delete scsi2` (detaches only; the SSD content is untouched), start the VM, and remove `passthrough_disk_by_id` from the node. Removing the variable alone does **not** detach the disk (the helper has no destroy step by design). Re-attaching needs the same node entry and `tofu apply -replace='module.talos.terraform_data.passthrough_disk["<node>"]'` (also needed if a VM is ever recreated). **Warning:** once Longhorn holds volumes on a disk, detaching or removing it destroys that replica; do it only after the volumes are healthy on the other nodes, or after a verified off-host backup and restore. The SSD is the only copy of that replica.

## Trinity NixOS VM

Trinity is a separate generic VM, not part of the Talos module: VMID 4050 (`trinity`) on `pve-00`, 4 vCPU, 8 GiB RAM, 80 GiB `local-nvme`, x86_64 UEFI. Its NIC uses `vmbr0` untagged. `pve-00`'s `vmbr0` is a bridge over `nic0` without VLAN-aware configuration; VLAN 40 is the native untagged network, so do not set `vlan_id = 40`. The address is `10.0.40.50/24`, gateway `10.0.40.1`.

Deployment is two commands, with one confirmation prompt and no console or GUI step:

```bash
task proxmox:trinity-plan     # optional review, no changes
task proxmox:trinity-deploy   # create VM, wait for SSH, install NixOS, verify
```

How it works:

1. OpenTofu has Proxmox download a pinned Debian 13 cloud image (SHA-512 verified) into `nfs-proxmox-iso` (`import` content) and creates VM 4050 from it. Proxmox cloud-init sets the static address, DNS and the public key `~/.ssh/id_proxmox.pub` for the bootstrap user `debian` (passwordless sudo).
2. `scripts/trinity-install.sh` waits for SSH and refuses unless the target is the fresh Debian bootstrap: VM named `trinity` with an 80 GiB disk, the guest NIC matches the MAC Proxmox reports, `/dev/sda` is exactly 80 GiB, and `/etc/NIXOS` is absent. An already-installed NixOS Trinity is never reinstalled.
3. `nixos-anywhere --build-on remote --copy-host-keys` kexecs into a NixOS installer on the VM, partitions it with disko and installs `path:.#trinity` from `../nix-hosts`. The Mac builds nothing. Disko erases the bootstrap disk, which is intended.
4. `task proxmox:trinity-status` confirms the installed system over SSH as `fs@10.0.40.50`.

The VM resource ignores changes to `started`, `disk`, `initialization`, `efi_disk` and `boot_order`, so a later apply never alters an installed host. Terraform owns only the VM hardware and bootstrap disk; the OS is owned by `nix-hosts` and configured with `task proxmox:trinity-configure` (`just nixos-switch trinity`). Other tasks: `trinity-ssh`, `trinity-start`, `trinity-install` (install only) and `trinity-console` (Proxmox web console, troubleshooting only).

Rebuilding Trinity (`tofu apply -replace=proxmox_virtual_environment_vm.trinity`) destroys its disk and repeats the bootstrap. The Debian image URL is dated; if cloud.debian.org rotates that build away, update `url`, `file_name` and `checksum` in `proxmox/trinity.tf`.

`task proxmox:plan` creates a full Proxmox plan; `task proxmox:apply` prompts once, applies, and then runs `scripts/trinity-install.sh --auto`: it installs NixOS on a freshly created Trinity bootstrap VM, and quietly skips when Trinity is absent or already runs NixOS (identity mismatches still fail). So `task proxmox:plan` followed by `task proxmox:apply` is the whole Trinity deployment, including after deleting the VM. `task plan-preview` creates a non-applying Proxmox plan; `task apply-existing-plan` applies the explicitly reviewed `proxmox/tfplan`. State, saved plans, and provider caches are ignored by Git.

## Capacity, backup, and validation

- Data-disk sizing assumes `local-hdd` has at least 300 GiB free for the three 100 GiB worker disks plus headroom for snapshots and Proxmox metadata. Confirm free space on `pve-00` before `nodes-apply`.
- Rollback before storing any workload data: restore the prior Terraform configuration and review a scoped plan. Once a worker data disk has PVC data, **never** remove it or its Terraform state to roll back without an independently verified off-host backup and restore.
- Validate a fresh plan before applying: it may add three `scsi1` disks, remove four obsolete VLAN 70 NICs and replace the GPU worker's Talos ISO reference with the 580-series LTS schematic. Stop on any VM replacement or `scsi0` resize/deletion.
- Removing the secondary NIC or changing the boot ISO may require a VM stop/start. Schedule a maintenance window, keep the old saved state and apply only the plan actually reviewed.
