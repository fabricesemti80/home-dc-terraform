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
- Talos VMs: `nodes-plan`/`nodes-apply` target `module.talos` and its Proxmox dependencies only. Controllers 4090–4092 and workers 4093–4094 are configured to start. Controllers use `local-nvme`; workers use `local-hdd`. Boot ISOs and cloud-init images use `nfs-proxmox-iso`.
- Each Talos VM's primary NIC is untagged on `vmbr0` in VLAN 40; the secondary VLAN 70 Ceph NIC stays tagged. The switch uplink must carry VLAN 70 tagged. GPU worker 4094 is configured for P2000 GPU/audio passthrough and proprietary NVIDIA Talos extensions. Driver/runtime support is not verified; accept NVIDIA's driver EULA before use.
- Talos tasks provision VMs only; they do not configure Talos or bootstrap Kubernetes. They do not mutate `home-dc-kubernetes` files or state.
- The PVE API token cannot change feature flags on privileged LXCs (HTTP 403). `ensure-lxc-nesting` uses root SSH and merges `nesting=1` into the existing feature list, preserving all other flags; it reboots a container only when nesting is absent. Terraform ignores feature-flag drift; the helper is part of `pbs-apply`, `smoke`, and full apply tasks.
- Smoke and PBS LXC SSH use the root key from `~/.ssh/id_proxmox.pub`; no password is configured. `initialization.user_account` applies only at container creation, so existing LXCs were seeded through `pct exec`. Key rotation on existing LXCs is a manual authorized-keys update.
- Staged tasks use `-target`, so OpenTofu warns that a partial plan may omit other stacks; use `task plan` to review remaining work. Successful applies print direct SSH commands and host-key fingerprints. The PBS web UI is available at `https://10.0.40.20:8007` after installing PBS.
- Talos guidance lists each configured IP and VMID, labels workers as configured started, and distinguishes insecure maintenance access from authenticated `talosctl` after config/bootstrap. This root creates no `talosconfig` or VIP.
- Smoke LXC 4019 runs Debian 12 at `10.0.40.19/24`, untagged on `vmbr0`. Its Proxmox standard LXC template is pinned by SHA-512.

`task plan-preview` creates a non-applying full-stack plan. `task plan` saves a full-stack plan; `task apply` presents a full plan and requires interactive confirmation. Full-stack local state, saved plans, and provider caches are ignored by Git.
