# Secrets and environment variables

The inventory of every secret, credential and environment variable the OpenTofu roots and helper scripts in this repository read or write. Values never belong in Git; this file records **names, locations and purpose only**.

> **Keep this file current.** Any change that adds, renames, moves or removes a secret, Terraform input variable sourced from Doppler, or environment variable must update this file in the same commit. See [`AGENTS.md`](../AGENTS.md).

## How secrets reach OpenTofu

Both roots run under `doppler run --project home-dc-terraform --config prd --name-transformer tf-var`, through `scripts/tofu.sh` for `proxmox/` and `cloudflare/Taskfile.yml` for `cloudflare/`. The `tf-var` transformer exposes each Doppler secret `FOO_BAR` as `TF_VAR_foo_bar`, so a Doppler name maps directly to a Terraform variable.

| Project / config | Access | Used by |
| --- | --- | --- |
| `home-dc-terraform` / `prd` | Read/write service token | Both roots (inputs and `doppler_secret` outputs), `scripts/pbs-monitoring-credential.py` |

## Inputs read from Doppler `home-dc-terraform/prd`

| Doppler name | Terraform variable | Root | Source | Function |
| --- | --- | --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | `cloudflare_api_token` | `cloudflare/` | Operator (manual) | Cloudflare API token for tunnels and Zero Trust Access. |
| `CLOUDFLARE_ACCOUNT_ID` | `cloudflare_account_id` | `cloudflare/` | Operator (manual) | Cloudflare account; also embedded in the tunnel token and credentials JSON. |
| `CLOUDFLARE_ZONE_ID` | `cloudflare_zone_id` | `cloudflare/` | Operator (manual) | Zone ID for `krapulax.dev`. |
| `TUNNEL_SECRET` *(optional)* | `tunnel_secret` | `cloudflare/` | Operator (manual) | Pre-existing `kubernetes-apps` tunnel secret. When it's empty, `random_id.kubernetes_tunnel_secret` is used. |
| `PROXMOX_TOKEN_ID` | `proxmox_token_id` | `proxmox/` | **Reference** to `home-dc-proxmox/prd` | ID of the `terraform@pve!provisioning` API token. |
| `PROXMOX_TOKEN_SECRET` | `proxmox_token_secret` | `proxmox/` | **Reference** to `home-dc-proxmox/prd` | Secret of that token. Rotated by the `home-dc-proxmox` Ansible role, not here. |

Non-secret inputs (`proxmox_endpoint`, `nodes`, `gateway`, `talos_version`, `dns_servers`, `talos_image_type`, tunnel names) have defaults in the `.tf` files. Any of them can still be overridden by a Doppler secret with the matching name.

## Outputs written to Doppler `home-dc-terraform/prd`

