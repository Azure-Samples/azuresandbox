#!/bin/bash

# Installs the jumpbox apt keyrings, repositories and packages. This is the single source for the
# jumpbox package set, shared by two callers:
#   * Deploy time: cloud-init runs it with no arguments (see main.tf).
#   * Image build: an Azure VM Image Builder template runs it with --image-build, which also runs
#     apt-get dist-upgrade so the image ships fully patched.
# The script is idempotent and must run as root.

# Note: This code has been tested on Ubuntu 24.04 LTS (Noble Numbat) and will not work on other Linux distros

set -euo pipefail

usage() {
  printf 'Usage: %s [--image-build]\n' "$0" >&2
  exit 1
}

image_build=false
case "${1:-}" in
  '') ;;
  --image-build) image_build=true ;;
  *) usage ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  printf 'Error: %s must run as root.\n' "$0" >&2
  exit 1
fi

log() {
  printf '%s : %s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$1"
}

export DEBIAN_FRONTEND=noninteractive

# Wait for other apt/dpkg users (e.g. first-boot apt-daily or unattended-upgrades) instead of failing.
apt_opts=(-y -q -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Retry key downloads to ride out transient DNS or network failures early in boot.
curl_opts=(-fsSL --retry 6 --retry-all-errors --retry-connrefused --retry-delay 2)

packages=(
  autofs
  azure-cli
  cifs-utils
  containerd.io
  docker-buildx-plugin
  docker-ce
  docker-ce-cli
  docker-compose-plugin
  helm
  jp
  keyutils
  krb5-config
  krb5-user
  libnss-winbind
  libpam-winbind
  notary
  ntp
  powershell
  python3-pip
  samba
  terraform
  winbind
)

log "Running '$0' (image build: $image_build)..."

# shellcheck disable=SC1091
release=$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")

#region keyrings
log "Installing apt keyrings..."
install -m 0755 -d /etc/apt/keyrings

install_keyring() {
  local url=$1 path=$2 dearmor=$3

  if [ -f "$path" ]; then
    log "Keyring '$path' already exists."
    return
  fi

  log "Downloading keyring '$path' from '$url'..."
  if [ "$dearmor" = true ]; then
    curl "${curl_opts[@]}" "$url" | gpg --batch --yes --dearmor -o "$path"
  else
    curl "${curl_opts[@]}" "$url" -o "$path"
  fi
  chmod a+r "$path"
}

install_keyring https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.asc false
install_keyring https://apt.releases.hashicorp.com/gpg /etc/apt/keyrings/hashicorp-archive-keyring.gpg true
install_keyring https://packages.buildkite.com/helm-linux/helm-debian/gpgkey /etc/apt/keyrings/helm.gpg true
install_keyring https://packages.microsoft.com/keys/microsoft.asc /etc/apt/keyrings/microsoft.gpg true
#endregion

#region repositories
log "Writing apt repository definitions..."

write_source() {
  local filename=$1 source=$2
  printf '%s\n' "$source" >"/etc/apt/sources.list.d/$filename"
  log "Wrote '/etc/apt/sources.list.d/$filename'."
}

write_source azure-cli.list "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $release main"
write_source docker.list "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $release stable"
write_source helm-stable-debian.list "deb [arch=amd64 signed-by=/etc/apt/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main"
write_source microsoft-prod.list "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/24.04/prod $release main"
write_source hashicorp.list "deb [arch=amd64 signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $release main"
#endregion

#region packages
log "Updating apt package lists..."
apt-get "${apt_opts[@]}" update

# A full dist-upgrade is deliberately not performed at deploy time. It is not required to install
# the packages below, it makes provisioning depend on every package on the image being
# downloadable from the Ubuntu mirror, and it triggers a mid-provisioning reboot when a new kernel
# is installed. Ongoing patching is handled by the sandbox's Azure Update Manager schedule. Image
# builds do upgrade, without a reboot, so a new kernel takes effect when a VM is first deployed
# from the image.
if [ "$image_build" = true ]; then
  log "Upgrading installed packages (dist-upgrade)..."
  apt-get "${apt_opts[@]}" dist-upgrade
fi

log "Installing packages: ${packages[*]}..."
apt-get "${apt_opts[@]}" install "${packages[@]}"
#endregion

log "'$0' complete."
