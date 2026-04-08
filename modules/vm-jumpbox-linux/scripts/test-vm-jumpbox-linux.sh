#!/bin/bash

# Unit tests for vm-jumpbox-linux module
# Runs on jumplinux1 via Invoke-AzVMRunCommand -CommandId RunShellScript

module_name='vm-jumpbox-linux'
log_dir="/var/log/unit-tests/$module_name"
log_file="$log_dir/test-vm-jumpbox-linux.log"
passed=0
failed=0

mkdir -p "$log_dir"
: > "$log_file"

write_log() {
    local entry
    entry="$(date +"%Y-%m-%d %H:%M:%S %Z") : $1"
    echo "$entry" >> "$log_file"
    echo "$entry"
}

write_test_result() {
    local status="$1"
    local msg="$2"
    write_log "[MODULE:$module_name] [$status] $msg"
}

write_log "Starting unit tests for module '$module_name' on '$(hostname)'..."

# Read configuration from cloud-init generated config file
config_file='/etc/azuresandbox-conf.json'
if [ ! -f "$config_file" ]; then
    write_test_result 'FAIL' "Config file '$config_file' not found"
    failed=$((failed + 1))
    total=$((passed + failed))
    write_test_result 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
    exit 0
fi

adds_domain_name=$(jp -f "$config_file" -u adds_domain_name 2>/dev/null)
storage_account_name=$(jp -f "$config_file" -u storage_account_name 2>/dev/null)
storage_share_name=$(jp -f "$config_file" -u storage_share_name 2>/dev/null)
key_vault_name=$(jp -f "$config_file" -u key_vault_name 2>/dev/null)

write_log "Config: domain='$adds_domain_name' storage_account='$storage_account_name' share='$storage_share_name' key_vault='$key_vault_name'"

# Test 1: cloud-init status is done
cloud_init_status=$(cloud-init status 2>/dev/null | grep -oP '(?<=status: )\S+')
if [ "$cloud_init_status" = "done" ]; then
    write_test_result 'PASS' "cloud-init: status is 'done'"
    passed=$((passed + 1))
else
    write_test_result 'FAIL' "cloud-init: status is '$cloud_init_status' (expected 'done')"
    failed=$((failed + 1))
fi

# Test 2: AD domain joined (winbind trust check)
if wbinfo -t &>/dev/null; then
    write_test_result 'PASS' "AD: Domain trust check succeeded (wbinfo -t)"
    passed=$((passed + 1))
else
    write_test_result 'FAIL' "AD: Domain trust check failed (wbinfo -t)"
    failed=$((failed + 1))
fi

# Test 3: DNS - Resolve domain name
if [ -n "$adds_domain_name" ]; then
    dns_result=$(getent hosts "$adds_domain_name" 2>/dev/null)
    if [ -n "$dns_result" ]; then
        dns_ip=$(echo "$dns_result" | awk '{print $1}' | head -1)
        write_test_result 'PASS' "DNS: '$adds_domain_name' resolves to '$dns_ip'"
        passed=$((passed + 1))
    else
        write_test_result 'FAIL' "DNS: '$adds_domain_name' does not resolve"
        failed=$((failed + 1))
    fi
else
    write_test_result 'FAIL' "DNS: Skipped - domain name not available from config"
    failed=$((failed + 1))
fi

# Test 4: Software - Azure CLI
if command -v az &>/dev/null; then
    az_version=$(az version --output tsv 2>/dev/null | head -1 | awk '{print $1}')
    write_test_result 'PASS' "Software: az CLI installed (version: $az_version)"
    passed=$((passed + 1))
else
    write_test_result 'FAIL' "Software: az CLI not found"
    failed=$((failed + 1))
fi

# Test 5: Software - PowerShell
if command -v pwsh &>/dev/null; then
    pwsh_version=$(pwsh --version 2>/dev/null)
    write_test_result 'PASS' "Software: pwsh installed ($pwsh_version)"
    passed=$((passed + 1))
else
    write_test_result 'FAIL' "Software: pwsh not found"
    failed=$((failed + 1))
fi

# Test 6: Software - Terraform
if command -v terraform &>/dev/null; then
    tf_version=$(terraform --version 2>/dev/null | head -1)
    write_test_result 'PASS' "Software: terraform installed ($tf_version)"
    passed=$((passed + 1))
else
    write_test_result 'FAIL' "Software: terraform not found"
    failed=$((failed + 1))
fi

# Test 7: Software - Docker
if command -v docker &>/dev/null; then
    docker_version=$(docker --version 2>/dev/null)
    write_test_result 'PASS' "Software: docker installed ($docker_version)"
    passed=$((passed + 1))
else
    write_test_result 'FAIL' "Software: docker not found"
    failed=$((failed + 1))
