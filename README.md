# Proxmox Terraform

This repository manages guests on `pve-00` through OpenTofu and Task. Its Proxmox API endpoint is `https://10.0.40.10:8006`. The API token is read at runtime from the `iac` 1Password vault item `pve-00-terraform-api-token`; no token is stored in Terraform variable files.

## Proxmox stack

`infra/terraform_proxmox` holds the Proxmox provider root and Talos module, including the `module.talos.*` resource addresses and `nodes.yaml` IP/MAC output update. It preserves definitions for three controllers (VMIDs 4090–4092); the old local state records these on `pve-0`, `pve-1`, and `pve-2`, while the new root targets the standalone `pve-00`. Two worker definitions (4093 and 4094) are stopped on `local-hdd`; the GPU worker's Talos schematic has not been verified for NVIDIA driver support. All guests use VLAN 40 addressing. PBS CT ID 4020 is configured for `10.0.40.20/24`, gateway `10.0.40.1`.

The previous Proxmox/Talos state is still in the Kubernetes repository's local working copy and has not been copied or reconciled here. It records controllers on `pve-0`, `pve-1`, and `pve-2`, unlike the live standalone `pve-00`. The Kubernetes repository's Proxmox task entrypoints were removed, but its local state is preserved. Full `task plan` and `task apply` require a deliberate state handoff, represented by `infra/terraform_proxmox/STATE-HANDOFF-COMPLETE`; do not create that marker before reviewing and reconciling ownership. The targeted smoke LXC was deployed separately.

## Tasks

- `task init`: initialize providers.
- `task plan-preview`: create a local plan for review.
- `task apply-existing-plan`: apply only a previously reviewed plan file; do not use before state handoff.
- `task smoke`: successfully creates the Debian LXC (ID 4019, `10.0.40.19/24`, VLAN 40); it remains stopped on `local-nvme`.
- `task pbs-plan`: create a targeted plan for PBS CT ID 4020 (`10.0.40.20/24`, VLAN 40); not applied.
- `task pbs-apply`: apply the PBS LXC only after reviewed state handoff.

The PBS configuration creates a privileged Debian LXC with resource limits; it does **not** install PBS or run the Community Scripts installer. Validate that script's requirements before execution. GPU passthrough is not configured: PVE docs identify the P2000 GPU and audio functions, but Talos schematic extensions and guest driver support remain unverified.

The local state, plan, and provider cache are ignored. Never commit `.tfstate`, `tfplan`, provider cache, or credentials. The PVE token grants administrator access; review plans and apply only intentionally.
