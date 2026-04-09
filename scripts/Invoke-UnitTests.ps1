#requires -Version 7.0
#requires -Modules Az.Accounts, Az.Compute, Az.Resources, Az.Sql, Az.Network, Az.PrivateDns, Az.MySql, Az.DesktopVirtualization

# Usage:
#   Step 1: Authenticate to Azure (one-time, persisted to ~/.Azure/)
#     From bash:       pwsh -Command 'Connect-AzAccount -UseDeviceAuthentication'
#     From PowerShell: Connect-AzAccount -UseDeviceAuthentication
#
#   Step 2: Run unit tests (all installed modules)
#     From bash:       pwsh -File ./scripts/Invoke-UnitTests.ps1
#     From PowerShell: .\scripts\Invoke-UnitTests.ps1
#
#   Step 2 (alt): Run unit tests for a single module
#     From bash:       pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vnet_shared
#     From PowerShell: .\scripts\Invoke-UnitTests.ps1 -Module vnet_app
#
#   Step 2 (alt): Run unit tests for a module and its associated integration tests
#     From bash:       pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vnet_app -Integration
#     From PowerShell: .\scripts\Invoke-UnitTests.ps1 -Module vm_mssql_win -Integration
#
#   Valid module names: vnet_shared, vnet_app, vm_jumpbox_linux, vm_mssql_win, mssql, mysql, vwan
#
# Prerequisites:
#   - PowerShell 7.x (pwsh) with Az.Accounts, Az.Compute, and Az.Resources modules installed
#   - Authenticated Azure session (see Step 1 above)
#   - Terraform CLI in PATH with initialized state in the repo root

param(
    [Parameter(Mandatory = $false)]
    [string]$Module,

    [Parameter(Mandatory = $false)]
    [switch]$Integration
)

#region functions
function Write-Log {
    param([string]$msg)
    $entry = "$(Get-Date -Format FileDateTimeUniversal) : $msg"
    $entry | Out-File -FilePath $script:logPath -Append -Force
    Write-Host $entry
}

function Exit-WithError {
    param([string]$msg)
    Write-Log "There was an exception during the process, please review..."
    Write-Log $msg
    exit 2
}

function Invoke-VMTest {
    param(
        [string]$ResourceGroupName,
        [string]$VMName,
        [string]$CommandId,
        [string]$ScriptPath,
        [hashtable]$Parameters,
        [string]$Label
    )

    $testResult = @{ Passed = 0; Failed = 1 }

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "[WARNING] Test script not found: $ScriptPath. Skipping."
        return $testResult
    }

    Write-Log "Executing test script on VM '$VMName' via run command..."

    try {
        $runParams = @{
            ResourceGroupName = $ResourceGroupName
            VMName            = $VMName
            CommandId         = $CommandId
            ScriptPath        = $ScriptPath
            ErrorAction       = 'Stop'
        }

        if ($Parameters.Count -gt 0) {
            $runParams['Parameter'] = $Parameters
        }

        $result = Invoke-AzVMRunCommand @runParams

        # Parse stdout and stderr
        # Windows (RunPowerShellScript) returns ComponentStatus/StdOut and ComponentStatus/StdErr
        # Linux (RunShellScript) returns a single ProvisioningState/succeeded with combined output
        $stdoutValue = $result.Value | Where-Object { $_.Code -like '*StdOut*' } | Select-Object -First 1
        $stderrValue = $result.Value | Where-Object { $_.Code -like '*StdErr*' } | Select-Object -First 1

        if (-not $stdoutValue) {
            # Linux RunShellScript: output is in the single ProvisioningState value
            $stdoutValue = $result.Value | Where-Object { $_.Code -like '*succeeded*' } | Select-Object -First 1
        }

        $stdout = $stdoutValue.Message
        $stderr = $stderrValue.Message

        if ($stdout) {
            $lines = $stdout -split "`n" | ForEach-Object { $_.Trim() } | Where-Object {
                $_ -and $_ -notmatch '^\[stdout\]$' -and $_ -notmatch '^\[stderr\]$' -and $_ -notmatch '^Enable succeeded:?$'
            }
            foreach ($line in $lines) {
                Write-Log $line
            }
        }

        if ($stderr) {
            Write-Log "[$Label] StdErr output:"
            $stderr -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
                Write-Log "  $_"
            }
        }

        # Parse summary line
        $summaryLine = ($stdout -split "`n") | Where-Object { $_ -match '\[SUMMARY\]' } | Select-Object -Last 1
        if ($summaryLine -match 'Passed:\s*(\d+)\s+Failed:\s*(\d+)\s+Total:\s*(\d+)') {
            $testResult = @{ Passed = [int]$Matches[1]; Failed = [int]$Matches[2] }
        }
        else {
            Write-Log "[WARNING] Could not parse summary line from '$Label'. Treating as failure."
        }
    }
    catch {
        Write-Log "[$Label] [FAIL] Failed to execute tests on VM '$VMName'"
        Write-Log "[$Label] [FAIL] Exception: $_"
    }

    return $testResult
}

