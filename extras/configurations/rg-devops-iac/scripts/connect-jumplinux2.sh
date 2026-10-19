#!/bin/bash
# Connects to jumplinux2 through Azure Bastion using Microsoft Entra ID SSH sign-in, for VS Code Remote-SSH or ssh.
#
# What it does:
#   1. Requests a short-lived (about 1 hour) Entra ID OpenSSH certificate with 'az ssh cert'.
#   2. Writes (or updates) a managed 'Host jumplinux2' block in ~/.ssh/config that points at the local tunnel port.
#   3. Opens 'az network bastion tunnel' to the VM resource id in the foreground, renewing the certificate in the
#      background about every 50 minutes while the tunnel is up.
#
# Keep this terminal open while connected: it hosts the Bastion tunnel. Press Ctrl+C to close the tunnel.
# Then connect with VS Code Remote-SSH (host 'jumplinux2') or 'ssh jumplinux2' from another terminal.
#
# Prerequisites: Azure CLI signed in ('az login') with the 'bastion' and 'ssh' extensions, OpenSSH client
# (ssh-keygen), python3, and the 'Virtual Machine Administrator Login' role on the VM plus Reader on the VM,
# its NIC and the Bastion host. Defaults are read from this configuration's Terraform outputs; override them
# with the options below when the state isn't available locally.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$(dirname -- "$script_dir")"

bastion_name=""
resource_group=""
vm_id=""
host_alias="jumplinux2"
local_port="2222"
renew_seconds=3000

usage() {
  cat << EOF
Usage: $(basename "$0") [options]

Options:
  -b, --bastion-name NAME     Bastion host name (default: terraform output resource_names["bastion_host"])
  -g, --resource-group NAME   Resource group of the Bastion host (default: terraform output resource_names["resource_group"])
  -v, --vm-id ID              VM resource id (default: terraform output resource_ids["virtual_machine_jumplinux2"])
  -a, --host-alias ALIAS      ~/.ssh/config host alias (default: $host_alias)
  -p, --port PORT             Local tunnel port (default: $local_port)
  -h, --help                  Show this help
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    -b|--bastion-name) bastion_name="${2:?}"; shift 2 ;;
    -g|--resource-group) resource_group="${2:?}"; shift 2 ;;
    -v|--vm-id) vm_id="${2:?}"; shift 2 ;;
    -a|--host-alias) host_alias="${2:?}"; shift 2 ;;
    -p|--port) local_port="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "unknown option '$1'" ;;
  esac
done

[[ "$local_port" =~ ^[0-9]+$ ]] || fail "port must be numeric"
[[ "$host_alias" =~ ^[A-Za-z0-9._-]+$ ]] || fail "host alias may contain only letters, digits, '.', '_' and '-'"

#region prerequisites
for cmd in az ssh-keygen python3; do
  command -v "$cmd" > /dev/null || fail "'$cmd' is required but was not found in PATH"
done

az account show --only-show-errors > /dev/null 2>&1 || fail "not signed in to Azure CLI; run 'az login' first"

for extension in bastion ssh; do
  az extension show --name "$extension" --only-show-errors > /dev/null 2>&1 \
    || fail "Azure CLI '$extension' extension is required; run 'az extension add --name $extension'"
done
#endregion

#region resolve-targets
tf_output() {
  # $1 = output name, $2 = map key. Prints nothing if the output isn't available.
  terraform -chdir="$config_dir" output -json "$1" 2> /dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ''))" "$2" 2> /dev/null || true
}

if [ -z "$bastion_name" ] || [ -z "$resource_group" ] || [ -z "$vm_id" ]; then
  command -v terraform > /dev/null || fail "terraform not found; pass --bastion-name, --resource-group and --vm-id"
  [ -n "$bastion_name" ] || bastion_name="$(tf_output resource_names bastion_host)"
  [ -n "$resource_group" ] || resource_group="$(tf_output resource_names resource_group)"
  [ -n "$vm_id" ] || vm_id="$(tf_output resource_ids virtual_machine_jumplinux2)"
fi

[ -n "$bastion_name" ] && [ -n "$resource_group" ] && [ -n "$vm_id" ] \
  || fail "could not read Terraform outputs from '$config_dir'; pass --bastion-name, --resource-group and --vm-id"
#endregion

#region certificate
key_dir="$HOME/.ssh/az_ssh_config/$host_alias"
key_file="$key_dir/id_rsa"
cert_file="$key_dir/id_rsa-cert.pub"

mkdir -p "$key_dir"
chmod 700 "$HOME/.ssh" "$key_dir"

# Microsoft Entra ID issues OpenSSH certificates for RSA keys only.
if [ ! -f "$key_file" ]; then
  ssh-keygen -q -t rsa -b 4096 -N "" -C "$host_alias-entra" -f "$key_file"
fi

renew_cert() {
  az ssh cert --public-key-file "$key_file.pub" --file "$cert_file" --only-show-errors > /dev/null
}

echo "Requesting Microsoft Entra ID SSH certificate..."
renew_cert || fail "'az ssh cert' failed"

# The certificate principal is the Entra user name the VM expects (normally the UPN).
ssh_user="$(ssh-keygen -L -f "$cert_file" | awk '/Principals:/ {getline; gsub(/^[ \t]+|[ \t]+$/, ""); print; exit}')"
[ -n "$ssh_user" ] || fail "could not read the principal from '$cert_file'"
#endregion

#region ssh-config
ssh_config="$HOME/.ssh/config"
begin_marker="# BEGIN $host_alias (managed by connect-jumplinux2)"
end_marker="# END $host_alias (managed by connect-jumplinux2)"

touch "$ssh_config"
chmod 600 "$ssh_config"

tmp_config="$(mktemp)"
awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin { skip = 1; next }
  $0 == end { skip = 0; next }
  !skip { print }
' "$ssh_config" > "$tmp_config"

cat >> "$tmp_config" << EOF
$begin_marker
Host $host_alias
  HostName 127.0.0.1
  Port $local_port
  User $ssh_user
  IdentityFile "$key_file"
  CertificateFile "$cert_file"
  IdentitiesOnly yes
  HostKeyAlias $host_alias
$end_marker
EOF

cat "$tmp_config" > "$ssh_config"
rm -f "$tmp_config"
echo "Updated '$ssh_config' (Host $host_alias -> 127.0.0.1:$local_port as $ssh_user)."
#endregion

#region tunnel
renew_loop() {
  while sleep "$renew_seconds"; do
    if renew_cert; then
      echo "$(date '+%H:%M:%S') Renewed Microsoft Entra ID SSH certificate."
    else
      echo "$(date '+%H:%M:%S') Warning: certificate renewal failed; run 'az login' and restart this script." >&2
    fi
  done
}

renew_loop &
renew_pid=$!
# Stop the in-flight 'sleep' first so it isn't orphaned, then the loop itself.
trap 'pkill -P "$renew_pid" 2> /dev/null || true; kill "$renew_pid" 2> /dev/null || true' EXIT

echo "Opening Bastion tunnel to '$host_alias' on 127.0.0.1:$local_port. Keep this terminal open; press Ctrl+C to close."
echo "Connect with VS Code Remote-SSH (host '$host_alias') or 'ssh $host_alias'."
az network bastion tunnel \
  --name "$bastion_name" \
  --resource-group "$resource_group" \
  --target-resource-id "$vm_id" \
  --resource-port 22 \
  --port "$local_port" \
  --only-show-errors
#endregion
