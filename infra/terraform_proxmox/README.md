# Proxmox/Talos infrastructure

Tasks in the repository root manage this stack. `scripts/tofu.sh` reads the Proxmox API token from the `iac` 1Password vault; it does not write credentials to Terraform files.

`task smoke` deploys and starts Debian 12 LXC 4019 on `pve-00` at `10.0.40.19/24`, VLAN 40. It uses the Proxmox Debian standard LXC template pinned by SHA-512. Verified running with the configured IPv4 address and default route.

The PBS target is a stopped privileged LXC, ID 4020, at `10.0.40.20/24`, VLAN 40, on `local-nvme`. `task pbs-plan` creates a review plan only. Terraform provisions the container but does not install Proxmox Backup Server or run the Community Script.

Talos configuration defines three controllers (4090–4092) and two workers (4093–4094), all assigned to `pve-00`. The guest primary network is VLAN 40; a second interface carries the Ceph network on VLAN 70. Worker VMs are configured stopped. GPU passthrough and the proprietary NVIDIA Talos extensions are configured for worker 4094, but not yet applied; accept NVIDIA's driver EULA and verify the guest driver/runtime before using it.

## State handoff required

This root is not safe to apply from an empty local state. The Kubernetes Terraform state contains the three current controller bindings at `module.talos.proxmox_virtual_environment_vm.talos_node["k8s-ctrl-01"]`, `["k8s-ctrl-02"]`, and `["k8s-ctrl-03"]` with IDs 4090, 4091, and 4092. The source state remains at `../home-dc-kubernetes/infra/terraform_proxmox/terraform.tfstate`; it has not been handed off.

The source state records the controllers on `pve-0`, `pve-1`, and `pve-2`; that is historical state, not the target placement. All VM definitions in this root target `pve-00`, with storage selected per node. `task plan-preview` is available before the handoff marker and creates a non-applying full-stack plan for inspection. Before handoff, this plan uses only this root's local state; it does not include ownership information from the Kubernetes state and may propose recreating its resources. It is evidence about the current root and live host only, not a migration plan. Transfer/reconcile state ownership and verify actual VMIDs before creating `STATE-HANDOFF-COMPLETE`. Afterward, `task plan` creates a full-stack plan using the handed-off state; review it for correct `pve-00` placement/storage and no unexpected VM recreation or destruction before applying. The `apply`, `apply-existing-plan`, and `pbs-apply` tasks remain guarded until state handoff.
