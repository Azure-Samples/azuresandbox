#!/bin/bash

# Installs and registers the GitHub Actions self-hosted runner agent on the VM.
#
# This script is delivered to the VM as a cloud-init 'text/x-shellscript' part, so it runs once per
# instance after packages (azure-cli, terraform, powershell) have been installed. It is NOT a
# Terraform template: all deployment specific settings are read from the configuration file written
# by the companion cloud-config part (configure-github-runner.yaml), which keeps this script
# lintable by ShellCheck.
#
# The GitHub registration secret is never embedded in this script or in the VM custom data. It is
# read at provisioning time from Azure Key Vault using the VM managed identity, so it is never
# written to Terraform state.

set -euo pipefail

config_file=/etc/github-runner.conf

# Defaults, overridden by $config_file.
runner_url=""
runner_name=""
runner_group="Default"
runner_labels=""
runner_version=""
runner_user="githubrunner"
runner_home="/opt/actions-runner"
key_vault_name=""
token_secret_name=""
token_type="pat"
aad_tenant_id=""
vwan_sudoers="true"

log() {
    printf '%s configure-github-runner: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

# Retries transient failures rather than failing the whole provisioning run, e.g. the VM may boot
# before the managed identity role assignment has propagated or the key vault private endpoint is
# reachable, or while another process holds the apt lock.
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

read_secret() {
    github_token=$(az keyvault secret show \
        --vault-name "$key_vault_name" \
        --name "$token_secret_name" \
        --query value \
        --output tsv \
        --only-show-errors)

    [ -n "$github_token" ]
}

get_registration_token() {
    registration_token=$(curl -sSf -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$registration_api" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))')

    [ -n "$registration_token" ]
}

if [ ! -f "$config_file" ]; then
    fail "configuration file $config_file not found"
fi

# shellcheck source=/dev/null
. "$config_file"

for required in runner_url runner_name runner_version key_vault_name token_secret_name; do
    if [ -z "${!required}" ]; then
        fail "required setting '$required' is not set in $config_file"
    fi
done

if [ -f "$runner_home/.runner" ]; then
    log "runner is already configured at $runner_home, nothing to do..."
    exit 0
fi

log "Logging in to Azure using the VM managed identity..."
retry "Azure managed identity login" \
    az login --identity --allow-no-subscriptions --only-show-errors --output none

log "Reading secret '$token_secret_name' from key vault '$key_vault_name'..."
github_token=""
retry "Key vault secret read" read_secret

# A repository URL contains exactly one '/' after the github.com prefix, an organization URL none.
api_path=${runner_url#https://github.com/}

if [ "$(printf '%s' "$api_path" | tr -cd '/' | wc -c)" -eq 1 ]; then
    runner_scope="repository"
else
    runner_scope="organization"
fi

# A personal access token must be exchanged for a short lived runner registration token. A token
# supplied as a registration token is used as-is.
if [ "$token_type" = "pat" ]; then
    if [ "$runner_scope" = "repository" ]; then
        registration_api="https://api.github.com/repos/$api_path/actions/runners/registration-token"
    else
        registration_api="https://api.github.com/orgs/$api_path/actions/runners/registration-token"
    fi

    log "Exchanging personal access token for a runner registration token..."
    registration_token=""
    retry "Runner registration token request" get_registration_token
else
    registration_token="$github_token"
fi

github_token=""

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
if [ "$vwan_sudoers" = "true" ]; then
    log "Granting '$runner_user' command-scoped sudo for the vwan P2S VPN integration tests..."
    sudoers_file=/etc/sudoers.d/azuresandbox-github-runner

    cat > "$sudoers_file" << EOF
# Managed by cloud-init (configure-github-runner.sh). Do not edit by hand.
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
else
    log "Skipping vwan sudoers drop-in, var.github_runner_enable_vwan_sudoers is disabled..."
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
# the same time. It is idempotent, so retry rather than failing the whole provisioning run.
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

# Runner groups are an organization/enterprise feature. Passing --runnergroup when registering a
# repository level runner fails with "Could not find any self-hosted runner group named ...".
if [ "$runner_scope" = "organization" ] && [ -n "$runner_group" ]; then
    config_args+=(--runnergroup "$runner_group")
fi

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