function Invoke-LocalTest {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters,
        [string]$Label
    )

    $testResult = @{ Passed = 0; Failed = 1 }

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "[WARNING] Test script not found: $ScriptPath. Skipping."
        return $testResult
    }

    Write-Log "Executing test script locally..."

    try {
        # Stream output line-by-line so progress is visible in real time
        $collectedLines = [System.Collections.Generic.List[string]]::new()

        & $ScriptPath @Parameters 2>&1 | ForEach-Object {
            $line = "$_".Trim()
            if ($line) {
                Write-Log $line
                $collectedLines.Add($line)
            }
        }

        # Parse summary line
        $summaryLine = $collectedLines | Where-Object { $_ -match '\[SUMMARY\]' } | Select-Object -Last 1
        if ($summaryLine -match 'Passed:\s*(\d+)\s+Failed:\s*(\d+)\s+Total:\s*(\d+)') {
            $testResult = @{ Passed = [int]$Matches[1]; Failed = [int]$Matches[2] }
        }
        else {
            Write-Log "[WARNING] Could not parse summary line from '$Label'. Treating as failure."
        }
    }
    catch {
        Write-Log "[$Label] [FAIL] Failed to execute local tests"
        Write-Log "[$Label] [FAIL] Exception: $_"
    }

    return $testResult
}

function Invoke-VMStopDeallocateStart {
    param(
        [string]$ResourceGroupName,
        [string]$VMName
    )

    Write-Log "Stopping VM '$VMName' (deallocate) to test startup configuration..."
    Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force -ErrorAction Stop | Out-Null

    Write-Log "Starting VM '$VMName'..."
    Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop | Out-Null

    # The startup scheduled task (Set-MssqlStartupConfiguration.ps1) runs at boot.
    # After a deallocate the temp disk is wiped, so the task will reformat it,
    # reconfigure the pagefile and restart the VM once more before starting SQL Server.
    # Poll until the SQL Server service is running to confirm the full cycle completed.
    Write-Log "Waiting for VM '$VMName' to complete startup configuration..."

    $probeScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) 'probe-mssql-ready.ps1'
    Set-Content -Path $probeScriptPath -Value "(Get-Service -Name MSSQLSERVER -ErrorAction SilentlyContinue).Status"

    $ready = $false
    $maxAttempts = 10

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Start-Sleep -Seconds 30

        try {
            $probe = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId 'RunPowerShellScript' -ScriptPath $probeScriptPath -ErrorAction Stop
            $stdout = ($probe.Value | Where-Object { $_.Code -like '*StdOut*' } | Select-Object -First 1).Message

            if ($stdout -match 'Running') {
                Write-Log "VM '$VMName' is ready - SQL Server service is running."
                $ready = $true
                break
            }

            Write-Log "VM '$VMName' probe attempt $attempt/$maxAttempts - SQL Server status: $($stdout.Trim())"
        }
        catch {
            Write-Log "VM '$VMName' probe attempt $attempt/$maxAttempts - VM agent not ready yet."
        }
    }

    Remove-Item $probeScriptPath -Force -ErrorAction SilentlyContinue

    if (-not $ready) {
        Write-Log "[WARNING] VM '$VMName' may not be fully ready after $maxAttempts probe attempts. Proceeding with tests."
    }
}
#endregion

#region main
$script:logPath = Join-Path $PWD 'Invoke-UnitTests.ps1.log'
$repoRoot = Split-Path $PSScriptRoot -Parent

# Clear previous log
if (Test-Path $script:logPath) { Remove-Item $script:logPath -Force }

Write-Log "Starting unit test collection..."
Write-Log "Log file: $($script:logPath)"