fi

# Test 8: Software - Helm
if command -v helm &>/dev/null; then
    helm_version=$(helm version --short 2>/dev/null)
    write_test_result 'PASS' "Software: helm installed ($helm_version)"
    passed=$((passed + 1))
else
    write_test_result 'FAIL' "Software: helm not found"
    failed=$((failed + 1))
fi

# Acquire Kerberos TGT for CIFS tests
# RunShellScript runs as root which has no domain credentials.
# Uses managed identity to fetch admin credentials from Key Vault,
# same pattern as configure-vm-jumpbox-linux.sh
cifs_mount="/fileshares/$storage_share_name"
has_krb_ticket=false

if [ -n "$key_vault_name" ] && [ -n "$adds_domain_name" ]; then
    adds_realm_name=$(echo "$adds_domain_name" | tr '[:lower:]' '[:upper:]')
    write_log "Acquiring Kerberos TGT via managed identity + Key Vault '$key_vault_name'..."

    access_token=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true | jp -u 'access_token' 2>/dev/null)

    if [ -n "$access_token" ]; then
        admin_username=$(curl -s -X GET -H "Authorization: Bearer $access_token" -H "Content-Type: application/json" \
            "https://$key_vault_name.vault.azure.net/secrets/adminuser?api-version=7.2" | jp -u 'value' 2>/dev/null)
        admin_password=$(curl -s -X GET -H "Authorization: Bearer $access_token" -H "Content-Type: application/json" \
            "https://$key_vault_name.vault.azure.net/secrets/adminpassword?api-version=7.2" | jp -u 'value' 2>/dev/null)

        if [ -n "$admin_username" ] && [ -n "$admin_password" ]; then
            if echo "$admin_password" | kinit "${admin_username}@${adds_realm_name}" &>/dev/null; then
                has_krb_ticket=true
                write_log "Kerberos TGT acquired for '${admin_username}@${adds_realm_name}'"
            else
                write_log "WARNING: kinit failed for '${admin_username}@${adds_realm_name}'"
            fi
        else
            write_log "WARNING: Failed to retrieve admin credentials from Key Vault"
        fi
        # Clear sensitive variables
        admin_password=''
        access_token=''
    else
        write_log "WARNING: Failed to get managed identity access token"
    fi
else
    write_log "WARNING: key_vault_name or adds_domain_name not available, skipping Kerberos TGT"
fi

# Test 9: CIFS - Azure Files mount point accessible
if [ -n "$storage_share_name" ]; then
    if [ "$has_krb_ticket" = true ]; then
        if [ -d "$cifs_mount" ]; then
            write_test_result 'PASS' "CIFS: Mount point '$cifs_mount' is accessible"
            passed=$((passed + 1))
        else
            write_test_result 'FAIL' "CIFS: Mount point '$cifs_mount' not accessible (autofs mount may have failed)"
            failed=$((failed + 1))
        fi
    else
        write_test_result 'FAIL' "CIFS: Skipped mount test - no Kerberos TGT available"
        failed=$((failed + 1))
    fi
else
    write_test_result 'FAIL' "CIFS: Skipped - storage_share_name not available from config"
    failed=$((failed + 1))
fi

# Test 10: CIFS - Read/write test
if [ -n "$storage_share_name" ] && [ "$has_krb_ticket" = true ] && [ -d "$cifs_mount" ]; then
    test_file="$cifs_mount/.unit-test-$(hostname)-$$"
    test_content="unit-test-$(date +%s)"

    if echo "$test_content" > "$test_file" 2>/dev/null; then
        read_back=$(cat "$test_file" 2>/dev/null)
        rm -f "$test_file" 2>/dev/null

        if [ "$read_back" = "$test_content" ]; then
            write_test_result 'PASS' "CIFS: Read/write test succeeded on '$cifs_mount'"
            passed=$((passed + 1))
        else
            write_test_result 'FAIL' "CIFS: Read-back mismatch on '$cifs_mount'"
            failed=$((failed + 1))
        fi
    else
        write_test_result 'FAIL' "CIFS: Write failed on '$cifs_mount'"
        failed=$((failed + 1))
    fi
else
    if [ "$has_krb_ticket" != true ]; then
        write_test_result 'FAIL' "CIFS: Skipped read/write - no Kerberos TGT available"
    else
        write_test_result 'FAIL' "CIFS: Skipped read/write - mount point not available"
    fi
    failed=$((failed + 1))
fi

# Clean up Kerberos ticket
if [ "$has_krb_ticket" = true ]; then
    kdestroy &>/dev/null
    write_log "Kerberos TGT destroyed"
fi

# Summary
total=$((passed + failed))
write_test_result 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
