#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || ! $1 =~ ^[0-9]+$ ]]; then
  printf 'usage: %s <vmid> [feature=value ...]\n' "$0" >&2
  exit 2
fi
vmid=$1
shift
required=(nesting=1 "$@")
for feature in "${required[@]}"; do
  case "$feature" in
    nesting=0|nesting=1|keyctl=0|keyctl=1|fuse=0|fuse=1|mknod=0|mknod=1|mount=*) ;;
    *) printf 'unsupported LXC feature: %s\n' "$feature" >&2; exit 2 ;;
  esac
done

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
declare -a applied
for i in "${!required[@]}"; do applied[$i]=0; done
merged=
for flag in "${flags[@]}"; do
  [[ -z $flag ]] && continue
  key=${flag%%=*}
  for i in "${!required[@]}"; do
    requested=${required[$i]}
    [[ $key == "${requested%%=*}" ]] || continue
    if [[ $key == mount ]]; then
      current_mount=${flag#*=}
      requested_mount=${requested#*=}
      case ";$current_mount;" in
        *";$requested_mount;"*) ;;
        *) flag="mount=${current_mount};${requested_mount}" ;;
      esac
    else
      flag=$requested
    fi
    applied[$i]=1
    break
  done
  merged="${merged:+$merged,}$flag"
done

for i in "${!required[@]}"; do
  if (( !applied[$i] )); then
    merged="${merged:+$merged,}${required[$i]}"
  fi
done

if [[ $merged == "$features" ]]; then
  printf 'LXC %s already has required features; existing flags preserved.\n' "$vmid"
  exit 0
fi

printf -v escaped_features '%q' "$merged"
printf 'Updating LXC %s features to %s and restarting it.\n' "$vmid" "$merged"
ssh pve-00 "pct set $vmid --features $escaped_features && if pct status $vmid | grep -q running; then pct reboot $vmid --timeout 30; else pct start $vmid; fi"