# Verify Azure connection
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) { throw "No Azure context found." }
    Write-Log "Azure context: subscription '$($context.Subscription.Name)' ($($context.Subscription.Id))"
}
catch {
    Exit-WithError "Azure credentials are missing or expired. Run 'Connect-AzAccount' to authenticate. Exception: $_"
}

# Verify terraform is available
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Exit-WithError "terraform command not found. Ensure terraform is installed and in PATH."
}

# Get terraform outputs (run from scope of the repo root to find state)
Write-Log "Reading terraform outputs..."
try {
    Push-Location $repoRoot
    $tfJson = terraform output -json resource_names 2>&1
    $tfExitCode = $LASTEXITCODE
    Pop-Location
    if ($tfExitCode -ne 0) { throw "terraform output exit code ${tfExitCode}: $tfJson" }
    $resourceNames = $tfJson | ConvertFrom-Json -AsHashtable
}
catch {
    Exit-WithError "Failed to read terraform outputs. Ensure terraform state is initialized in '$repoRoot'. Exception: $_"
}

# Read fqdns output (may be empty if no modules expose FQDNs)
$fqdns = @{}
try {
    Push-Location $repoRoot
    $fqdnJson = terraform output -json fqdns 2>&1
    $fqdnExitCode = $LASTEXITCODE
    Pop-Location
    if ($fqdnExitCode -eq 0 -and $fqdnJson) {
        $fqdns = $fqdnJson | ConvertFrom-Json -AsHashtable
    }
}
catch {
    Write-Log "[WARNING] Could not read terraform output 'fqdns': $_"
}

# Read adds_domain_name output (needed for AVD integration tests)
$addsDomainName = $null
try {
    Push-Location $repoRoot
    $domainJson = terraform output -json adds_domain_name 2>&1
    $domainExitCode = $LASTEXITCODE
    Pop-Location
    if ($domainExitCode -eq 0 -and $domainJson) {
        $addsDomainName = $domainJson | ConvertFrom-Json
    }
}
catch {
    Write-Log "[WARNING] Could not read terraform output 'adds_domain_name': $_"
}

$resourceGroupName = $resourceNames['resource_group']
if (-not $resourceGroupName) {
    Exit-WithError "resource_group not found in terraform output resource_names."
}

Write-Log "Resource group: $resourceGroupName"

# Validate Azure credentials are live by querying the target resource group
try {
    $null = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop
    Write-Log "Azure credentials validated against resource group '$resourceGroupName'."
}
catch {
    Exit-WithError "Azure credentials are expired or lack access to resource group '$resourceGroupName'. Run 'Connect-AzAccount' to re-authenticate. Exception: $_"
}

# Map main.tf module names to test configuration keys
$moduleToVmKey = @{
    'vnet_shared'      = 'virtual_machine_adds1'
    'vnet_app'         = 'virtual_machine_jumpwin1'
    'vm_jumpbox_linux' = 'virtual_machine_jumplinux1'
    'vm_mssql_win'     = 'virtual_machine_mssqlwin1'
    'mssql'            = '$local_mssql'
    'mysql'            = '$local_mysql'
    'petstore'         = '$local_petstore'
    'vwan'             = '$local_vwan'
    'avd'              = '$local_avd'
}

if ($Integration -and -not $Module) {
    Exit-WithError "-Integration requires -Module to be specified."
}

# Validate -Module parameter if specified
if ($Module) {
    if (-not $moduleToVmKey.ContainsKey($Module)) {
        Exit-WithError "Unknown module '$Module'. Valid modules: $($moduleToVmKey.Keys -join ', ')"
    }
    Write-Log "Targeting single module: $Module"
    if ($Integration) {
        Write-Log "Integration tests enabled for module: $Module"
    }
}

# Map modules to their associated integration test names
$moduleIntegrationMap = @{
    'vnet_app'         = @('SSH: jumpwin1 -> jumplinux1', 'SQL: jumpwin1 -> mssqlwin1', 'Azure SQL: jumpwin1 -> testdb', 'MySQL: jumpwin1 -> mysql')
    'vm_jumpbox_linux' = @('SSH: jumpwin1 -> jumplinux1')
    'vm_mssql_win'     = @('SQL: jumpwin1 -> mssqlwin1')
    'mssql'            = @('Azure SQL: jumpwin1 -> testdb')
    'mysql'            = @('MySQL: jumpwin1 -> mysql')
    'petstore'         = @('Petstore API: jumpwin1 -> petstore')
    'vwan'             = @('P2S VPN: local -> sandbox endpoints')
    'avd'              = @('AVD: personal session host config', 'AVD: remoteapp session host config')
}

