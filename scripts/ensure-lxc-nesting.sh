#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[0-9]+$ ]]; then
  printf 'usage: %s <vmid>\n' "$0" >&2
  exit 2
fi
vmid=$1
config=$(ssh pve-00 "pct config $vmid")
features=
while IFS= read -r line; do
  case "$line" in
    features:*)
      features=${line#features:}
      features=${features# }
      ;;
  esac
done <<< "$config"

IFS=',' read -r -a flags <<< "$features"
merged=
has_nesting=0
nesting_enabled=0
for flag in "${flags[@]}"; do
  case "$flag" in
    nesting=1)
      has_nesting=1
      nesting_enabled=1
      ;;
    nesting=0)
      has_nesting=1
      flag=nesting=1
      ;;
  esac
  [[ -z $flag ]] && continue
  merged="${merged:+$merged,}$flag"
done

if (( nesting_enabled )); then
  printf 'LXC %s nesting already enabled; existing feature flags preserved.\n' "$vmid"
  exit 0
fi
if (( !has_nesting )); then
  merged="${merged:+$merged,}nesting=1"
fi
printf -v escaped_features '%q' "$merged"
printf 'Enabling nesting on LXC %s; preserving existing feature flags and rebooting it.\n' "$vmid"
ssh pve-00 "pct set $vmid --features $escaped_features && pct reboot $vmid --timeout 30"
