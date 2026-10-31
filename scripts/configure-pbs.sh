#!/usr/bin/env bash
set -euo pipefail

# Run as root inside the PBS LXC (Debian 13 template). Terraform runs this with PBS_ADMIN_PASSWORD/PBS_BACKUP_PASSWORD set; it can also be run by hand.
# PBS 4's Community Scripts installer targets Debian 13 (Trixie).

readonly CORE_REF="5acac4483be88990354dd4e3778e2cdce4df428e"
readonly APP_REF="dd2d2a169694d96da2005042abe828f81e48c2c1"
readonly CORE_URL="https://raw.githubusercontent.com/community-scripts/core/${CORE_REF}"
readonly APP_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/${APP_REF}"
readonly NFS_SERVER="10.0.40.2"
readonly NFS_EXPORT="/proxmox-pbs-datastore"
readonly NFS_MOUNT="/mnt/pbs"
readonly DATASTORE="home-dc"
readonly DATASTORE_PATH="${NFS_MOUNT}/pbs/${DATASTORE}"
readonly ADMIN_USER="pbs-admin@pbs"
readonly BACKUP_USER="pve-backup@pbs"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

read_secret() {
  local variable_name=$1 prompt=$2 value
  value=${!variable_name:-}
  if [[ -z $value ]]; then
    [[ -t 0 ]] || fail "Set ${variable_name} from your secret manager when running non-interactively."
    read -r -s -p "${prompt}: " value
    printf '\n'
  fi
  [[ ${#value} -ge 8 ]] || fail "${variable_name} must contain at least 8 characters."
  printf '%s' "$value"
}

user_exists() {
  proxmox-backup-manager user list --output-format json | grep -Fq "$1"
}

[[ $EUID -eq 0 ]] || fail 'Run this script as root inside the PBS LXC.'
[[ -r /etc/os-release ]] || fail 'Cannot detect the container operating system.'
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_CODENAME:-} == trixie ]] || \
  fail 'The Community Scripts PBS 4 installer requires Debian 13 (Trixie). Redeploy LXC 4020 with the Terraform Debian 13 template first.'

export DEBIAN_FRONTEND=noninteractive

# The PBS installer adds the subscription-only enterprise repo (401 without a
# subscription), which breaks every later `apt-get update`. Disable it.
disable_enterprise_repo() {
  local f=/etc/apt/sources.list.d/pbs-enterprise.sources
  [[ -f $f ]] && ! grep -q '^Enabled: no' "$f" && printf 'Enabled: no\n' >>"$f"
  return 0
}
disable_enterprise_repo
apt-get update
apt-get install -y ca-certificates curl nfs-common openssl

if ! command -v proxmox-backup-manager >/dev/null 2>&1; then
  # Keep the container root account locked; PBS access uses dedicated PBS users.
  export MODE=default PASSWORD=preserve app=proxmox-backup-server
  export COMMUNITY_SCRIPTS_CORE_URL="$CORE_URL"
  export FUNCTIONS_FILE_PATH="$(curl -fsSL "${CORE_URL}/lxc/install.func")"
  curl -fsSL "${APP_URL}/install/proxmox-backup-server-install.sh" | bash
  disable_enterprise_repo
fi

if ! grep -Fq "${NFS_SERVER}:${NFS_EXPORT} ${NFS_MOUNT} nfs " /etc/fstab; then
  printf '%s %s nfs vers=4.1,_netdev 0 0\n' "${NFS_SERVER}:${NFS_EXPORT}" "$NFS_MOUNT" >>/etc/fstab
fi
mkdir -p "$NFS_MOUNT"
if ! mountpoint -q "$NFS_MOUNT"; then
  mount "$NFS_MOUNT" || fail "NFS mount failed; ensure LXC 4020 has the Proxmox mount=nfs feature."
fi

# Keep PBS from starting until the remote datastore mount is available after a
# container restart. The legacy datastore remains untouched in its own directory.
for unit in proxmox-backup.service proxmox-backup-proxy.service; do
  install -d -m 0755 "/etc/systemd/system/${unit}.d"
  cat >"/etc/systemd/system/${unit}.d/10-pbs-datastore.conf" <<EOF
[Unit]
RequiresMountsFor=${NFS_MOUNT}
EOF
done
systemctl daemon-reload

install -d -o backup -g backup -m 0750 "$DATASTORE_PATH"
if datastore_config=$(proxmox-backup-manager datastore show "$DATASTORE" 2>/dev/null); then
  grep -Fq "$DATASTORE_PATH" <<<"$datastore_config" || fail "Datastore ${DATASTORE} exists at a different path."
else
  proxmox-backup-manager datastore create "$DATASTORE" "$DATASTORE_PATH"
fi

if ! user_exists "$ADMIN_USER"; then
  admin_password=$(read_secret PBS_ADMIN_PASSWORD 'PBS web administrator password')
  proxmox-backup-manager user create "$ADMIN_USER" --password "$admin_password" --comment 'PBS web administrator'
fi
proxmox-backup-manager acl update / Admin --auth-id "$ADMIN_USER"

if ! user_exists "$BACKUP_USER"; then
  backup_password=$(read_secret PBS_BACKUP_PASSWORD 'PVE backup account password')
  proxmox-backup-manager user create "$BACKUP_USER" --password "$backup_password" --comment 'Proxmox VE backup client'
fi
proxmox-backup-manager acl update "/datastore/${DATASTORE}" DatastoreBackup --auth-id "$BACKUP_USER"
proxmox-backup-manager acl update "/datastore/${DATASTORE}" DatastoreAudit --auth-id "$BACKUP_USER"

systemctl enable --now proxmox-backup.service proxmox-backup-proxy.service
systemctl restart proxmox-backup.service proxmox-backup-proxy.service

printf '\nPBS is ready.\n'
printf 'Web UI: https://%s:8007\n' "$(hostname -I | awk '{print $1}')"
printf 'Administrator: %s\n' "$ADMIN_USER"
printf 'Datastore: %s at %s\n' "$DATASTORE" "$DATASTORE_PATH"
printf 'PVE backup account: %s\n' "$BACKUP_USER"
printf 'TLS fingerprint: '
openssl x509 -in /etc/proxmox-backup/proxy.pem -noout -fingerprint -sha256 | cut -d= -f2
printf '\nAdd a PBS storage in the PVE UI with this address, datastore, backup account, password, and fingerprint.\n'