# Pre-validate sudo early if vwan integration tests will run (avoids waiting for prompt mid-test)
$willRunVwanIntegration = ((-not $Module) -or ($Module -eq 'vwan' -and $Integration)) -and $resourceNames['virtual_wan'] -and $resourceNames['virtual_wan_hub']
if ($willRunVwanIntegration -and ($IsLinux -or $IsMacOS)) {
    Write-Log "Pre-validating sudo access for vwan integration test..."
    & sudo -n true 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if ([System.Environment]::UserInteractive -or (Test-Path /dev/tty)) {
            & sudo -v
        }
    }
}

# Define test configurations
$testConfigs = [ordered]@{
    'virtual_machine_adds1' = @{
        Module     = 'vnet-shared'
        ModuleName = 'vnet_shared'
        ScriptPath = Join-Path $repoRoot 'modules' 'vnet-shared' 'scripts' 'Test-VnetShared.ps1'
        CommandId  = 'RunPowerShellScript'
        Parameters = @{}
    }
    'virtual_machine_jumpwin1' = @{
        Module     = 'vnet-app'
        ModuleName = 'vnet_app'
        ScriptPath = Join-Path $repoRoot 'modules' 'vnet-app' 'scripts' 'Test-VnetApp.ps1'
        CommandId  = 'RunPowerShellScript'
        Parameters = @{
            KeyVaultName       = $resourceNames['key_vault']
            StorageAccountName = $resourceNames['storage_account']
            StorageShareName   = $resourceNames['storage_share']
        }
    }
    'virtual_machine_jumplinux1' = @{
        Module     = 'vm-jumpbox-linux'
        ModuleName = 'vm_jumpbox_linux'
        ScriptPath = Join-Path $repoRoot 'modules' 'vm-jumpbox-linux' 'scripts' 'test-vm-jumpbox-linux.sh'
        CommandId  = 'RunShellScript'
        Parameters = @{}
    }
    'virtual_machine_mssqlwin1' = @{
        Module     = 'vm-mssql-win'
        ModuleName = 'vm_mssql_win'
        ScriptPath = Join-Path $repoRoot 'modules' 'vm-mssql-win' 'scripts' 'Test-VmMssqlWin.ps1'
        CommandId  = 'RunPowerShellScript'
        Parameters = @{
            KeyVaultName = $resourceNames['key_vault']
        }
        StopDeallocateBeforeTest = $true
    }
    '$local_mssql' = @{
        Module     = 'mssql'
        ModuleName = 'mssql'
        RunLocal   = $true
        ScriptPath = Join-Path $repoRoot 'modules' 'mssql' 'scripts' 'Test-Mssql.ps1'
        Parameters = @{
            ResourceGroupName = $resourceGroupName
            MssqlServerName   = $resourceNames['mssql_server']
            MssqlDatabaseName = $resourceNames['mssql_db']
        }
    }
    '$local_mysql' = @{
        Module     = 'mysql'
        ModuleName = 'mysql'
        RunLocal   = $true
        ScriptPath = Join-Path $repoRoot 'modules' 'mysql' 'scripts' 'Test-Mysql.ps1'
        Parameters = @{
            ResourceGroupName = $resourceGroupName
            MysqlServerName   = $resourceNames['mysql_server']
            MysqlDatabaseName = $resourceNames['mysql_db']
        }
    }
    '$local_petstore' = @{
        Module     = 'petstore'
        ModuleName = 'petstore'
        RunLocal   = $true
        ScriptPath = Join-Path $repoRoot 'extras' 'modules' 'petstore' 'scripts' 'Test-Petstore.ps1'
        Parameters = @{
            ResourceGroupName            = $resourceGroupName
            ContainerAppEnvironmentName  = $resourceNames['container_app_environment']
            ContainerAppName             = 'petstore'
            ContainerRegistryName        = $resourceNames['container_registry']
        }
    }
    '$local_vwan' = @{
        Module     = 'vwan'
        ModuleName = 'vwan'
        RunLocal   = $true
        ScriptPath = Join-Path $repoRoot 'modules' 'vwan' 'scripts' 'Test-Vwan.ps1'
        Parameters = @{
            ResourceGroupName = $resourceGroupName
            VirtualWanName    = $resourceNames['virtual_wan']
            VirtualHubName    = $resourceNames['virtual_wan_hub']
        }
    }
    '$local_avd' = @{
        Module     = 'avd'
        ModuleName = 'avd'
        RunLocal   = $true
        ScriptPath = Join-Path $repoRoot 'extras' 'modules' 'avd' 'scripts' 'Test-Avd.ps1'
        Parameters = @{
            ResourceGroupName     = $resourceGroupName
            AvdWorkspaceName      = $resourceNames['avd_workspace']
            HostPoolPersonalName  = $resourceNames['avd_host_pool_personal']
            HostPoolRemoteappName = $resourceNames['avd_host_pool_remoteapp']
            AppGroupPersonalName  = $resourceNames['avd_application_group_personal']
            AppGroupRemoteappName = $resourceNames['avd_application_group_remoteapp']
            VmNamePersonal        = $resourceNames['virtual_machine_session_host_personal']
            VmNameRemoteapp       = $resourceNames['virtual_machine_session_host_remoteapp']
        }
    }
}