| Name | Written by | Consumed by | Function |
| --- | --- | --- | --- |
| `TUNNEL_CREDENTIALS_APPS` | `cloudflare/` `doppler_secret.kubernetes_tunnel_credentials` | `home-dc-kubernetes/apps` by reference | `kubernetes-apps` tunnel credentials JSON (AccountTag, TunnelID, TunnelSecret, TunnelName). |
| `TUNNEL_ID_APPS` | `cloudflare/` | `home-dc-kubernetes/apps` by reference | `kubernetes-apps` tunnel ID. |
| `TUNNEL_TOKEN_APPS` | `cloudflare/` | `home-dc-kubernetes/apps` → `cloudflare-tunnel-secret` (`TUNNEL_TOKEN`) | Connector token for the app-cluster `cloudflared`. |
| `TUNNEL_CREDENTIALS_INFRA` | `cloudflare/` | `home-dc-kubernetes/infra` by reference | `kubernetes-infra` tunnel credentials JSON. |
| `TUNNEL_ID_INFRA` | `cloudflare/` | `home-dc-kubernetes/infra` by reference | `kubernetes-infra` tunnel ID. |
| `TUNNEL_TOKEN_INFRA` | `cloudflare/` | `home-dc-kubernetes/infra` → `cloudflare-tunnel-infra-secret` (`TUNNEL_TOKEN`) | Connector token for the infra-cluster `cloudflared`. |
| `PBS_ADMIN_PASSWORD` | `proxmox/` `doppler_secret.pbs_admin_password` (`random_password.pbs_admin`) | Operator; `scripts/configure-pbs.sh` | Password for `pbs-admin@pbs` (PBS web UI). |
| `PBS_BACKUP_PASSWORD` | `proxmox/` `doppler_secret.pbs_backup_password` (`random_password.pbs_backup`) | Operator; `scripts/configure-pbs.sh` | Password for `pve-backup@pbs`, used when adding PBS storage in PVE. |
| `PBS_MONITORING_TOKEN_ID` | `scripts/pbs-monitoring-credential.py --apply` (`task pbs-monitoring-apply`) | Script idempotency check | ID of the audit-only `prometheus@pbs!victoriametrics` token. |
| `PBS_MONITORING_TOKEN_SECRET` | `scripts/pbs-monitoring-credential.py --apply` | `home-dc-kubernetes/infra` by reference → `pbs-exporter` | Secret of the PBS monitoring token. Never stored in Terraform state. |

`DOPPLER_APPS_TOKEN` and `DOPPLER_INFRA_TOKEN` were used previously and are **retired**; this repository no longer reads them.

## Local secrets (outside Doppler)

| Item | Location | Function |
| --- | --- | --- |
| Doppler service token | macOS Keychain, service `home-dc-doppler-tf`, account `$USER` | Authenticates `doppler run`, the Doppler provider and the PBS monitoring script. |
| SSH key pair | `~/.ssh/id_proxmox`, `~/.ssh/id_proxmox.pub` | Public key injected into LXC 4020. Private key used by the `pbs_setup` remote-exec provisioner. |
| SSH access to `pve-00` | Operator's SSH config / agent | `scripts/ensure-lxc-nesting.sh`, `scripts/pbs-monitoring-credential.py`, `access-*` tasks. |
| `cloudflare-tunnel.json`, `cloudflare-tunnel-infra.json` | Repo root, Git-ignored (`local_file` resources) | Local copies of the tunnel credentials JSON. |
| `*.tfstate*`, `tfplan*`, `*.tfvars` | Each root, Git-ignored | State and plans hold secret values in plaintext (tunnel secrets, PBS passwords). |
| `cloudflare/terraform.tfstate.before-doppler-migration` | Local, Git-ignored | Secret-bearing rollback backup from the Doppler migration. |
| `state-archive/` | Local, Git-ignored | Historical state only; never load it as active state. |

## Environment variables

| Variable | Where it's read | Source | Function |
| --- | --- | --- | --- |
| `DOPPLER_TOKEN` | `scripts/tofu.sh`, `cloudflare/Taskfile.yml`, `scripts/pbs-monitoring-credential.py`, Doppler provider | Optional override; otherwise read from Keychain `home-dc-doppler-tf` | Doppler service token. |
| `TF_VAR_*` | OpenTofu | Injected by `doppler run --name-transformer tf-var` | Terraform inputs (see the inputs table above). |
| `USER` | Keychain lookups | Shell | Keychain account name. |
| `PBS_ADMIN_PASSWORD`, `PBS_BACKUP_PASSWORD` | `scripts/configure-pbs.sh` (inside LXC 4020) | Set inline by the `terraform_data.pbs_setup` provisioner, or prompted when run by hand | Initial PBS account passwords. |

## Rotation notes

- Tunnel secrets have `ignore_changes`. Rotating one is a deliberate replacement, and the Kubernetes references pick up the new value at read time.
- Doppler cross-project references need an eligible plan. A missing source can come back as the literal reference string, so check that references resolve before applying.
- The Proxmox token is rotated in `home-dc-proxmox`. Update both repositories' inventories if names change.
