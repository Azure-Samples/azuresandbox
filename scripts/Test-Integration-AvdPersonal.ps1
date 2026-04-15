param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$StorageShareName,

    [Parameter(Mandatory = $true)]
    [string]$DomainName
)

#region functions
function Write-Log {
    param([string]$msg)
    $entry = "$(Get-Date -Format FileDateTimeUniversal) : $msg"
    $entry | Out-File -FilePath $script:logPath -Append -Force
    Write-Output $entry
}

function Write-TestResult {
    param(
        [string]$module,
        [string]$status,
        [string]$msg
    )
    Write-Log ("[MODULE:$module] [$status] $msg")
}
#endregion

#region main
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'integration'
$logDir = 'C:\unit-tests\integration'
$script:logPath = Join-Path $logDir 'Test-Integration-AvdPersonal.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: AVD personal session host on '$env:COMPUTERNAME'..."
Write-Log ("Parameters: KeyVaultName='$KeyVaultName' StorageAccountName='$StorageAccountName' StorageShareName='$StorageShareName' DomainName='$DomainName'")

$passed = 0
$failed = 0

# Test 1: DNS - Azure Files FQDN resolves to a private IP
try {
    $filesFqdn = "$StorageAccountName.file.core.windows.net"
    $dnsResult = Resolve-DnsName $filesFqdn -ErrorAction Stop
    $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

    if ($ip -match '^10\.') {
        Write-TestResult $moduleName 'PASS' "DNS: '$filesFqdn' resolves to private IP '$ip'"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "DNS: '$filesFqdn' resolved to '$ip' (expected private IP 10.x.x.x)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "DNS: '$filesFqdn' does not resolve"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: DNS - Key Vault FQDN resolves to a private IP
try {
    $kvFqdn = "$KeyVaultName.vault.azure.net"
    $dnsResult = Resolve-DnsName $kvFqdn -ErrorAction Stop
    $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

    if ($ip -match '^10\.') {
        Write-TestResult $moduleName 'PASS' "DNS: '$kvFqdn' resolves to private IP '$ip'"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "DNS: '$kvFqdn' resolved to '$ip' (expected private IP 10.x.x.x)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "DNS: '$kvFqdn' does not resolve"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: SMB - TCP port 445 reachable on Azure Files private endpoint
try {
    $filesFqdn = "$StorageAccountName.file.core.windows.net"
    $tcpTest = Test-NetConnection -ComputerName $filesFqdn -Port 445 -ErrorAction Stop

    if ($tcpTest.TcpTestSucceeded) {
        Write-TestResult $moduleName 'PASS' ("SMB: TCP port 445 reachable on '$filesFqdn' (remote IP: " + $tcpTest.RemoteAddress + ")")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "SMB: TCP port 445 not reachable on '$filesFqdn'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "SMB: Failed to test TCP connectivity to '$filesFqdn':445"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: Key Vault - HTTPS port 443 reachable
try {
    $kvFqdn = "$KeyVaultName.vault.azure.net"
    $tcpTest = Test-NetConnection -ComputerName $kvFqdn -Port 443 -ErrorAction Stop

    if ($tcpTest.TcpTestSucceeded) {
        Write-TestResult $moduleName 'PASS' ("Key Vault: TCP port 443 reachable on '$kvFqdn' (remote IP: " + $tcpTest.RemoteAddress + ")")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Key Vault: TCP port 443 not reachable on '$kvFqdn'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Key Vault: Failed to test TCP connectivity to '$kvFqdn':443"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Acquire managed identity token from IMDS for Key Vault access
$kvToken = $null
try {
    $tokenUri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net'
    $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Headers @{ Metadata = 'true' } -ErrorAction Stop
    $kvToken = $tokenResponse.access_token
    Write-Log "Acquired managed identity token for Key Vault (expires: $($tokenResponse.expires_on))"
}
catch {
    Write-TestResult $moduleName 'FAIL' "Key Vault: Failed to acquire managed identity token from IMDS"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: Key Vault - Retrieve adminuser secret via REST API
$smbAdminUser = $null
$smbAdminPwd = $null

if ($kvToken) {
    try {
        $kvUri = "https://$KeyVaultName.vault.azure.net/secrets/adminuser?api-version=7.4"
        $secretResponse = Invoke-RestMethod -Uri $kvUri -Headers @{ Authorization = "Bearer $kvToken" } -ErrorAction Stop
        $smbAdminUser = $secretResponse.value

        if (-not [string]::IsNullOrEmpty($smbAdminUser)) {
            Write-TestResult $moduleName 'PASS' "Key Vault: Retrieved 'adminuser' secret (value='$smbAdminUser')"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Key Vault: 'adminuser' secret is empty"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Key Vault: Failed to retrieve 'adminuser' secret from '$KeyVaultName'"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "Key Vault: Skipped adminuser - no IMDS token"
    $failed++
}

# Test 6: Key Vault - Retrieve adminpassword secret via REST API
if ($kvToken) {
    try {
        $kvUri = "https://$KeyVaultName.vault.azure.net/secrets/adminpassword?api-version=7.4"
        $secretResponse = Invoke-RestMethod -Uri $kvUri -Headers @{ Authorization = "Bearer $kvToken" } -ErrorAction Stop
        $smbAdminPwd = $secretResponse.value

        if (-not [string]::IsNullOrEmpty($smbAdminPwd)) {
            Write-TestResult $moduleName 'PASS' ("Key Vault: Retrieved 'adminpassword' secret (length=" + $smbAdminPwd.Length + ")")
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Key Vault: 'adminpassword' secret is empty"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Key Vault: Failed to retrieve 'adminpassword' secret from '$KeyVaultName'"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "Key Vault: Skipped adminpassword - no IMDS token"
    $failed++
}

# Test 7: SMB - Azure Files read/write with explicit domain credentials
$smbTestPassed = $false
$smbTestReason = 'not attempted'

if ($smbAdminUser -and $smbAdminPwd -and $DomainName) {
    $domainUser = "$smbAdminUser@$DomainName"
    $filesFqdn = "$StorageAccountName.file.core.windows.net"
    $uncPath = "\\$filesFqdn\$StorageShareName"
    $drive = 'Z'

    try {
        # Map drive with explicit credentials (UPN format for Entra ID joined hosts)
        $netUseOutput = & net use "${drive}:" $uncPath /user:$domainUser $smbAdminPwd /persistent:no 2>&1
        if ($LASTEXITCODE -ne 0) {
            $smbTestReason = "SMB: net use failed (exit code $LASTEXITCODE): $netUseOutput"
        }
        else {
            $testFile = "${drive}:\.unit-test-$env:COMPUTERNAME"
            $content = 'unit-test-' + (Get-Date -Format FileDateTime)

            try {
                Set-Content -Path $testFile -Value $content -ErrorAction Stop
                $readBack = Get-Content -Path $testFile -ErrorAction Stop
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue

                if ($readBack -eq $content) {
                    $smbTestPassed = $true
                    $smbTestReason = "SMB: Read/write test succeeded on '$uncPath' as '$domainUser'"
                }
                else {
                    $smbTestReason = "SMB: Content mismatch (wrote '$content', read '$readBack')"
                }
            }
            catch {
                $smbTestReason = "SMB: File operation failed: $_"
            }
            finally {
                & net use "${drive}:" /delete /yes 2>&1 | Out-Null
            }
        }
    }
    catch {
        $smbTestReason = "SMB: Failed to execute net use: $_"
        & net use "${drive}:" /delete /yes 2>&1 | Out-Null
    }
}
else {
    if (-not $DomainName) { $smbTestReason = 'SMB: Skipped - DomainName parameter is empty' }
    elseif (-not $smbAdminUser -or -not $smbAdminPwd) { $smbTestReason = 'SMB: Skipped - credentials not available from Key Vault' }
}

if ($smbTestPassed) {
    Write-TestResult $moduleName 'PASS' $smbTestReason
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' $smbTestReason
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
