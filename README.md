# Proxmox Terraform

This repository independently manages guests on `pve-00` through OpenTofu and Task. The Proxmox API token is read at runtime from the `iac` 1Password vault item `pve-00-terraform-api-token`; credentials are not stored in Terraform files.

The OpenTofu state in `infra/terraform_proxmox/terraform.tfstate` belongs to this repository. It is not imported from or synchronized with `home-dc-kubernetes`; the existing Kubernetes deployment and its state stay there, untouched by these tasks.

## Deploy in stages

```bash
task init
task pbs-plan
task pbs-apply
task nodes-plan
task nodes-apply
```

- `task pbs-plan` plans the PBS LXC only. `task pbs-apply` creates and starts LXC 4020 on `pve-00`, `10.0.40.20/24`, using `local-nvme`. Its NIC is untagged on `vmbr0`; the Proxmox uplink's native/access network must be VLAN 40.
- The PBS task provisions a Debian LXC target; it does not run the Community Scripts installer or install PBS itself.
- `task nodes-plan` plans the Talos VM module and dependencies. `task nodes-apply` applies that module only: controllers 4090–4092 use `local-nvme`; workers 4093–4094 use `local-hdd`. Talos boot ISOs and generated cloud-init images use `nfs-proxmox-iso`.
- Talos VMs use the same untagged `vmbr0` network for VLAN 40 (`10.0.40.0/24`); their secondary VLAN 70 interface remains tagged. The uplink must carry VLAN 70 tagged. GPU worker 4094 is configured for P2000 passthrough. Talos configuration and Kubernetes bootstrap remain separate workflows.
- LXC SSH is available from VLAN 40 or routed clients using the root key in `~/.ssh/id_proxmox`; no root password is set. Apply tasks print direct SSH commands and the current host-key fingerprints. Talos guidance distinguishes unauthenticated maintenance access from authenticated API access after config/bootstrap.
- The Proxmox host bridge is untagged and not VLAN-aware, so VLAN 40 guests use untagged `vmbr0`; the switch uplink's native/access VLAN must be 40. The secondary Talos NIC remains tagged VLAN 70.
- PVE's API token cannot change feature flags on privileged LXCs. Apply tasks use the feature-preserving root-SSH helper to enable nesting and reboot an LXC only if nesting is not already enabled; Terraform ignores feature/user-account changes because these provider settings are restricted/create-time.
- PBS/Talos staged tasks use OpenTofu `-target` to avoid deploying the other stack early. Those targeting warnings are expected; run `task plan` afterward to inspect any intentionally pending resources.
- `task plan-preview` creates a full-stack plan without applying. `task plan` saves a full-stack plan. `task apply` presents a full plan and prompts before applying it. `task apply-existing-plan` applies the explicitly reviewed `tfplan` file.

The smoke LXC (4019, `10.0.40.19/24`) is untagged on `vmbr0` like the PVE host; the uplink's native/access network must be VLAN 40. It runs Debian 12 from the Proxmox standard LXC template, pinned by SHA-512. Terraform state, saved plans, and provider caches are ignored; never commit credentials or state files. See [`infra/terraform_proxmox/README.md`](infra/terraform_proxmox/README.md) for details.
