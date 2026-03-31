param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$StorageShareName
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

$moduleName = 'vnet-app'
$logDir = "C:\unit-tests\$moduleName"
$script:logPath = Join-Path $logDir 'Test-VnetApp.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting unit tests for module '$moduleName' on '$env:COMPUTERNAME'..."
Write-Log ("Parameters: KeyVaultName='$KeyVaultName' StorageAccountName='$StorageAccountName' StorageShareName='$StorageShareName'")

$passed = 0
$failed = 0
$domainName = $null

# Discover domain name from this machine
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $domainName = $cs.Domain
    Write-Log "Detected domain: '$domainName'"
}
catch {
    Write-Log "WARNING: Could not detect domain name via CIM: $_"
}

# Test 1: AD - Storage account computer object exists in AD
try {
    $stComputer = Get-ADComputer -Identity $StorageAccountName -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' ("AD: Storage account computer object '$StorageAccountName' exists (DN: " + $stComputer.DistinguishedName + ")")
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "AD: Storage account computer object '$StorageAccountName' not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: AD - This machine's computer object exists in AD
try {
    $myComputer = Get-ADComputer -Identity $env:COMPUTERNAME -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' ("AD: Computer object '$env:COMPUTERNAME' exists (DN: " + $myComputer.DistinguishedName + ")")
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "AD: Computer object '$env:COMPUTERNAME' not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: DNS - A record for this VM in the domain zone
if ($domainName) {
    try {
        $fqdn = "$env:COMPUTERNAME.$domainName"
        $dnsResult = Resolve-DnsName $fqdn -ErrorAction Stop
        $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress
        Write-TestResult $moduleName 'PASS' "DNS: '$fqdn' resolves to '$ip'"
        $passed++
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "DNS: '$fqdn' does not resolve"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "DNS: Skipped - domain name not available"
    $failed++
}

# Test 4: DNS - Azure Files FQDN resolves to a private IP
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

# Test 5: Key Vault - Connect via managed identity
$azConnected = $false
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $azConnected = $true
    Write-TestResult $moduleName 'PASS' "Key Vault: Connected to Azure via managed identity"
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "Key Vault: Failed to connect via managed identity"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 6: Key Vault - Retrieve adminuser secret
if ($azConnected) {
    try {
        $adminUser = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminuser' -AsPlainText -ErrorAction Stop

        if (-not [string]::IsNullOrEmpty($adminUser)) {
            Write-TestResult $moduleName 'PASS' "Key Vault: Retrieved 'adminuser' secret (value='$adminUser')"
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
    Write-TestResult $moduleName 'FAIL' "Key Vault: Skipped adminuser - managed identity not connected"
    $failed++
}

# Test 7: Key Vault - Retrieve adminpassword secret
if ($azConnected) {
    try {
        $adminPwd = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminpassword' -AsPlainText -ErrorAction Stop

        if (-not [string]::IsNullOrEmpty($adminPwd)) {
            Write-TestResult $moduleName 'PASS' ("Key Vault: Retrieved 'adminpassword' secret (length=" + $adminPwd.Length + ")")
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
    Write-TestResult $moduleName 'FAIL' "Key Vault: Skipped adminpassword - managed identity not connected"
    $failed++
}

# Disconnect Azure context
if ($azConnected) {
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}
}

# Test 8: Windows Features - RSAT features installed
$requiredFeatures = @('RSAT-ADDS', 'RSAT-DNS-Server')
$allFeaturesInstalled = $true
$featureDetails = @()

foreach ($featureName in $requiredFeatures) {
    $feature = Get-WindowsFeature -Name $featureName -ErrorAction SilentlyContinue
    if ($feature -and $feature.InstallState -eq 'Installed') {
        $featureDetails += "$featureName=Installed"
    }
    else {
        $featureDetails += "$featureName=Missing"
        $allFeaturesInstalled = $false
    }
}

if ($allFeaturesInstalled) {
    Write-TestResult $moduleName 'PASS' ("Windows Features: All required features installed ($($featureDetails -join ', '))")
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' ("Windows Features: One or more features missing ($($featureDetails -join ', '))")
    $failed++
}

# Test 9: Software - Visual Studio Code installed
$vscodePath = 'C:\Program Files\Microsoft VS Code\Code.exe'
if (Test-Path $vscodePath) {
    $vscodeVersion = (Get-Item $vscodePath).VersionInfo.ProductVersion
    Write-TestResult $moduleName 'PASS' "Software: Visual Studio Code installed (version: $vscodeVersion)"
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' "Software: Visual Studio Code not found at '$vscodePath'"
    $failed++
}

# Test 10: Software - SQL Server Management Studio installed
$ssmsPath = Get-ChildItem 'C:\Program Files\Microsoft SQL Server Management Studio*\Release\Common7\IDE\Ssms.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($ssmsPath) {
    $ssmsVersion = $ssmsPath.VersionInfo.ProductVersion
    Write-TestResult $moduleName 'PASS' ("Software: SSMS installed at '" + $ssmsPath.FullName + "' (version: $ssmsVersion)")
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' "Software: SQL Server Management Studio not found"
    $failed++
}

# Test 11: Software - MySQL Workbench installed
$mysqlWbPath = Get-ChildItem 'C:\Program Files\MySQL\MySQL Workbench*\MySQLWorkbench.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($mysqlWbPath) {
    $mysqlWbVersion = $mysqlWbPath.VersionInfo.ProductVersion
    Write-TestResult $moduleName 'PASS' ("Software: MySQL Workbench installed at '" + $mysqlWbPath.FullName + "' (version: $mysqlWbVersion)")
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' "Software: MySQL Workbench not found"
    $failed++
}

# Test 12: SMB - TCP port 445 reachable on Azure Files private endpoint
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

# Test 13: SMB - Azure Files read/write with domain credentials
# RunPowerShellScript runs as SYSTEM which has no domain Kerberos ticket.
# Use a scheduled task to run as the domain admin (same pattern as Invoke-AzureFilesConfiguration.ps1).
# Success/failure is determined by the task's exit code (0 = pass, non-zero = fail).
$smbTestPassed = $false
$smbTestReason = 'not attempted'
$taskName = 'UnitTest-SMB-ReadWrite'

# Get domain credentials via managed identity + Key Vault
$smbAdminUser = $null
$smbAdminPwd = $null

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null

    $smbAdminUser = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminuser' -AsPlainText -ErrorAction Stop
    $smbAdminPwd = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminpassword' -AsPlainText -ErrorAction Stop

    Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
}
catch {
    $smbTestReason = "Failed to retrieve credentials from Key Vault: $_"
}

if ($smbAdminUser -and $smbAdminPwd -and $domainName) {
    $domainNetbios = $domainName.Split('.')[0].ToUpper()
    $domainUser = "$domainNetbios\$smbAdminUser"
    $filesFqdn = "$StorageAccountName.file.core.windows.net"
    $uncPath = "\\$filesFqdn\$StorageShareName"

    # Clean up any previous task
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    # The task script: map drive, write, read-back, verify, clean up. Exit 0 on success, 1 on failure.
    $testScript = @"
`$ErrorActionPreference = 'Stop'
`$drive = 'Z'
try {
    net use `${drive}: $uncPath /persistent:no 2>&1 | Out-Null
    if (`$LASTEXITCODE -ne 0) { exit 1 }
    `$testFile = "`${drive}:\.unit-test-`$env:COMPUTERNAME"
    `$content = 'unit-test-' + (Get-Date -Format FileDateTime)
    Set-Content -Path `$testFile -Value `$content
    `$readBack = Get-Content -Path `$testFile
    Remove-Item `$testFile -Force -ErrorAction SilentlyContinue
    net use `${drive}: /delete /yes 2>&1 | Out-Null
    if (`$readBack -eq `$content) { exit 0 } else { exit 1 }
} catch {
    net use `${drive}: /delete /yes 2>&1 | Out-Null
    exit 1
}
"@

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($testScript))

    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NonInteractive -EncodedCommand " + $encodedCommand)
        Register-ScheduledTask -TaskName $taskName -Action $action -User $domainUser -Password $smbAdminPwd -RunLevel Highest -Force -ErrorAction Stop | Out-Null

        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop

        # Wait for the task to complete (max 60 seconds)
        $waited = 0
        do {
            Start-Sleep -Seconds 2
            $waited += 2
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        } while ($waited -lt 60 -and $taskInfo.LastTaskResult -eq 267009)

        $lastResult = $taskInfo.LastTaskResult

        if ($lastResult -eq 0) {
            $smbTestPassed = $true
            $smbTestReason = ("SMB: Read/write test succeeded on '" + $uncPath + "' as '" + $domainUser + "'")
        }
        else {
            $smbTestReason = ("SMB: Read/write test failed (task exit code: " + $lastResult + ")")
        }
    }
    catch {
        $smbTestReason = "SMB: Scheduled task failed: $_"
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}
else {
    if (-not $domainName) { $smbTestReason = 'SMB: Skipped - domain name not available' }
    elseif (-not $smbAdminUser -or -not $smbAdminPwd) { $smbTestReason = 'SMB: Skipped - credentials not available' }
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
#endregion
