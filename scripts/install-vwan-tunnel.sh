#!/bin/bash

# Installs the vwan P2S VPN test wrapper (scripts/vwan-tunnel.sh) as a root-owned command and, with
# --user, grants that user passwordless sudo for it only. Use it on a developer workstation or a
# self-hosted runner so the vwan integration test can run unattended as a non-root user. Root users
# and users who answer a sudo password prompt don't need it.
#
# Usage: sudo ./scripts/install-vwan-tunnel.sh [--user NAME] [--source PATH]
#   --user NAME    Writes /etc/sudoers.d/azuresandbox-vwan, granting NAME passwordless sudo for the
#                  installed wrapper only. Replaces the file if it exists.
#   --source PATH  Wrapper to install. Defaults to vwan-tunnel.sh next to this script.
#
# Safe to re-run, e.g. after pulling a new version of the wrapper.

set -euo pipefail
umask 022
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

install_dir=/usr/local/libexec/azuresandbox
install_path="$install_dir/vwan-tunnel"
sudoers_file=/etc/sudoers.d/azuresandbox-vwan

user_name=''
source_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vwan-tunnel.sh"

usage() {
    echo "usage: sudo $0 [--user NAME] [--source PATH]" >&2
    exit 2
}

fail() {
    echo "install-vwan-tunnel: $*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)
            [ "$#" -ge 2 ] || usage
            user_name="$2"
            shift 2
            ;;
        --source)
            [ "$#" -ge 2 ] || usage
            source_path="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

[ "$(id -u)" -eq 0 ] || fail "must run as root (use sudo)"
[ -f "$source_path" ] || fail "wrapper not found at $source_path"
bash -n "$source_path" || fail "$source_path isn't a valid bash script"

user_id=''
if [ -n "$user_name" ]; then
    user_id=$(id -u "$user_name" 2> /dev/null) || fail "user '$user_name' doesn't exist"
    [ "$user_id" -ne 0 ] || fail "--user isn't needed for root"
fi

install -d -o 0 -g 0 -m 0755 "$install_dir"

# Passwordless sudo is only as safe as the path it points to: if the user can write to the file or any
# directory above it, they can replace the wrapper.
dir="$install_dir"
while [ "$dir" != / ]; do
    if [ -L "$dir" ] || [ -z "$(find "$dir" -maxdepth 0 -user 0 ! -perm -g+w ! -perm -o+w 2> /dev/null)" ]; then
        fail "$dir must be a root-owned directory that only root can write to"
    fi
    dir=$(dirname "$dir")
done

install -o 0 -g 0 -m 0755 "$source_path" "$install_path"
echo "Installed $install_path (interface version $("$install_path" version))."

if [ -n "$user_name" ]; then
    [ -d /etc/sudoers.d ] || fail "/etc/sudoers.d doesn't exist"
    command -v visudo > /dev/null 2>&1 || fail "visudo not found"

    # Validate a temporary file first: a malformed drop-in breaks sudo for every user.
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT
    cat > "$temp_file" << EOF
# Managed by scripts/install-vwan-tunnel.sh. Re-run it to change this file.
# Lets $user_name run the vwan P2S VPN integration test wrapper as root without a password.
#$user_id ALL=(root) NOPASSWD: $install_path
EOF
    visudo -cf "$temp_file" > /dev/null || fail "generated sudoers file is invalid; $sudoers_file not changed"
    install -o 0 -g 0 -m 0440 "$temp_file" "$sudoers_file"
    echo "Granted '$user_name' passwordless sudo for $install_path in $sudoers_file."
fi
