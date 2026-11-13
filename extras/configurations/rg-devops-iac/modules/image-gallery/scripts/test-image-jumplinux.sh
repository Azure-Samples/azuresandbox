#!/bin/bash

# Validates the jumplinux image on the Azure VM Image Builder build VM, after customization and before the image is
# deprovisioned and distributed. Any failed check exits non-zero, which stops the build, because the image template
# sets continueDistributeOnFailure = false. Must run as root.
#
# Checks:
#   * Every package passed as an argument is installed. The image template passes the 'packages' array from the shared
#     install script (modules/vm-jumpbox-linux/scripts/install-vm-jumpbox-linux-packages.sh).
#   * The main jumpbox tools are on the PATH.
#   * No security upgrades are pending.
#
# Usage: test-image-jumplinux.sh PACKAGE [PACKAGE...]

set -euo pipefail

if [ "$#" -eq 0 ]; then
  printf 'Usage: %s PACKAGE [PACKAGE...]\n' "$0" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  printf 'Error: %s must run as root.\n' "$0" >&2
  exit 1
fi

failed=0

log() {
  printf '%s : %s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$1"
}

check() {
  local passed=$1 message=$2
  if [ "$passed" = true ]; then
    log "[PASS] $message"
  else
    log "[FAIL] $message"
    failed=$((failed + 1))
  fi
}

log "Running '$0'..."

# Packages
for package in "$@"; do
  if [ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" = 'install ok installed' ]; then
    check true "Package '$package' is installed"
  else
    check false "Package '$package' is not installed"
  fi
done

# Tools
for tool in az docker helm pwsh terraform; do
  if command -v "$tool" >/dev/null 2>&1; then
    check true "'$tool' is on the PATH"
  else
    check false "'$tool' is not on the PATH"
  fi
done

# Pending security upgrades
export DEBIAN_FRONTEND=noninteractive
if apt-get -q -o DPkg::Lock::Timeout=600 update >/dev/null; then
  pending=$(apt-get -s -o Debug::NoLocking=1 dist-upgrade | grep -E '^Inst .*-security' || true)
  if [ -z "$pending" ]; then
    check true 'No security upgrades are pending'
  else
    check false "Security upgrades are pending: $(printf '%s' "$pending" | awk '{print $2}' | paste -sd ' ' -)"
  fi
else
  check false "Couldn't update the apt package lists"
fi

if [ "$failed" -gt 0 ]; then
  log "Image failed $failed check(s)."
  exit 1
fi

log 'Image passed all checks.'