# Filter to single module if specified
if ($Module) {
    $targetVmKey = $moduleToVmKey[$Module]
    $filteredConfigs = [ordered]@{}
    $filteredConfigs[$targetVmKey] = $testConfigs[$targetVmKey]
    $testConfigs = $filteredConfigs
}

$overallPassed = 0
$overallFailed = 0
$moduleResults = @()

# Module unit tests
foreach ($configKey in $testConfigs.Keys) {
    $config = $testConfigs[$configKey]

    if ($config.RunLocal) {
        # Client-side test (e.g. mssql PaaS module)
        # Skip if required terraform output keys are missing (module not deployed)
        $skipLocal = $false
        foreach ($val in $config.Parameters.Values) {
            if (-not $val) {
                $skipLocal = $true
                break
            }
        }

        if ($skipLocal) {
            Write-Log "Skipping module '$($config.Module)': required terraform outputs not found (module not deployed)."
            continue
        }

        Write-Log "========================================"
        Write-Log "Module: $($config.Module) | Local"
        Write-Log "========================================"

        $testResult = Invoke-LocalTest -ScriptPath $config.ScriptPath -Parameters $config.Parameters -Label "MODULE:$($config.Module)"
    }
    else {
        # VM-based test
        $vmName = $resourceNames[$configKey]

        if (-not $vmName) {
            Write-Log "Skipping module '$($config.Module)': VM key '$configKey' not found in terraform outputs (module not deployed)."
            continue
        }

        Write-Log "========================================"
        Write-Log "Module: $($config.Module) | VM: $vmName"
        Write-Log "========================================"

        # Stop/deallocate and restart VM if required (tests startup configuration after temp disk wipe)
        if ($config.StopDeallocateBeforeTest) {
            try {
                Invoke-VMStopDeallocateStart -ResourceGroupName $resourceGroupName -VMName $vmName
            }
            catch {
                Write-Log "[MODULE:$($config.Module)] [FAIL] Failed to stop/deallocate/start VM '$vmName': $_"
                $overallFailed++
                $moduleResults += @{ Module = $config.Module; Passed = 0; Failed = 1 }
                continue
            }
        }

        $testResult = Invoke-VMTest -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId $config.CommandId -ScriptPath $config.ScriptPath -Parameters $config.Parameters -Label "MODULE:$($config.Module)"
    }
    $overallPassed += $testResult.Passed
    $overallFailed += $testResult.Failed
    $moduleResults += @{ Module = $config.Module; Passed = $testResult.Passed; Failed = $testResult.Failed }
}

