# AGENTS.md

## Secrets and environment variables

[`docs/secrets-and-env-vars.md`](docs/secrets-and-env-vars.md) is the authoritative inventory of every secret, Doppler-sourced Terraform input, Doppler output and environment variable in this repository.

- Update it **in the same change** whenever you add, rename, remove or move any of these. That includes a `sensitive` variable, a `doppler_secret` resource, a Keychain item, the Doppler project/config in `scripts/tofu.sh` or a Taskfile, or a script's environment usage.
- Remember the `tf-var` name transformer: Doppler `FOO_BAR` is Terraform `var.foo_bar`. Keep both names in the table.
- Record names, locations, writers, readers and purpose only. Never write secret values into the file, a commit, a log or chat.
- When a value is shared across repositories (for example `PROXMOX_TOKEN_*` from `home-dc-proxmox`, or `TUNNEL_*` and `PBS_MONITORING_TOKEN_*` consumed by `home-dc-kubernetes`), update the other repository's `docs/secrets-and-env-vars.md` too.
- Before finishing, check for drift: `grep -rnE "sensitive|doppler_secret|DOPPLER|os\.environ|\\$\{?[A-Z_]{4,}" cloudflare proxmox scripts Taskfile.yml`. Every secret it shows must appear in the inventory.
