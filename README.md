# Infrastructure OpenTofu

This repository has two active, independent OpenTofu roots:

- `proxmox/` provisions guest VMs and LXCs on the standalone `pve-00` host. It does not configure the PVE host or install Talos/Kubernetes. The PBS LXC is a Debian target; this root does not install PBS.
- `cloudflare/` provisions the Kubernetes Cloudflare Tunnels and Zero Trust Access applications/policies. It writes tunnel credentials to Doppler project `home-dc-kubernetes` (`apps` and `infra` configs). Kubernetes `ExternalDNS` publishes application records; local DNS is served by Technitium. This root does not contain a local-DNS stack or direct DNS-record resources.

## Logical overview

![Logical overview of the independent OpenTofu roots and their Proxmox, Cloudflare, Doppler, and Kubernetes owners](docs/architecture.svg)

Ownership boundaries:

| Concern | Owner |
| --- | --- |
| Standalone PVE host configuration | Ansible in [`home-dc-proxmox`](https://github.com/fabricesemti80/home-dc-proxmox) |
| Proxmox guest lifecycle | OpenTofu in this repository, `proxmox/` |
| Talos configuration, Kubernetes bootstrap, manifests, and GitOps | [`home-dc-kubernetes`](https://github.com/fabricesemti80/home-dc-kubernetes) |
| Local DNS | Technitium; no active Terraform root here |
| UniFi network configuration | Separate local repository `../homelab-terraform-unifi`; UniFi DNS records are legacy, not the local-DNS source of truth |

Historical Terraform state/configuration from the former Kubernetes repository remains under local, Git-ignored `state-archive/`. Those files are not active roots or an alternate source of truth. No service-host stack is active.

## Tasks

Root tasks run across both active roots (Cloudflare first, then Proxmox):

```bash
task tf:init
task tf:plan
task tf:apply
```

Use namespaced tasks for one root:

```bash
task cloudflare:tf:init
task cloudflare:tf:plan
task cloudflare:tf:apply
task proxmox:tf:init
task proxmox:tf:plan
task proxmox:tf:apply
```

Per-root `tf:apply` tasks present a fresh interactive plan; they do not auto-approve changes. Both roots read their credentials from Doppler project `home-dc-terraform`, config `prd`, authenticated by the service token in the macOS keychain item `home-dc-doppler-tf` (see `scripts/tofu.sh` and `cloudflare/Taskfile.yml`). The only cross-project write is the Cloudflare root publishing tunnel credentials to `home-dc-kubernetes` (`apps`, `infra`) using the scoped `DOPPLER_APPS_TOKEN`/`DOPPLER_INFRA_TOKEN` stored in `prd`.

For guest operations, `task nodes-plan` creates the reviewed full-stack Talos VM plan and `task nodes-apply` applies that saved plan. `task pbs-plan` and `task pbs-apply` operate on LXC 4020 at `10.0.40.20/24` and also install and configure PBS (`scripts/configure-pbs.sh`: NFS datastore, `pbs-admin@pbs` and `pve-backup@pbs`; generated passwords are written to Doppler `PBS_ADMIN_PASSWORD`/`PBS_BACKUP_PASSWORD`). See [`proxmox/README.md`](proxmox/README.md) for storage, network, and access details.

OpenTofu state, saved plans, provider caches, tunnel credential JSON, and archived state are local secret material and ignored by Git. Never commit them.
