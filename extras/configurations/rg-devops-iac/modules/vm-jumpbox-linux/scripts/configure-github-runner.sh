#!/bin/bash

# Installs and registers the GitHub Actions self-hosted runner agent on the VM.
#
# This script is run as root by the ConfigureGitHubRunner managed Run Command, after cloud-init has
# finished and the VM extensions are installed. It is NOT a Terraform template: deployment specific
# settings arrive as Run Command parameters, which Linux exposes to the script as environment
# variables, so this script stays lintable by ShellCheck.
#
# The runner registration token arrives as the protected parameter RUNNER_TOKEN. Terraform passes it through the
# write-only azapi sensitive_body argument, so it is never written to Terraform state, the saved plan,
# the VM custom data or Azure Key Vault.

set -euo pipefail

runner_url="${RUNNER_URL:-}"
runner_name="${RUNNER_NAME:-}"
runner_labels="${RUNNER_LABELS:-}"
runner_version="${RUNNER_VERSION:-}"
runner_user="githubrunner"
runner_home="${RUNNER_HOME:-/opt/actions-runner}"
aad_tenant_id="${AAD_TENANT_ID:-}"

registration_token="${RUNNER_TOKEN:-}"
unset RUNNER_TOKEN

log() {
    printf '%s configure-github-runner: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

# Retries transient failures rather than failing the whole registration, e.g. another process
# holding the apt lock.
retry() {
    local description="$1"
    shift
    local attempt=1
    local max_attempts=30

    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            fail "$description failed after $attempt attempts"
        fi

        log "$description failed (attempt $attempt of $max_attempts), retrying in 20 seconds..."
        attempt=$((attempt + 1))
        sleep 20
    done
}

[ -n "$runner_url" ] || fail "required parameter 'RUNNER_URL' is not set"
[ -n "$runner_name" ] || fail "required parameter 'RUNNER_NAME' is not set"
[ -n "$runner_version" ] || fail "required parameter 'RUNNER_VERSION' is not set"

# The Run Command runs again whenever Azure re-applies it (e.g. a changed parameter or script), usually
# without RUNNER_TOKEN. A registered runner is left as-is.
if [ -f "$runner_home/.runner" ]; then
    log "runner is already configured at $runner_home, nothing to do..."
    exit 0
fi

if [ -z "$registration_token" ]; then
    fail "RUNNER_TOKEN is empty and the runner is not registered. Set TF_VAR_github_runner_token, increment github_runner_token_version and apply again."
fi

if id -u "$runner_user" > /dev/null 2>&1; then
    log "Service account '$runner_user' already exists..."
else
    log "Creating service account '$runner_user'..."
    useradd --system --create-home --shell /bin/bash "$runner_user"
fi

# The vwan integration tests (scripts/Test-Integration-VwanConnectivity.ps1) establish a P2S VPN
# tunnel, which requires root to create the tun device and rewrite the routing table. The runner
# service account is unprivileged, so grant command-scoped NOPASSWD sudo for exactly the binaries
# those tests invoke. This mirrors the /etc/sudoers.d/azuresandbox-vwan drop-in used on interactive
# Terraform execution environments.
log "Granting '$runner_user' command-scoped sudo for the vwan P2S VPN integration tests..."
sudoers_file=/etc/sudoers.d/azuresandbox-github-runner

cat > "$sudoers_file" << EOF
# Managed by the ConfigureGitHubRunner Run Command (configure-github-runner.sh). Do not edit by hand.
# Command-scoped NOPASSWD sudo for the privileged binaries invoked by
# scripts/Test-Integration-VwanConnectivity.ps1 when the vwan P2S VPN integration
# tests run on this self-hosted runner.
$runner_user ALL=(root) NOPASSWD: /usr/sbin/openvpn, /usr/bin/cat, /usr/bin/tail, /usr/bin/kill, /usr/bin/pkill
EOF

chown root:root "$sudoers_file"
chmod 0440 "$sudoers_file"

# A malformed drop-in breaks sudo for every user, so validate and discard it if invalid.
if ! visudo -cf "$sudoers_file" > /dev/null; then
    rm -f "$sudoers_file"
    fail "generated sudoers file $sudoers_file is invalid and has been removed"
fi

# The Sandbox deployment workflow's preflight installs a Terraform CLI version that satisfies the
# deployed branch's required_version when the installed one doesn't. Granting 'apt-get install' through
# sudo would let the caller add arbitrary packages, because sudoers wildcards match spaces, so grant a
# root-owned wrapper that accepts only a validated X.Y.Z and installs only the HashiCorp terraform package.
terraform_installer=/usr/local/sbin/azuresandbox-install-terraform
log "Installing Terraform installer wrapper $terraform_installer..."
cat > "$terraform_installer" << 'EOF'
#!/bin/bash
# Managed by the ConfigureGitHubRunner Run Command (configure-github-runner.sh). Do not edit by hand.
# Installs one version of the terraform package from the HashiCorp apt repository, upgrading or
# downgrading the installed one. The GitHub Actions runner service account may run only this
# command through sudo. Usage: azuresandbox-install-terraform X.Y.Z
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

if [ "$#" -ne 1 ] || ! [[ "$1" =~ ^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$ ]]; then
    echo "usage: azuresandbox-install-terraform X.Y.Z" >&2
    exit 2
fi
version="$1"

# The VM may have just been started, when apt-daily and unattended-upgrades can hold the dpkg lock.
lock=(-o DPkg::Lock::Timeout=600)

# Refresh only the HashiCorp repository's package list.
apt-get "${lock[@]}" -qq \
    -o Dir::Etc::sourcelist=sources.list.d/hashicorp.list \
    -o Dir::Etc::sourceparts=- \
    -o APT::Get::List-Cleanup=0 \
    update

package_version=$(apt-cache madison terraform | awk -v prefix="$version-" 'index($3, prefix) == 1 { print $3; exit }')
if [ -z "$package_version" ]; then
    echo "terraform $version is not available from the HashiCorp apt repository." >&2
    exit 1
fi

apt-get "${lock[@]}" -qq install -y --allow-downgrades --no-install-recommends "terraform=$package_version"
terraform version
EOF
chown root:root "$terraform_installer"
chmod 0755 "$terraform_installer"

terraform_sudoers=/etc/sudoers.d/azuresandbox-github-runner-terraform
log "Granting '$runner_user' sudo for $terraform_installer only..."
cat > "$terraform_sudoers" << EOF
# Managed by the ConfigureGitHubRunner Run Command (configure-github-runner.sh). Do not edit by hand.
# Lets the Sandbox deployment workflow install a Terraform CLI version that satisfies the
# deployed branch's required_version. The wrapper validates its only argument.
$runner_user ALL=(root) NOPASSWD: $terraform_installer
EOF
chown root:root "$terraform_sudoers"
chmod 0440 "$terraform_sudoers"

# A malformed drop-in breaks sudo for every user, so validate and discard it if invalid.
if ! visudo -cf "$terraform_sudoers" > /dev/null; then
    rm -f "$terraform_sudoers"
    fail "generated sudoers file $terraform_sudoers is invalid and has been removed"
fi

log "Downloading GitHub Actions runner v$runner_version..."
install -d -o "$runner_user" -g "$runner_user" -m 0755 "$runner_home"
tarball="actions-runner-linux-x64-$runner_version.tar.gz"
curl -sSfL -o "/tmp/$tarball" \
    "https://github.com/actions/runner/releases/download/v$runner_version/$tarball"
tar -xzf "/tmp/$tarball" -C "$runner_home"
rm -f "/tmp/$tarball"
chown -R "$runner_user:$runner_user" "$runner_home"

# installdependencies.sh calls apt-get without waiting for the apt/dpkg locks, so it fails if another
# process (e.g. unattended-upgrades, apt-daily or a policy deployed VM extension) is using apt at
# the same time. It is idempotent, so retry rather than failing the whole registration.
log "Installing GitHub Actions runner dependencies..."
retry "Runner dependency installation" "$runner_home/bin/installdependencies.sh"

# svc.sh sources this file into the runner service environment, which makes the pre-installed
# toolchain and managed identity based azurerm provider auth available to every job.
log "Writing runner service environment file '$runner_home/.env'..."
cat > "$runner_home/.env" << EOF
ARM_USE_MSI=true
ARM_TENANT_ID=$aad_tenant_id
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
chown "$runner_user:$runner_user" "$runner_home/.env"
chmod 0640 "$runner_home/.env"

log "Registering runner '$runner_name' with '$runner_url'..."
cd "$runner_home"

config_args=(
    --unattended
    --replace
    --url "$runner_url"
    --token "$registration_token"
    --name "$runner_name"
    --work "$runner_home/_work"
)

if [ -n "$runner_labels" ]; then
    config_args+=(--labels "$runner_labels")
fi

sudo -u "$runner_user" -- "$runner_home/config.sh" "${config_args[@]}"

registration_token=""

log "Installing and starting the GitHub Actions runner service..."
"$runner_home/svc.sh" install "$runner_user"
"$runner_home/svc.sh" start

log "GitHub Actions runner registration complete..."
exit 0
