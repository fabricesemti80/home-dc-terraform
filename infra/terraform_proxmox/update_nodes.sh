#!/usr/bin/env bash
set -euo pipefail

nodes_yaml="${NODES_YAML:?NODES_YAML must point to nodes.yaml}"
nodes_json="${NODES_JSON:?NODES_JSON must contain node IP and MAC values}"

if [[ ! -f "$nodes_yaml" ]]; then
  echo "nodes.yaml not found at $nodes_yaml" >&2
  exit 1
fi

command -v jq >/dev/null
command -v yq >/dev/null

tmp_input=$(mktemp)
trap 'rm -f "$tmp_input"' EXIT
printf '%s\n' "$nodes_json" | jq -r 'to_entries[] | "\(.key) \(.value.mac_address) \(.value.ceph_mac_address) \(.value.ip)"' > "$tmp_input"

while read -r name mac ceph_mac ip; do
  [[ -n "$mac" && "$mac" != "null" ]] || continue
  mac=$(printf '%s' "$mac" | tr '[:upper:]' '[:lower:]')
  ceph_mac=$(printf '%s' "$ceph_mac" | tr '[:upper:]' '[:lower:]')
  if yq ".nodes[] | select(.name == \"$name\")" "$nodes_yaml" >/dev/null 2>&1; then
    yq -y -i "(.nodes[] | select(.name == \"$name\")).mac_addr = \"$mac\"" "$nodes_yaml"
    yq -y -i "(.nodes[] | select(.name == \"$name\")).ceph_mac_addr = \"$ceph_mac\"" "$nodes_yaml"
    yq -y -i "(.nodes[] | select(.name == \"$name\")).address = \"$ip\"" "$nodes_yaml"
    echo "Updated $name: IP=$ip, MAC=$mac, Ceph MAC=$ceph_mac"
  else
    echo "Node $name not found in nodes.yaml, skipping update."
  fi
done < "$tmp_input"