# Integration tests - run when testing all modules or when -Module -Integration is specified
$runIntegration = (-not $Module) -or ($Module -and $Integration)
if ($runIntegration) {
    $integrationTests = @(
        @{
            Name        = 'SSH: jumpwin1 -> jumplinux1'
            RequiredVMs = @('virtual_machine_jumpwin1', 'virtual_machine_jumplinux1')
            RunOnVM     = 'virtual_machine_jumpwin1'
            ScriptPath  = Join-Path $repoRoot 'scripts' 'Test-Integration-SshConnectivity.ps1'
            CommandId   = 'RunPowerShellScript'
            Parameters  = @{
                KeyVaultName = $resourceNames['key_vault']
                TargetVmName = $resourceNames['virtual_machine_jumplinux1']
            }
        }
        @{
            Name        = 'SQL: jumpwin1 -> mssqlwin1'
            RequiredVMs = @('virtual_machine_jumpwin1', 'virtual_machine_mssqlwin1')
            RunOnVM     = 'virtual_machine_jumpwin1'
            ScriptPath  = Join-Path $repoRoot 'scripts' 'Test-Integration-SqlConnectivity.ps1'
            CommandId   = 'RunPowerShellScript'
            Parameters  = @{
                KeyVaultName = $resourceNames['key_vault']
                TargetVmName = $resourceNames['virtual_machine_mssqlwin1']
            }
        }
        @{
            Name         = 'Azure SQL: jumpwin1 -> testdb'
            RequiredVMs  = @('virtual_machine_jumpwin1')
            RequiredFqdn = 'mssql_server'
            RunOnVM      = 'virtual_machine_jumpwin1'
            ScriptPath   = Join-Path $repoRoot 'scripts' 'Test-Integration-AzSqlConnectivity.ps1'
            CommandId    = 'RunPowerShellScript'
            Parameters   = @{
                MssqlServerFqdn   = $fqdns['mssql_server']
                MssqlDatabaseName = $resourceNames['mssql_db']
            }
        }
        @{
            Name         = 'MySQL: jumpwin1 -> mysql'
            RequiredVMs  = @('virtual_machine_jumpwin1')
            RequiredFqdn = 'mysql_server'
            RunOnVM      = 'virtual_machine_jumpwin1'
            ScriptPath   = Join-Path $repoRoot 'scripts' 'Test-Integration-AzMySqlConnectivity.ps1'
            CommandId    = 'RunPowerShellScript'
            Parameters   = @{
                MysqlServerFqdn   = $fqdns['mysql_server']
                MysqlDatabaseName = $resourceNames['mysql_db']
                KeyVaultName      = $resourceNames['key_vault']
            }
        }
        @{
            Name         = 'Petstore API: jumpwin1 -> petstore'
            RequiredVMs  = @('virtual_machine_jumpwin1')
            RequiredFqdn = 'petstore'
            RunOnVM      = 'virtual_machine_jumpwin1'
            ScriptPath   = Join-Path $repoRoot 'scripts' 'Test-Integration-Petstore.ps1'
            CommandId    = 'RunPowerShellScript'
            Parameters   = @{
                PetstoreFqdn = $fqdns['petstore']
            }
        }
        @{
            Name         = 'P2S VPN: local -> sandbox endpoints'
            RequiredVMs  = @()
            RunLocal     = $true
            RequiresSudo = $true
            ScriptPath   = Join-Path $repoRoot 'scripts' 'Test-Integration-VwanConnectivity.ps1'
            Parameters  = @{
                ResourceGroupName  = $resourceGroupName
                KeyVaultName       = $resourceNames['key_vault']
                VirtualWanName     = $resourceNames['virtual_wan']
                VirtualHubName     = $resourceNames['virtual_wan_hub']
                StorageAccountName = $resourceNames['storage_account']
                StorageShareName   = $resourceNames['storage_share']
                MssqlServerFqdn    = $fqdns['mssql_server']
                MssqlDatabaseName  = $resourceNames['mssql_db']
                MysqlServerFqdn    = $fqdns['mysql_server']
                MysqlDatabaseName  = $resourceNames['mysql_db']
            }
        }
        @{
            Name        = 'AVD: personal session host config'
            RequiredVMs = @('virtual_machine_session_host_personal')
            RunOnVM     = 'virtual_machine_session_host_personal'
            ScriptPath  = Join-Path $repoRoot 'scripts' 'Test-Integration-AvdPersonal.ps1'
            CommandId   = 'RunPowerShellScript'
            Parameters  = @{
                KeyVaultName       = $resourceNames['key_vault']
                StorageAccountName = $resourceNames['storage_account']
                StorageShareName   = $resourceNames['storage_share']
                DomainName         = $addsDomainName
            }
        }
        @{
            Name         = 'AVD: remoteapp session host config'
            RequiredVMs  = @('virtual_machine_session_host_remoteapp')
            RequiredFqdn = 'petstore'
            RunOnVM      = 'virtual_machine_session_host_remoteapp'
            ScriptPath   = Join-Path $repoRoot 'scripts' 'Test-Integration-AvdRemoteapp.ps1'
            CommandId    = 'RunPowerShellScript'
            Parameters   = @{
                PetstoreFqdn      = $fqdns['petstore']
            }
        }
    )

    # Filter integration tests when -Module -Integration is specified
    if ($Module -and $moduleIntegrationMap.ContainsKey($Module)) {
        $allowedNames = $moduleIntegrationMap[$Module]
        $integrationTests = $integrationTests | Where-Object { $_.Name -in $allowedNames }
    }
    elseif ($Module) {
        # Module has no associated integration tests
        $integrationTests = @()
        Write-Log "No associated integration tests for module '$Module'."
    }

    foreach ($test in $integrationTests) {
        # Check all required VMs are deployed
        $allDeployed = $true
        $missingVm = $null

        foreach ($vmKey in $test.RequiredVMs) {
            if (-not $resourceNames[$vmKey]) {
                $allDeployed = $false
                $missingVm = $vmKey
                break
            }
        }

        if (-not $allDeployed) {
            Write-Log "Skipping integration test '$($test.Name)': required VM '$missingVm' not deployed."
            continue
        }

        # Check required FQDN is available (for tests that depend on PaaS modules)
        if ($test.RequiredFqdn -and -not $fqdns[$test.RequiredFqdn]) {
            Write-Log "Skipping integration test '$($test.Name)': required FQDN '$($test.RequiredFqdn)' not found in terraform outputs (module not deployed)."
            continue
        }

        # For local integration tests, skip if required parameters are missing (module not deployed)
        if ($test.RunLocal) {
            $skipLocal = $false
            foreach ($key in @('ResourceGroupName', 'KeyVaultName', 'VirtualWanName', 'VirtualHubName')) {
                if ($test.Parameters.ContainsKey($key) -and -not $test.Parameters[$key]) {
                    Write-Log "Skipping integration test '$($test.Name)': required parameter '$key' not found in terraform outputs (module not deployed)."
                    $skipLocal = $true
                    break
                }
            }
            if ($skipLocal) { continue }
        }

        if ($test.RunLocal) {
            # Local integration test (e.g. P2S VPN from Terraform execution environment)
            Write-Log "========================================"
            Write-Log "Integration: $($test.Name) | Local"
            Write-Log "========================================"

            # Pre-validate sudo: prompt interactively if needed, or rely on passwordless in CI
            if ($test.RequiresSudo -and ($IsLinux -or $IsMacOS)) {
                & sudo -n true 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    if ([System.Environment]::UserInteractive -or (Test-Path /dev/tty)) {
                        & sudo -v
                    }
                }
            }

            $testResult = Invoke-LocalTest -ScriptPath $test.ScriptPath -Parameters $test.Parameters -Label "INTEGRATION:$($test.Name)"
        }
        else {
            $vmName = $resourceNames[$test.RunOnVM]

            Write-Log "========================================"
            Write-Log "Integration: $($test.Name) | VM: $vmName"
            Write-Log "========================================"

            $testResult = Invoke-VMTest -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId $test.CommandId -ScriptPath $test.ScriptPath -Parameters $test.Parameters -Label "INTEGRATION:$($test.Name)"
        }
        $overallPassed += $testResult.Passed
        $overallFailed += $testResult.Failed
        $moduleResults += @{ Module = "integration: $($test.Name)"; Passed = $testResult.Passed; Failed = $testResult.Failed }
    }
}

# Final summary
Write-Log "========================================"
Write-Log "UNIT TEST RESULTS SUMMARY"
Write-Log "========================================"
foreach ($mr in $moduleResults) {
    $status = if ($mr.Failed -gt 0) { 'FAIL' } else { 'PASS' }
    Write-Log "  [$status] $($mr.Module): Passed=$($mr.Passed) Failed=$($mr.Failed)"
}
$overallTotal = $overallPassed + $overallFailed
Write-Log "Overall: Passed=$overallPassed Failed=$overallFailed Total=$overallTotal"

if ($overallFailed -gt 0) {
    Write-Log "RESULT: FAIL"
    exit 1
}
else {
    Write-Log "RESULT: PASS"
    exit 0
}
#endregion
