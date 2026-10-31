#!/usr/bin/env bash
set -euo pipefail
# Secrets come from Doppler project home-dc-terraform, config prd. The only
# secret kept outside it is the read/write service token in the macOS keychain.
if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
  DOPPLER_TOKEN="$(security find-generic-password -a "$USER" -s home-dc-doppler-tf -w)"
  export DOPPLER_TOKEN
fi
exec doppler run --project home-dc-terraform --config prd --name-transformer tf-var -- tofu "$@"
