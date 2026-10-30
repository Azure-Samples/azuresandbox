#requires -Version 7.3

param(
    [Parameter(Mandatory)]
    [ValidateSet('preflight', 'apply', 'unit-test', 'summary')]
    [string]$Stage,

    # Internal: set only when this script starts one sandbox of a multi-sandbox run (SANDBOX_COUNT above 1).
    [ValidateRange(0, 20)]
    [int]$Instance = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SandboxProgress.ps1')
. (Join-Path $PSScriptRoot 'SandboxOidc.ps1')
. (Join-Path $PSScriptRoot 'SandboxRedaction.ps1')
. (Join-Path $PSScriptRoot 'SandboxTerraformError.ps1')
$script:utf8 = [System.Text.UTF8Encoding]::new($false)
$script:directory = $null
$script:redaction = $null
$script:count = 1
$script:fanOut = $false

function Stop-SandboxStage {
    param([string]$Message, [int]$Code = 1)
    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data['ExitCode'] = $Code
    throw $exception
}

function Write-SandboxLog {
    param([string]$Text)
    [System.IO.File]::AppendAllText($script:logPath, $Text, $script:utf8)
}

function Get-SandboxRedaction {
    # The run's ids and tags are known once preflight has copied backend.tf and terraform.tfvars; until then, GUIDs and
    # tag-shaped text are still redacted.
    if (-not $script:redaction -and $script:directory -and [System.IO.File]::Exists((Join-Path $script:directory 'backend.tf'))) {
        $script:redaction = Get-SandboxRedactionContext $script:directory
    }
    # A multi-sandbox parent has no backend.tf of its own; every sandbox in the run uses the same secrets.
    if (-not $script:redaction -and $script:fanOut) {
        foreach ($number in 1..$script:count) {
            $instanceDirectory = (Get-SandboxInstance $number).Directory
            if ([System.IO.File]::Exists((Join-Path $instanceDirectory 'backend.tf'))) {
                $script:redaction = Get-SandboxRedactionContext $instanceDirectory
                break
            }
        }
    }
    if ($script:redaction) { $script:redaction } else { @{ KnownIds = @{}; Tags = @{} } }
}

function Protect-SandboxText {
    # Applies SandboxRedaction.ps1 to anything published.
    param([AllowEmptyString()][string]$Text)
    $context = Get-SandboxRedaction
    ConvertTo-SandboxRedactedText -Text $Text -KnownIds $context.KnownIds -Tags $context.Tags
}

function Write-SandboxStatus {
    param([AllowEmptyString()][string]$Text)
    Write-Host (Protect-SandboxText $Text)
}

function Write-SandboxSummary {
    param([string]$Text)
    [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, (Protect-SandboxText $Text), $script:utf8)
}

function Write-SandboxJson {
    param([string]$Path, $Value)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30) + "`n", $script:utf8)
}

function Read-SandboxJson {
    param([string]$Path)
    ConvertFrom-Json -AsHashtable -InputObject ([System.IO.File]::ReadAllText($Path))
}

function Get-SandboxResourceGroupName {
    param($ResourceNames)
    if ($ResourceNames -isnot [System.Collections.IDictionary] -or
        $ResourceNames['resource_group'] -isnot [string] -or
        [string]::IsNullOrWhiteSpace($ResourceNames['resource_group']) -or
        $ResourceNames['resource_group'] -match '[\p{C}`]') {
        Stop-SandboxStage 'Terraform resource_names did not provide a reportable resource group name.'
    }
    $ResourceNames['resource_group']
}

function Get-SandboxHash {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-SandboxEqual {
    param($Left, $Right)
    if ($Left -is [System.Collections.IDictionary] -and $Right -is [System.Collections.IDictionary]) {
        if ($Left.Count -ne $Right.Count) { return $false }
        foreach ($key in $Left.Keys) {
            if (-not $Right.Contains($key) -or -not (Test-SandboxEqual $Left[$key] $Right[$key])) {
                return $false
            }
        }
        return $true
    }
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    return $Left.GetType() -eq $Right.GetType() -and $Left -ceq $Right
}

function Invoke-SandboxCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$OutputPath,
        [AllowNull()][string]$InputText,
        # Logged instead of Arguments when they contain a credential.
        [string[]]$LogArguments,
        # Returns the exit code instead of stopping the stage when the command fails.
        [switch]$AllowFailure
    )
    $logged = if ($LogArguments) { $LogArguments } else { $Arguments }
    Write-SandboxLog "`n[$([DateTimeOffset]::UtcNow.ToString('o'))] $($logged | ConvertTo-Json -Compress)`n"
    $destination = $script:logPath
    if ($OutputPath) {
        [System.IO.File]::WriteAllText($OutputPath, '', $script:utf8)
        $destination = $OutputPath
    }
    $inputPath = '/dev/null'
    $process = [System.Diagnostics.Process]::new()
    try {
        if ($PSBoundParameters.ContainsKey('InputText')) {
            $inputPath = Join-Path $script:directory 'command-input.txt'
            [System.IO.File]::WriteAllText($inputPath, $InputText, $script:utf8)
        }
        $info = [System.Diagnostics.ProcessStartInfo]::new()
        $info.FileName = 'bash'
        $info.UseShellExecute = $false
        $info.WorkingDirectory = $script:root
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($argument in @(
                (Join-Path $PSScriptRoot 'Invoke-SandboxDeployment.sh'), '--command',
                $script:root, $script:logPath, $destination, $inputPath, '--'
            ) + $Arguments) {
            $info.ArgumentList.Add($argument)
        }
        $info.Environment.Clear()
        foreach ($entry in $script:childEnvironment.GetEnumerator()) {
            $info.Environment[$entry.Key] = $entry.Value
        }
        $process.StartInfo = $info
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $lastSize = ([System.IO.FileInfo]::new($script:logPath)).Length
        if (-not $process.Start()) { Stop-SandboxStage 'Command did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(120000)) {
            $size = ([System.IO.FileInfo]::new($script:logPath)).Length
            $health = if ($size -gt $lastSize) { 'log advancing' } else { 'no new log output; review if persistent' }
            Write-SandboxStatus "${Stage}: $([int][Math]::Floor($timer.Elapsed.TotalMinutes)) min elapsed; $health."
            if ($Stage -in @('apply', 'unit-test') -and $size -gt $lastSize) {
                try {
                    foreach ($line in @(Read-SandboxProgress -Path $script:logPath -Start $lastSize -Stage $Stage)) {
                        Write-SandboxStatus "  $line"
                    }
                }
                catch [System.IO.IOException] {
                    Write-SandboxLog "$($_ | Out-String)`n"
                    $size = ([System.IO.FileInfo]::new($script:logPath)).Length
                    Write-SandboxStatus "${Stage}: sanitized progress preview unavailable; see private diagnostics."
                }
                catch [System.UnauthorizedAccessException] {
                    Write-SandboxLog "$($_ | Out-String)`n"
                    $size = ([System.IO.FileInfo]::new($script:logPath)).Length
                    Write-SandboxStatus "${Stage}: sanitized progress preview unavailable; see private diagnostics."
                }
            }
            $lastSize = $size
        }
        Write-SandboxLog ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
        $code = $process.ExitCode
        Write-SandboxLog "[$([DateTimeOffset]::UtcNow.ToString('o'))] Exit code: $code`n"
        if ($AllowFailure) { return $code }
        if ($code -ne 0) {
            Stop-SandboxStage 'Command failed; see the private stage log.' ([Math]::Max(1, $code))
        }
    }
    finally {
        $process.Dispose()
        if ($inputPath -ne '/dev/null' -and [System.IO.File]::Exists($inputPath)) {
            [System.IO.File]::Delete($inputPath)
        }
    }
}

function Get-SandboxOutput {
    param([string[]]$Arguments, [string]$Name, [string]$InputText)
    $path = Join-Path $script:directory $Name
    $parameters = @{ Arguments = $Arguments; OutputPath = $path }
    if ($PSBoundParameters.ContainsKey('InputText')) { $parameters.InputText = $InputText }
    Invoke-SandboxCommand @parameters
    [System.IO.File]::ReadAllText($path)
}

function Get-SandboxSource {
    (Get-SandboxOutput -Arguments @('git', 'rev-parse', 'HEAD') -Name 'source-sha.txt').Trim()
}

function Get-SandboxFingerprints {
    @{
        'backend.tf' = Get-SandboxHash (Join-Path $script:root 'backend.tf')
        'terraform.tfvars' = Get-SandboxHash (Join-Path $script:root 'terraform.tfvars')
        'profile.json' = Get-SandboxHash (Join-Path $script:directory 'profile.json')
    }
}

function Confirm-SandboxReceipt {
    $record = Read-SandboxJson $script:receipt
    $expected = @{
        deployment_id = $script:deploymentId; state_key = $script:key
        run_id = $script:runId; run_attempt = $script:attempt
        source_sha = Get-SandboxSource; configuration = Get-SandboxFingerprints
        plan_sha256 = Get-SandboxHash $script:plan; plan_path = $script:plan
    }
    foreach ($name in $expected.Keys) {
        if (-not (Test-SandboxEqual $expected[$name] $record[$name])) {
            Stop-SandboxStage 'Saved plan does not match this run, source, or configuration.'
        }
    }
    return $record
}

function Connect-SandboxAzureCli {
    param([System.Collections.IDictionary]$DeploymentProfile)
    if ($DeploymentProfile.auth_mode -ceq 'managed_identity') {
        # The client id is required: jumplinux2 also has a system-assigned identity, used for the state backend.
        Invoke-SandboxCommand @('az', 'login', '--identity', '--client-id', $DeploymentProfile.client_id,
            '--allow-no-subscriptions', '--output', 'none')
    }
    else {
        $login = @('az', 'login', '--service-principal', '--username', $DeploymentProfile.client_id,
            '--tenant', $DeploymentProfile.entra_tenant_id, '--allow-no-subscriptions', '--output', 'none', '--federated-token')
        Invoke-SandboxCommand -Arguments ($login + @(Get-SandboxGitHubIdToken)) -LogArguments ($login + @('<redacted>'))
    }
}

function Connect-SandboxProvider {
    # The deployment identity has no standing role, so the subscription is visible only while its time-bound grants are
    # active. Sign in without a subscription, confirm the grants, then sign in again: Azure CLI lists subscriptions only
    # at sign-in.
    param([System.Collections.IDictionary]$DeploymentProfile, [int]$MinimumMinutes, [int]$WaitSeconds)
    $script:childEnvironment['ARM_TENANT_ID'] = $DeploymentProfile.entra_tenant_id
    Connect-SandboxAzureCli $DeploymentProfile
    Confirm-SandboxJitGrant $DeploymentProfile $MinimumMinutes $WaitSeconds
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        Connect-SandboxAzureCli $DeploymentProfile
        $code = Invoke-SandboxCommand -Arguments @('az', 'account', 'set', '--subscription', $DeploymentProfile.subscription_id) -AllowFailure
        if ($code -eq 0) { break }
        # The subscription can be listed shortly after the grants take effect.
        if ($timer.Elapsed.TotalSeconds -ge 120) {
            Stop-SandboxStage 'The deployment identity has active grants but Azure CLI could not select the approved subscription; see the private stage log.'
        }
        Start-Sleep -Seconds 30
    }
    $account = Get-SandboxOutput @('az', 'account', 'show', '--output', 'json') 'account.json' | ConvertFrom-Json -AsHashtable
    if ($account.id -cne $DeploymentProfile.subscription_id -or $account.tenantId -cne $DeploymentProfile.entra_tenant_id) {
        Stop-SandboxStage 'Azure CLI context does not match the approved deployment.'
    }
}

function ConvertTo-SandboxDateTimeOffset {
    param($Value)
    if ($Value -is [datetime]) { return [DateTimeOffset]$Value.ToUniversalTime() }
    [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal)
}

function Confirm-SandboxJitGrant {
    # Confirms the deployment identity's time-bound Contributor and Role Based Access Control Administrator grants are
    # active and listed, waiting up to WaitSeconds for propagation, and that at least MinimumMinutes of the grants remain.
    param([System.Collections.IDictionary]$DeploymentProfile, [int]$MinimumMinutes, [int]$WaitSeconds)
    $subscription = "/subscriptions/$($DeploymentProfile.subscription_id)"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $permissionsPath = Join-Path $script:directory 'jit-permissions.json'
    while ($true) {
        # Without an active grant the identity has no role on the subscription, so this call can fail; treat that as no grant.
        $code = Invoke-SandboxCommand -Arguments @('az', 'rest', '--method', 'get', '--output', 'json', '--url',
            "https://management.azure.com$subscription/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
        ) -OutputPath $permissionsPath -AllowFailure
        $actions = @()
        if ($code -eq 0) {
            $permissions = [System.IO.File]::ReadAllText($permissionsPath) | ConvertFrom-Json -AsHashtable
            $actions = @($permissions['value'] | ForEach-Object { $_['actions'] })
        }
        $effective = $actions -ccontains '*' -and $actions -ccontains 'Microsoft.Authorization/roleAssignments/write'
        $missing = $null
        if ($effective) {
            if ($MinimumMinutes -le 0) { return }
            # Schedule instances can be listed a few minutes after the roles take effect.
            $instances = Get-SandboxOutput @('az', 'rest', '--method', 'get', '--output', 'json', '--url',
                "https://management.azure.com$subscription/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01&`$filter=asTarget()"
            ) 'jit-instances.json' | ConvertFrom-Json -AsHashtable
            $roleEnds = [ordered]@{}
            foreach ($role in $script:jitRoles.GetEnumerator()) {
                $roleEnds[$role.Key] = @(foreach ($instance in @($instances['value'])) {
                        $properties = $instance['properties']
                        $scope = [string]$properties['scope']
                        if (([string]$properties['roleDefinitionId']).EndsWith("/$($role.Value)", [StringComparison]::OrdinalIgnoreCase) -and
                            ($scope -ieq $subscription -or $scope -ceq '/' -or
                                $scope.StartsWith('/providers/Microsoft.Management/managementGroups/', [StringComparison]::OrdinalIgnoreCase))) {
                            if ($null -eq $properties['endDateTime']) { [DateTimeOffset]::MaxValue }
                            else { ConvertTo-SandboxDateTimeOffset $properties['endDateTime'] }
                        }
                    })
                if ($null -eq $missing -and $roleEnds[$role.Key].Count -eq 0) { $missing = $role.Key }
            }
            if ($null -eq $missing) { break }
        }
        if ($timer.Elapsed.TotalSeconds -ge $WaitSeconds) {
            if (-not $effective) {
                Stop-SandboxStage 'The deployment identity has no active Contributor and Role Based Access Control Administrator grant on the subscription. Grant both time-bound roles before approving the run.'
            }
            Stop-SandboxStage "Could not find an active assignment of $missing for the deployment identity to check its remaining time."
        }
        Start-Sleep -Seconds 30
    }
    $now = [DateTimeOffset]::UtcNow
    $remaining = [TimeSpan]::MaxValue
    foreach ($role in $roleEnds.GetEnumerator()) {
        $end = @($role.Value | Sort-Object -Descending)[0]
        if ($end -eq [DateTimeOffset]::MaxValue) {
            Write-SandboxSummary "Warning: the deployment identity has a permanent $($role.Key) assignment; just-in-time access isn't enforced.`n`n"
            continue
        }
        if ($end - $now -lt $remaining) { $remaining = $end - $now }
    }
    if ($remaining -eq [TimeSpan]::MaxValue) { return }
    if ($remaining.TotalMinutes -lt $MinimumMinutes) {
        Stop-SandboxStage "The deployment identity's time-bound grant ends in $([int][Math]::Floor($remaining.TotalMinutes)) minutes; at least $MinimumMinutes minutes are required. Extend or renew the grant, then start a new run."
    }
    Write-SandboxSummary "Just-in-time grant: $([int][Math]::Floor($remaining.TotalMinutes)) minutes remaining (minimum $MinimumMinutes).`n`n"
}

function Get-SandboxTerraformVersion {
    $version = (Get-SandboxOutput -Arguments @('terraform', 'version', '-json') -Name 'terraform-version.json' |
        ConvertFrom-Json).terraform_version
    if ($version -isnot [string] -or $version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+') {
        Stop-SandboxStage 'Could not read the runner Terraform version.'
    }
    $version
}

# Lets Terraform itself evaluate the constraint: init in a directory that declares only required_version
# fails with "Unsupported Terraform Core version" when the installed CLI doesn't satisfy it.
function Test-SandboxTerraformConstraint {
    param([string]$Constraint)
    $checkDirectory = Join-Path $script:directory 'terraform-version-check'
    if ([System.IO.Directory]::Exists($checkDirectory)) { [System.IO.Directory]::Delete($checkDirectory, $true) }
    $null = [System.IO.Directory]::CreateDirectory($checkDirectory)
    try {
        [System.IO.File]::WriteAllText((Join-Path $checkDirectory 'versions.tf'),
            "terraform {`n  required_version = `"$Constraint`"`n}`n", $script:utf8)
        $outputPath = Join-Path $checkDirectory 'init.txt'
        $code = Invoke-SandboxCommand -AllowFailure -OutputPath $outputPath -Arguments @(
            'bash', '-c', 'exec "$@" 2>&1', 'terraform-version-check',
            'env', "TF_DATA_DIR=$checkDirectory/.terraform",
            'terraform', "-chdir=$checkDirectory", 'init', '-backend=false', '-input=false', '-no-color'
        )
        $output = [System.IO.File]::ReadAllText($outputPath)
        Write-SandboxLog $output
        if ($code -eq 0) { return $true }
        if ($output -cmatch 'Unsupported Terraform Core version') { return $false }
        Stop-SandboxStage 'Could not check the runner Terraform version against required_version; see the private stage log.'
    }
    finally {
        [System.IO.Directory]::Delete($checkDirectory, $true)
    }
}

# Uses the runner's Terraform when it satisfies the deployed source's required_version, even if it is newer than
# the version static CI uses. Otherwise installs the X.Y.Z that ci-terraform.yml derives, through the root-owned
# wrapper that rg-devops-iac grants the runner service account.
function Confirm-SandboxTerraformVersion {
    $declarations = [regex]::Matches([System.IO.File]::ReadAllText((Join-Path $script:root 'terraform.tf')),
        '(?m)^\s*required_version\s*=\s*"([^"\r\n]+)"')
    if ($declarations.Count -ne 1) { Stop-SandboxStage 'The deployed terraform.tf must declare exactly one required_version.' }
    $constraint = $declarations[0].Groups[1].Value
    if ($constraint -cnotmatch '^[0-9A-Za-z.,~<>=! -]+$') { Stop-SandboxStage 'The deployed required_version is not a valid version constraint.' }
    $installed = Get-SandboxTerraformVersion
    if (Test-SandboxTerraformConstraint $constraint) {
        Write-SandboxStatus "preflight: Terraform $installed satisfies required_version `"$constraint`"; nothing to install."
        Write-SandboxSummary "## Terraform`n`nrequired_version: ``$constraint``; runner Terraform ``$installed`` is compatible, nothing installed.`n`n"
        return
    }
    $target = [regex]::Match($constraint, '^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+)')
    if (-not $target.Success) { Stop-SandboxStage "Runner Terraform $installed doesn't satisfy required_version, and no X.Y.Z version can be derived from it." }
    $version = $target.Groups[1].Value
    $installer = '/usr/local/sbin/azuresandbox-install-terraform'
    if (-not [System.IO.File]::Exists($installer)) {
        Stop-SandboxStage "Runner Terraform $installed doesn't satisfy required_version `"$constraint`", and $installer is missing. Re-provision rg-devops-iac to install it, or install Terraform $version on the runner."
    }
    Write-SandboxStatus "preflight: Terraform $installed doesn't satisfy required_version `"$constraint`"; installing $version."
    Invoke-SandboxCommand @('sudo', '-n', $installer, $version)
    $current = Get-SandboxTerraformVersion
    if ($current -cne $version -or -not (Test-SandboxTerraformConstraint $constraint)) {
        Stop-SandboxStage "Installed Terraform $current doesn't satisfy required_version `"$constraint`"."
    }
    Write-SandboxSummary "## Terraform`n`nrequired_version: ``$constraint``; runner Terraform ``$installed`` was incompatible, installed ``$current``.`n`n"
}

function Get-SandboxBackend {
    # Parses and checks SANDBOX_BACKEND_HCL. Each run sets its own state key, so the secret must not set one.
    $backendText = $env:SANDBOX_BACKEND_HCL
    if ([string]::IsNullOrWhiteSpace($backendText)) { Stop-SandboxStage 'Both environment HCL secrets are required.' }
    $backend = @{}
    foreach ($name in @('tenant_id', 'subscription_id', 'storage_account_name', 'container_name')) {
        $backendMatches = [regex]::Matches($backendText, "(?m)^\s*$name\s*=\s*`"([^`"\n]+)`"\s*(?:#.*)?$")
        if ($backendMatches.Count -ne 1) { Stop-SandboxStage "Backend requires exactly one literal $name." }
        $backend[$name] = $backendMatches[0].Groups[1].Value
    }
    foreach ($name in @('use_msi', 'use_azuread_auth')) {
        if (-not [regex]::IsMatch($backendText, "(?m)^\s*$name\s*=\s*true\s*(?:#.*)?$")) {
            Stop-SandboxStage "Backend requires $name = true."
        }
    }
    if ([regex]::IsMatch($backendText, '(?m)^\s*(key|client_id|access_key|sas_token|client_secret)\s*=')) {
        Stop-SandboxStage 'Backend must omit fixed keys and authentication credentials.'
    }
    $backend
}

function Get-SandboxDirectorySize {
    # Doesn't follow symbolic links, such as provider links into a run's shared cache.
    param([string]$Path)
    $options = [System.IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $true
    $options.IgnoreInaccessible = $true
    $options.AttributesToSkip = [System.IO.FileAttributes]::ReparsePoint
    $size = 0L
    foreach ($file in [System.IO.DirectoryInfo]::new($Path).EnumerateFiles('*', $options)) { $size += $file.Length }
    $size
}

function Format-SandboxSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:0.0} GB' -f ($Bytes / 1GB) }
    '{0:0} MB' -f ($Bytes / 1MB)
}

# Keeps the private records of the current run and of the SANDBOX_RETAINED_DEPLOYMENTS most recent previous runs on
# the runner, and purges older runs: first each deployment's state blob, then its records. A run is a unit: the
# records of every sandbox of a multi-sandbox run are kept or purged together. Runs share one concurrency group, so no
# other run is using the records or state. Requires the Azure CLI to be signed in as the runner's identity.
function Invoke-SandboxGarbageCollection {
    param([System.Collections.IDictionary]$Backend)
    $retainText = if ($env:SANDBOX_RETAINED_DEPLOYMENTS) { $env:SANDBOX_RETAINED_DEPLOYMENTS } else { '3' }
    if ($retainText -cnotmatch '^([1-9]|10)$') {
        Stop-SandboxStage 'SANDBOX_RETAINED_DEPLOYMENTS must be a whole number of previous runs from 1 to 10.'
    }
    $retain = [int]$retainText
    $root = Join-Path $HOME '.local/state/azuresandbox/deployments'
    $runs = @{}
    $unrecognized = 0
    foreach ($entry in [System.IO.DirectoryInfo]::new($root).EnumerateFileSystemInfos()) {
        $match = [regex]::Match($entry.Name, '^sandbox-([1-9][0-9]{0,18})(?:-([1-9]|1[0-9]|20))?$')
        if (-not $match.Success -or $entry -isnot [System.IO.DirectoryInfo] -or $entry.LinkTarget) { $unrecognized++; continue }
        $runId = [long]$match.Groups[1].Value
        if ($runId -eq [long]$script:runId) { continue }
        if (-not $runs.ContainsKey($runId)) { $runs[$runId] = [System.Collections.Generic.List[string]]::new() }
        $runs[$runId].Add($entry.FullName)
    }
    $previous = @($runs.Keys | Sort-Object -Descending)
    $kept = [Math]::Min($retain, $previous.Count)
    $purge = @($previous | Select-Object -Skip $retain)
    $result = [ordered]@{ Deployments = 0; Blobs = 0; Leases = 0; OtherBackend = 0; Bytes = 0L }
    if ($purge.Count -gt 0) {
        # One listing finds every deployment's state blob and lease.
        $listing = Get-SandboxOutput -Name 'state-blobs.json' -Arguments @(
            'az', 'storage', 'blob', 'list', '--auth-mode', 'login',
            '--account-name', $Backend.storage_account_name, '--container-name', $Backend.container_name,
            '--prefix', 'sandboxes/sandbox-', '--num-results', '*',
            '--query', '[].{name:name, lease:properties.lease.status}', '--output', 'json'
        ) | ConvertFrom-Json -AsHashtable -NoEnumerate
        if ($listing -isnot [System.Collections.IList]) { Stop-SandboxStage 'Storage did not return a valid state-blob listing.' }
        $blobs = @{}
        foreach ($blob in $listing) { $blobs[[string]$blob['name']] = [string]$blob['lease'] }
    }
    try {
        foreach ($path in @($purge | ForEach-Object { $runs[$_] })) {
            $id = [System.IO.Path]::GetFileName($path)
            $key = "sandboxes/$id/terraform.tfstate"
            # The manifest records the backend when preflight gets far enough to use the state key; without it, no
            # state blob was created.
            $manifestPath = Join-Path $path 'deployment.json'
            if ([System.IO.File]::Exists($manifestPath)) {
                $manifest = Read-SandboxJson $manifestPath
                $recorded = $manifest['backend']
                if ($recorded -isnot [System.Collections.IDictionary] -or
                    $recorded['storage_account_name'] -cne $Backend.storage_account_name -or
                    $recorded['container_name'] -cne $Backend.container_name) {
                    $result.OtherBackend++
                }
                elseif ($blobs.ContainsKey($key)) {
                    $target = @('--account-name', $Backend.storage_account_name, '--container-name', $Backend.container_name)
                    # An interrupted run can leave Terraform's state lock (a blob lease) held, which blocks the delete.
                    if ($blobs[$key] -ceq 'locked') {
                        Invoke-SandboxCommand (@('az', 'storage', 'blob', 'lease', 'break', '--auth-mode', 'login') + $target +
                            @('--blob-name', $key, '--lease-break-period', '0', '--output', 'none'))
                        $result.Leases++
                    }
                    Invoke-SandboxCommand (@('az', 'storage', 'blob', 'delete', '--auth-mode', 'login') + $target +
                        @('--name', $key, '--delete-snapshots', 'include', '--output', 'none'))
                    $result.Blobs++
                }
            }
            # Records go after the state blob, so a failed delete leaves them to retry on the next run.
            $result.Bytes += Get-SandboxDirectorySize $path
            Write-SandboxLog "`nPurging runner records: $path`n"
            [System.IO.Directory]::Delete($path, $true)
            $result.Deployments++
        }
    }
    catch {
        Write-SandboxLog "$($_ | Out-String)`n$($_.ScriptStackTrace)`n"
        Write-SandboxStatus "preflight: runner records: cleanup failed after purging $($result.Deployments) deployment(s); see the private stage log."
        Stop-SandboxStage 'Could not purge the records or state blob of an old run; see the private stage log.'
    }
    # Drops the worktree metadata of purged multi-sandbox source trees.
    if ($purge.Count -gt 0) { $null = Invoke-SandboxCommand @('git', 'worktree', 'prune') -AllowFailure }
    $keptText = "the current run and $kept previous run$(if ($kept -ne 1) { 's' }) (SANDBOX_RETAINED_DEPLOYMENTS = $retain)"
    $purged = if ($purge.Count -eq 0) { 'nothing to purge' } else {
        "purged $($purge.Count) run$(if ($purge.Count -ne 1) { 's' }): $($result.Deployments) deployment$(if ($result.Deployments -ne 1) { 's' }), " +
        "$($result.Blobs) state blob$(if ($result.Blobs -ne 1) { 's' }) deleted$(if ($result.Leases) { " ($($result.Leases) lease$(if ($result.Leases -ne 1) { 's' }) broken)" }), " +
        "$(Format-SandboxSize $result.Bytes) freed"
    }
    $notes = ''
    if ($result.OtherBackend) { $notes += " $($result.OtherBackend) purged deployment(s) used another state backend; delete those state blobs manually." }
    if ($unrecognized) { $notes += " $unrecognized unrecognized entr$(if ($unrecognized -ne 1) { 'ies' } else { 'y' }) left in place." }
    Write-SandboxStatus "preflight: runner records: kept $keptText; $purged.$notes"
    Write-SandboxSummary "## Runner records`n`nKept $keptText; $purged.$notes`n`n"
}

function Confirm-SandboxInvocation {
    if ($env:GITHUB_REF -cne 'refs/heads/main') { Stop-SandboxStage 'Run the registered workflow in the trusted main context.' }
    if ($env:GITHUB_EVENT_NAME -ceq 'workflow_dispatch') { return }
    if ($env:GITHUB_EVENT_NAME -cne 'pull_request_target' -or
        [string]::IsNullOrWhiteSpace($env:GITHUB_EVENT_PATH) -or
        $env:SANDBOX_RUN_THROUGH -cne 'unit-test' -or
        $env:SANDBOX_SOURCE_SHA -cnotmatch '^[0-9a-f]{40}$') {
        Stop-SandboxStage 'Invalid deployment event or release stage/source selection.'
    }
    $invocation = Read-SandboxJson $env:GITHUB_EVENT_PATH
    $pr = $invocation['pull_request']
    if ($pr -isnot [System.Collections.IDictionary] -or
        $pr['head'] -isnot [System.Collections.IDictionary] -or
        $pr['base'] -isnot [System.Collections.IDictionary]) {
        Stop-SandboxStage 'Release PR metadata is missing.'
    }
    $head = $pr['head']
    $base = $pr['base']
    if ($head['repo'] -isnot [System.Collections.IDictionary] -or
        $base['repo'] -isnot [System.Collections.IDictionary] -or
        $head['repo']['full_name'] -cne $env:GITHUB_REPOSITORY -or
        $base['repo']['full_name'] -cne $env:GITHUB_REPOSITORY -or
        $head['ref'] -cne 'vnext' -or $base['ref'] -cne 'main' -or
        $pr['draft'] -isnot [bool] -or $pr['draft'] -or
        $head['sha'] -cne $env:SANDBOX_SOURCE_SHA -or
        $invocation['action'] -cnotin @('opened', 'reopened', 'synchronize', 'ready_for_review', 'edited')) {
        Stop-SandboxStage 'Only ready same-repository vnext to main release PRs may deploy.'
    }
    if ($invocation['action'] -ceq 'edited' -and
        ($invocation['changes'] -isnot [System.Collections.IDictionary] -or
            $invocation['changes']['base'] -isnot [System.Collections.IDictionary] -or
            $invocation['changes']['base']['ref'] -isnot [System.Collections.IDictionary])) {
        Stop-SandboxStage 'PR metadata-only edits do not request a deployment.'
    }
    if ((Get-SandboxSource) -cne $env:SANDBOX_SOURCE_SHA) {
        Stop-SandboxStage 'Checked-out source does not match the release PR head SHA.'
    }
}

function Invoke-SandboxPreflight {
    Confirm-SandboxInvocation
    if ($env:RUNNER_NAME -cne 'jumplinux2') { Stop-SandboxStage 'Job did not run on the approved runner.' }
    if ($Instance -and -not [System.IO.Directory]::Exists($script:root)) {
        Stop-SandboxStage 'The sandbox source tree is missing.'
    }
    $jitMinimum = if ($env:SANDBOX_JIT_MIN_REMAINING_MINUTES) { $env:SANDBOX_JIT_MIN_REMAINING_MINUTES } else { '150' }
    if ($jitMinimum -cnotmatch '^[0-9]{1,4}$' -or [int]$jitMinimum -gt 1440) {
        Stop-SandboxStage 'SANDBOX_JIT_MIN_REMAINING_MINUTES must be a whole number of minutes from 0 to 1440.'
    }
    if ([string]::IsNullOrWhiteSpace($env:SANDBOX_BACKEND_HCL) -or [string]::IsNullOrWhiteSpace($env:SANDBOX_TFVARS_HCL)) {
        Stop-SandboxStage 'Both environment HCL secrets are required.'
    }
    foreach ($name in @('backend.tf', 'terraform.tfvars')) {
        $text = if ($name -eq 'backend.tf') { $env:SANDBOX_BACKEND_HCL } else { $env:SANDBOX_TFVARS_HCL }
        $path = Join-Path $script:root $name
        [System.IO.File]::WriteAllText($path, $text, $script:utf8)
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]384)
        [System.IO.File]::Copy($path, (Join-Path $script:directory $name), $false)
    }
    $backend = Get-SandboxBackend
    $script:childEnvironment['ARM_TENANT_ID'] = $backend.tenant_id
    Write-SandboxSummary "## Sandbox target`n`nDeployment: ``$script:deploymentId```n`nState key: ``$script:key```n`n[Originating run]($script:runBase$script:runId) / [Current run]($script:runBase$script:runId)`n`n"
    Invoke-SandboxCommand @('git', '--version')
    # In a multi-sandbox run the parent checks the shared Terraform CLI and cleans up old runs once, before starting
    # the sandboxes.
    if (-not $Instance) { Confirm-SandboxTerraformVersion }
    Invoke-SandboxCommand @('az', 'version')
    Invoke-SandboxCommand @('az', 'login', '--identity', '--allow-no-subscriptions', '--output', 'none')
    if (-not $Instance) { Invoke-SandboxGarbageCollection $backend }
    $exists = Get-SandboxOutput @(
        'az', 'storage', 'blob', 'exists', '--auth-mode', 'login',
        '--account-name', $backend.storage_account_name, '--container-name', $backend.container_name,
        '--name', $script:key, '--query', 'exists', '--output', 'json'
    ) 'blob-exists.json' | ConvertFrom-Json
    if ($exists -isnot [bool]) { Stop-SandboxStage 'Storage did not return a valid state-blob existence result.' }
    if ($exists) { Stop-SandboxStage 'New-Sandbox automation requires an unused state key on every attempt; dispatch a new run.' }
    $manifestPath = Join-Path $script:deploymentDirectory 'deployment.json'
    $manifest = @{ deployment_id = $script:deploymentId; backend = $backend; repository = $env:GITHUB_REPOSITORY }
    if ([System.IO.File]::Exists($manifestPath) -and -not (Test-SandboxEqual $manifest (Read-SandboxJson $manifestPath))) {
        Stop-SandboxStage 'Deployment receipt does not match the selected backend.'
    }
    Write-SandboxJson $manifestPath $manifest
    # A multi-sandbox parent creates the run's provider cache before starting the sandboxes.
    if (-not $Instance) { $null = [System.IO.Directory]::CreateDirectory($script:childEnvironment['TF_PLUGIN_CACHE_DIR']) }
    Invoke-SandboxCommand @('terraform', 'init', '-input=false', "-backend-config=key=$script:key")
    Invoke-SandboxCommand @('terraform', 'validate', '-no-color')
    $expression = 'jsonencode({auth_mode=var.auth_mode,client_id=var.client_id,entra_tenant_id=var.entra_tenant_id,subscription_id=var.subscription_id,base=[var.enable_module_vnet_app,var.enable_module_vm_jumpbox_linux,var.enable_module_vm_mssql_win,var.enable_module_mssql,var.enable_module_mysql,var.enable_module_vwan],extras=[var.enable_module_avd,var.enable_module_petstore,var.enable_module_vnet_onprem]})' + "`n"
    $console = Get-SandboxOutput -Arguments @('terraform', 'console', '-no-color') -Name 'console.txt' -InputText $expression
    $deploymentProfile = ConvertFrom-Json -AsHashtable -InputObject (ConvertFrom-Json -InputObject $console)
    # Release runs deploy every base module. Manual runs may choose any base modules, but vnet_app (index 0) is required
    # because the others depend on it.
    $baseModules = @($deploymentProfile.base)
    $baseInvalid = if ($env:GITHUB_EVENT_NAME -ceq 'workflow_dispatch') {
        @($baseModules | Where-Object { $_ -isnot [bool] }).Count -gt 0 -or $baseModules.Count -eq 0 -or $baseModules[0] -ne $true
    }
    else { @($baseModules | Where-Object { $_ -isnot [bool] -or -not $_ }).Count -gt 0 }
    if ($deploymentProfile.auth_mode -cnotin @('managed_identity', 'oidc') -or $deploymentProfile.entra_tenant_id -cne $backend.tenant_id -or
        $deploymentProfile.subscription_id -cne $backend.subscription_id -or -not $deploymentProfile.client_id -or $baseInvalid -or
        @($deploymentProfile.extras | Where-Object { $_ -isnot [bool] -or $_ }).Count -gt 0) {
        Stop-SandboxStage 'Inputs do not match the approved authentication mode, backend, or module scope.'
    }
    if ($deploymentProfile.auth_mode -cne $env:SANDBOX_AUTH_MODE) {
        Stop-SandboxStage "auth_mode in SANDBOX_TFVARS_HCL ($($deploymentProfile.auth_mode)) doesn't match the SANDBOX_AUTH_MODE repository variable ($env:SANDBOX_AUTH_MODE)."
    }
    Write-SandboxJson (Join-Path $script:directory 'profile.json') $deploymentProfile
    Connect-SandboxProvider $deploymentProfile ([int]$jitMinimum) 300
    Invoke-SandboxCommand @('pwsh', '-NoLogo', '-NoProfile', '-File',
        'extras/configurations/rg-devops-iac/scripts/Connect-SandboxRunner.ps1',
        '-ProfilePath', (Join-Path $script:directory 'profile.json'))
    Invoke-SandboxCommand @('terraform', 'plan', '-input=false', '-no-color', "-out=$script:plan")
    $planJson = Join-Path $script:directory 'plan.json'
    Invoke-SandboxCommand -Arguments @('terraform', 'show', '-json', $script:plan) -OutputPath $planJson
    $counts = @{ create = 0; update = 0; delete = 0 }
    $planDocument = Read-SandboxJson $planJson
    foreach ($change in $planDocument['resource_changes']) {
        foreach ($action in $change.change.actions) {
            if ($counts.ContainsKey($action)) { $counts[$action]++ }
        }
    }
    [System.IO.File]::Delete($planJson)
    Write-SandboxJson $script:receipt @{
        deployment_id = $script:deploymentId; state_key = $script:key
        origin_run_id = $script:runId; origin_run_url = "$script:runBase$script:runId"
        run_id = $script:runId; run_attempt = $script:attempt
        source_sha = Get-SandboxSource; configuration = Get-SandboxFingerprints
        plan_path = $script:plan; plan_sha256 = Get-SandboxHash $script:plan
        created_at = [DateTimeOffset]::UtcNow.ToString('o'); changes = $counts
    }
}

function Invoke-SandboxApply {
    $status = Read-SandboxJson (Join-Path $script:directory 'preflight-status.json')
    if ($status.exit_code -isnot [long] -or $status.exit_code -ne 0) {
        Stop-SandboxStage 'Apply requires a successful preflight.'
    }
    $record = Confirm-SandboxReceipt
    Write-SandboxLog "Verified plan SHA-256: $($record.plan_sha256)`n"
    $deploymentProfile = Read-SandboxJson (Join-Path $script:directory 'profile.json')
    Connect-SandboxProvider $deploymentProfile 0 0
    Invoke-SandboxCommand @('terraform', 'apply', '-input=false', '-no-color', $script:plan)
    $names = Get-SandboxOutput @('terraform', 'output', '-json', 'resource_names') 'resource-names.json' | ConvertFrom-Json -AsHashtable
    Write-SandboxJson (Join-Path $script:directory 'resource-group.json') @{
        resource_group = Get-SandboxResourceGroupName $names
    }
}

function Invoke-SandboxUnitTest {
    $status = Read-SandboxJson (Join-Path $script:directory 'apply-status.json')
    if ($status.exit_code -isnot [long] -or $status.exit_code -ne 0) {
        Stop-SandboxStage 'Unit-test requires a successful apply.'
    }
    $null = Confirm-SandboxReceipt
    $deploymentProfile = Read-SandboxJson (Join-Path $script:directory 'profile.json')
    Connect-SandboxProvider $deploymentProfile 0 0
    Invoke-SandboxCommand @('bash', 'scripts/manage-vms.sh', 'start')
    $names = Get-SandboxOutput @('terraform', 'output', '-json', 'resource_names') 'resource-names.json' | ConvertFrom-Json -AsHashtable
    $resourceGroup = Get-SandboxResourceGroupName $names
    $vmNames = @($names.Keys | Where-Object { $_.StartsWith('virtual_machine_', [StringComparison]::Ordinal) } | ForEach-Object { $names[$_] })
    if ($vmNames.Count -eq 0) { Stop-SandboxStage 'Approved all-module scope must contain VMs.' }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $vms = @(Get-SandboxOutput @('az', 'vm', 'list', '-g', $resourceGroup, '-d', '--output', 'json') 'vm-status.json' | ConvertFrom-Json -AsHashtable)
        $states = @{}
        foreach ($vm in $vms) { $states[$vm['name']] = $vm['powerState'] }
        if (@($vmNames | Where-Object { $states[$_] -cne 'VM running' }).Count -eq 0) { break }
        if ($timer.Elapsed.TotalSeconds -ge 600) { Stop-SandboxStage 'VM-start gate did not confirm all deployed VMs running.' }
        Start-Sleep -Seconds 15
    }
    try {
        Invoke-SandboxCommand @('pwsh', '-NoLogo', '-NoProfile', '-File',
            'extras/configurations/rg-devops-iac/scripts/Connect-SandboxRunner.ps1',
            '-ProfilePath', (Join-Path $script:directory 'profile.json'), '-RunTests',
            '-ResultsJsonPath', (Join-Path $script:directory 'unit-test-results.json'))
    }
    finally {
        $orchestratorLog = Join-Path $script:root 'Invoke-UnitTests.ps1.log'
        if ([System.IO.File]::Exists($orchestratorLog)) {
            [System.IO.File]::Move($orchestratorLog, (Join-Path $script:directory 'orchestrator.log'), $true)
        }
    }
    if (-not [System.IO.File]::Exists((Join-Path $script:directory 'unit-test-results.json'))) {
        Stop-SandboxStage 'Tests completed without the requested JSON result file.' 2
    }
}

function Export-SandboxEvidence {
    $name = 'unit-test-results.json'
    $path = Join-Path $script:directory $name
    if (-not [System.IO.File]::Exists($path)) {
        Write-SandboxSummary "`nUnit-test evidence unavailable: no structured JSON result file was produced. No test results were fabricated.`n"
        [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT, "ready=false`ntests_passed=false`n", $script:utf8)
        return
    }
    $record = Read-SandboxJson $path
    if ($record -isnot [System.Collections.IDictionary] -or $record.schemaVersion -ne 1 -or
        $record.exitCode -isnot [long] -or $record.exitCode -notin @(0, 1, 2) -or
        $record['result'] -cnotin @('pass', 'fail', 'error') -or
        $record['totals'] -isnot [System.Collections.IDictionary]) {
        Stop-SandboxStage 'Invalid unit-test JSON; evidence was not published.'
    }
    $totals = $record['totals']
    foreach ($field in @('passed', 'failed', 'total', 'suitesFailed', 'suitesSkipped')) {
        if ($totals[$field] -isnot [long] -or $totals[$field] -lt 0) {
            Stop-SandboxStage 'Invalid unit-test totals; evidence was not published.'
        }
    }
    if ($totals['total'] -ne $totals['passed'] + $totals['failed']) {
        Stop-SandboxStage 'Inconsistent unit-test totals; evidence was not published.'
    }
    $testsPassed = ($record.exitCode -eq 0 -and $record['result'] -ceq 'pass' -and
        $totals['passed'] -gt 0 -and $totals['failed'] -eq 0 -and $totals['suitesFailed'] -eq 0).ToString().ToLowerInvariant()
    $staging = Join-Path $env:RUNNER_TEMP "sandbox-test-evidence-$script:runId-$script:attempt"
    if ([System.IO.Directory]::Exists($staging)) { Stop-SandboxStage 'Evidence staging directory already exists.' }
    $null = [System.IO.Directory]::CreateDirectory($staging)
    [System.IO.File]::SetUnixFileMode($staging, [System.IO.UnixFileMode]448)
    $jsonPath = Join-Path $staging $name
    # The private file has full detail (-VerboseResults); the published copy gets the same redaction as the job log.
    $context = Get-SandboxRedaction
    Write-SandboxJson $jsonPath (ConvertTo-SandboxRedactedValue -Value $record -KnownIds $context.KnownIds -Tags $context.Tags)
    [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT,
        "json_path=$jsonPath`nname=unit-test-evidence-$script:deploymentId-$script:runId-$script:attempt`nready=true`ntests_passed=$testsPassed`n", $script:utf8)
}

function Publish-SandboxTerraformError {
    # After a failed preflight or apply, shows the Terraform Error blocks in the job log (red), as an error annotation,
    # and saves them for the step summary. Shows nothing extra when the failure wasn't a Terraform error.
    try {
        $blocks = @(Get-SandboxTerraformError -Lines ([System.IO.File]::ReadAllLines($script:logPath, $script:utf8)))
    }
    catch [System.IO.IOException] {
        Write-SandboxLog "$($_ | Out-String)`n"
        Write-SandboxStatus "${Stage}: Terraform error details unavailable; see private diagnostics."
        return
    }
    catch [System.UnauthorizedAccessException] {
        Write-SandboxLog "$($_ | Out-String)`n"
        Write-SandboxStatus "${Stage}: Terraform error details unavailable; see private diagnostics."
        return
    }
    if ($blocks.Count -eq 0) { return }
    $context = Get-SandboxRedaction
    $report = ConvertTo-SandboxTerraformErrorReport -Blocks $blocks -KnownIds $context.KnownIds -Tags $context.Tags
    [System.IO.File]::WriteAllText((Join-Path $script:directory "$Stage-error.txt"), $report, $script:utf8)
    Write-SandboxStatus "${Stage}: Terraform reported $($blocks.Count) error block(s):"
    # Keeps a line of Terraform output from being run as a workflow command.
    $token = [guid]::NewGuid().ToString('N')
    Write-SandboxStatus "::stop-commands::$token"
    foreach ($line in @($report -split '\n')) { Write-SandboxStatus "`e[31m$line`e[0m" }
    Write-SandboxStatus "::${token}::"
    Write-SandboxStatus "::error title=Terraform $Stage failed::$(ConvertTo-SandboxAnnotationData $report)"
}

function Write-SandboxReport {
    $stages = [ordered]@{ preflight = 'PREFLIGHT_OUTCOME'; apply = 'APPLY_OUTCOME'; 'unit-test' = 'UNIT_TEST_OUTCOME' }
    $results = @{ success = 'PASS'; failure = 'FAIL'; skipped = 'NOT RUN'; cancelled = 'INCOMPLETE' }
    Write-SandboxSummary "## Sandbox stage results`n`n| Stage | Result |`n|---|---|`n"
    foreach ($name in $stages.Keys) {
        $outcome = [Environment]::GetEnvironmentVariable($stages[$name])
        $result = if ($outcome -and $results.ContainsKey($outcome)) { $results[$outcome] } else { 'NOT COMPLETED' }
        Write-SandboxSummary "| $name | $result |`n"
    }
    $resourceGroupPath = Join-Path $script:directory 'resource-group.json'
    if ([System.IO.File]::Exists($resourceGroupPath)) {
        $resourceGroup = Get-SandboxResourceGroupName (Read-SandboxJson $resourceGroupPath)
        Write-SandboxSummary "`nResource group: ``$resourceGroup```n"
    }
    else {
        Write-SandboxSummary "`nResource group: unavailable (no verified post-apply output was captured).`n"
    }
    foreach ($name in $stages.Keys) {
        $statusPath = Join-Path $script:directory "$name-status.json"
        if ([System.IO.File]::Exists($statusPath)) {
            $status = Read-SandboxJson $statusPath
            Write-SandboxSummary "`n${name}: exit ``$($status.exit_code)``, start ``$($status.started_at)``, end ``$($status.finished_at)``.`n`nPrivate log: ``~/.local/state/azuresandbox/deployments/$script:deploymentId/runs/$script:runId-$script:attempt/$name.log```n`n"
            $errorPath = Join-Path $script:directory "$name-error.txt"
            if ([System.IO.File]::Exists($errorPath)) {
                Write-SandboxSummary (ConvertTo-SandboxErrorMarkdown $name ([System.IO.File]::ReadAllText($errorPath)))
            }
        }
        elseif ([Environment]::GetEnvironmentVariable($stages[$name]) -notin @($null, '', 'skipped')) {
            Write-SandboxSummary "`n${name}: no final exit record; execution or result logging is incomplete.`n`n"
        }
    }
    if ([System.IO.File]::Exists($script:receipt)) {
        $record = Read-SandboxJson $script:receipt
        Write-SandboxSummary @"

Deployment: ``$script:deploymentId``; state key: ``$script:key``.

[Originating run]($script:runBase$script:runId) / [Current run]($script:runBase$script:runId)

Plan SHA-256: ``$($record.plan_sha256)``

Source commit: ``$($record.source_sha)``

Plan created: ``$($record.created_at)``; attempt: ``$script:attempt``.

Changes: create=$($record.changes.create), update=$($record.changes.update), delete=$($record.changes.delete).

Private plan: ``~/.local/state/azuresandbox/deployments/$script:deploymentId/runs/$script:runId-$script:attempt/sandbox.tfplan``

Preflight PASS is not proof that infrastructure was applied or tests passed.

"@
    }
    $resultsPath = Join-Path $script:directory 'unit-test-results.json'
    if ([System.IO.File]::Exists($resultsPath)) {
        $totals = (Read-SandboxJson $resultsPath).totals
        foreach ($name in @('passed', 'failed', 'suitesSkipped')) {
            if ($totals[$name] -isnot [long]) { Stop-SandboxStage 'Invalid unit-test totals; do not publish raw results.' }
        }
        Write-SandboxSummary "`nUnit-test counts: passed=$($totals.passed), failed=$($totals.failed), skipped suites=$($totals.suitesSkipped).`n"
    }
    if ($env:UNIT_TEST_ARTIFACT_OUTCOME -eq 'success' -and $env:UNIT_TEST_ARTIFACT_URL) {
        Write-SandboxSummary "`n[Download redacted unit-test evidence (JSON)]($env:UNIT_TEST_ARTIFACT_URL)`n"
    }
    elseif ($env:UNIT_TEST_ARTIFACT_OUTCOME -eq 'failure') {
        Write-SandboxSummary "`nUnit-test evidence upload failed; structured results remain on the runner.`n"
    }
}

function Get-SandboxInstance {
    # Id and private paths of sandbox Number in a multi-sandbox run. The parent and the sandbox's own process both use it.
    param([int]$Number)
    $id = "sandbox-$script:runId-$Number"
    $deployment = Join-Path $HOME ".local/state/azuresandbox/deployments/$id"
    [pscustomobject]@{
        Number     = $Number
        Id         = $id
        Deployment = $deployment
        Directory  = Join-Path $deployment "runs/$script:runId-$script:attempt"
        Source     = Join-Path $deployment "source/$script:runId-$script:attempt"
    }
}

function Receive-SandboxInstanceOutput {
    # Relays a sandbox process's new complete lines, prefixed with its id so they can't run as workflow commands.
    param($Child, [switch]$Final)
    if (-not [System.IO.File]::Exists($Child.Console)) { return }
    $stream = [System.IO.File]::Open($Child.Console, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $length = $stream.Length - $Child.Offset
        if ($length -le 0) { return }
        $buffer = [byte[]]::new($length)
        $stream.Position = $Child.Offset
        $read = 0
        while ($read -lt $length) {
            $chunk = $stream.Read($buffer, $read, $length - $read)
            if ($chunk -le 0) { break }
            $read += $chunk
        }
    }
    finally { $stream.Dispose() }
    # A newline byte is never part of a multi-byte UTF-8 character, so splitting there is safe.
    $end = if ($Final) { $read } else { [Array]::LastIndexOf($buffer, [byte]10, $read - 1) + 1 }
    if ($end -le 0) { return }
    $Child.Offset += $end
    foreach ($line in ($script:utf8.GetString($buffer, 0, $end).TrimEnd("`n") -split '\n')) {
        # Sandbox output can include Terraform and Azure error text; also neutralize the legacy ##[command] syntax.
        Write-SandboxStatus "[$($Child.Id)] $($line.TrimEnd("`r").Replace('##[', '## ['))"
    }
}

function Invoke-SandboxFanOut {
    # Runs this stage for every sandbox of a multi-sandbox run, each in its own process with its own source tree, state
    # key and private records. A failed sandbox doesn't stop the others; the stage fails if any sandbox fails.
    $ready = @(1..$script:count)
    if ($Stage -eq 'preflight') {
        Confirm-SandboxInvocation
        if ($env:RUNNER_NAME -cne 'jumplinux2') { Stop-SandboxStage 'Job did not run on the approved runner.' }
        Invoke-SandboxCommand @('git', '--version')
        # Installing Terraform uses sudo and replaces the shared CLI, so it runs once, before any sandbox starts.
        Confirm-SandboxTerraformVersion
        $backend = Get-SandboxBackend
        Invoke-SandboxCommand @('az', 'version')
        Invoke-SandboxCommand @('az', 'login', '--identity', '--allow-no-subscriptions', '--output', 'none')
        Invoke-SandboxGarbageCollection $backend
        # Each sandbox links providers from this cache instead of downloading about 730 MB. Only this init writes to it.
        $null = [System.IO.Directory]::CreateDirectory($script:childEnvironment['TF_PLUGIN_CACHE_DIR'])
        Invoke-SandboxCommand @('terraform', 'init', '-backend=false', '-input=false', '-no-color')
        foreach ($number in $ready) {
            $instance = Get-SandboxInstance $number
            $null = [System.IO.Directory]::CreateDirectory($instance.Deployment)
            [System.IO.File]::SetUnixFileMode($instance.Deployment, [System.IO.UnixFileMode]448)
            if ([System.IO.Directory]::Exists($instance.Source)) { Stop-SandboxStage 'This run attempt already has sandbox source trees.' }
            $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($instance.Source))
            # backend.tf and terraform.tfvars are written into the source tree, so each sandbox needs its own.
            Invoke-SandboxCommand @('git', 'worktree', 'add', '--detach', $instance.Source, 'HEAD')
        }
    }
    else {
        # All or nothing: apply starts only when every sandbox passed preflight.
        foreach ($number in $ready) {
            $statusPath = Join-Path (Get-SandboxInstance $number).Directory 'preflight-status.json'
            $status = if ([System.IO.File]::Exists($statusPath)) { Read-SandboxJson $statusPath } else { @{} }
            if ($status.exit_code -isnot [long] -or $status.exit_code -ne 0) {
                Stop-SandboxStage 'Apply requires a successful preflight for every sandbox.'
            }
        }
    }
    Write-SandboxStatus "${Stage}: starting $($ready.Count) of $script:count sandboxes in parallel."
    $pending = [System.Collections.Generic.Queue[int]]::new([int[]]$ready)
    $children = [System.Collections.Generic.List[object]]::new()
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $nextHeartbeat = 120
    $failures = [System.Collections.Generic.List[string]]::new()
    # Relayed sandbox output must never run as a workflow command, so command processing stays off until all of it is out.
    $token = [guid]::NewGuid().ToString('N')
    Write-SandboxStatus "::stop-commands::$token"
    try {
        while ($true) {
            # Starts are staggered so sign-ins and Azure Resource Manager writes don't all begin at once.
            if ($pending.Count -gt 0) {
                $number = $pending.Dequeue()
                $console = Join-Path $script:directory "sandbox-$number-$Stage.txt"
                $info = [System.Diagnostics.ProcessStartInfo]::new()
                $info.FileName = 'bash'
                $info.UseShellExecute = $false
                $info.WorkingDirectory = $script:root
                # The sandbox process inherits this process's environment, including the HCL secrets and the OIDC
                # token request variables that its own stage needs.
                foreach ($argument in @('-c', 'exec "$@" >"$0" 2>&1', $console, 'pwsh', '-NoLogo', '-NoProfile',
                        '-File', $PSCommandPath, '-Stage', $Stage, '-Instance', "$number")) {
                    $info.ArgumentList.Add($argument)
                }
                $process = [System.Diagnostics.Process]::Start($info)
                $children.Add([pscustomobject]@{
                        Number = $number; Id = "sandbox-$script:runId-$number"; Process = $process; Console = $console; Offset = 0L
                    })
            }
            foreach ($child in $children) { Receive-SandboxInstanceOutput $child }
            $running = @($children | Where-Object { -not $_.Process.HasExited }).Count
            if ($pending.Count -eq 0 -and $running -eq 0) { break }
            if ($timer.Elapsed.TotalSeconds -ge $nextHeartbeat) {
                $exited = @($children | Where-Object { $_.Process.HasExited })
                $passed = @($exited | Where-Object { $_.Process.ExitCode -eq 0 }).Count
                Write-SandboxStatus ("${Stage}: $([int][Math]::Floor($timer.Elapsed.TotalMinutes)) min elapsed; " +
                    "sandboxes running=$running, passed=$passed, failed=$($exited.Count - $passed), not started=$($pending.Count).")
                $nextHeartbeat += 120
            }
            Start-Sleep -Seconds 10
        }
        foreach ($child in $children) { $child.Process.WaitForExit(); Receive-SandboxInstanceOutput $child -Final }
        foreach ($child in $children) {
            $directory = (Get-SandboxInstance $child.Number).Directory
            $statusPath = Join-Path $directory "$Stage-status.json"
            $status = if ([System.IO.File]::Exists($statusPath)) { Read-SandboxJson $statusPath } else { @{} }
            if ($child.Process.ExitCode -eq 0 -and $status.exit_code -is [long] -and $status.exit_code -eq 0) { continue }
            $errorPath = Join-Path $directory "$Stage-error.txt"
            $message = if ([System.IO.File]::Exists($errorPath)) { [System.IO.File]::ReadAllText($errorPath) }
            else { "$Stage failed (exit $($child.Process.ExitCode)); review its private runner log." }
            $failures.Add("::error title=$($child.Id) $Stage failed::$(ConvertTo-SandboxAnnotationData $message)")
        }
    }
    finally {
        foreach ($child in $children) { $child.Process.Dispose() }
        Write-SandboxStatus "::${token}::"
    }
    foreach ($annotation in $failures) { Write-SandboxStatus $annotation }
    $failed = $failures.Count
    $succeeded = $children.Count - $failed
    Write-SandboxStatus "${Stage}: $succeeded of $($children.Count) sandboxes passed."
    if ($failed -gt 0) { Stop-SandboxStage "$failed of $($children.Count) sandboxes failed $Stage." }
}

function Get-SandboxStageResult {
    param([string]$Directory, [string]$Name)
    $statusPath = Join-Path $Directory "$Name-status.json"
    if (-not [System.IO.File]::Exists($statusPath)) { return 'NOT RUN' }
    $status = Read-SandboxJson $statusPath
    if ($status.exit_code -is [long] -and $status.exit_code -eq 0) { 'PASS' } else { 'FAIL' }
}

function Write-SandboxFleetReport {
    # Job summary for a multi-sandbox run, from each sandbox's private status files.
    $stages = @('preflight', 'apply')
    $succeeded = 0
    Write-SandboxSummary "## Sandbox results`n`n| Sandbox | Resource group | preflight | apply |`n|---|---|---|---|`n"
    foreach ($number in 1..$script:count) {
        $instance = Get-SandboxInstance $number
        $results = @{}
        foreach ($name in $stages) { $results[$name] = Get-SandboxStageResult $instance.Directory $name }
        if ($env:SANDBOX_RUN_THROUGH -ceq 'preflight' -and $results.apply -eq 'NOT RUN') { $results.apply = 'N/A' }
        if ($results[$env:SANDBOX_RUN_THROUGH] -eq 'PASS') { $succeeded++ }
        $resourceGroup = 'unavailable'
        $resourceGroupPath = Join-Path $instance.Directory 'resource-group.json'
        if ([System.IO.File]::Exists($resourceGroupPath)) {
            try { $resourceGroup = "``$(Get-SandboxResourceGroupName (Read-SandboxJson $resourceGroupPath))``" }
            catch { $resourceGroup = 'unavailable' }
        }
        Write-SandboxSummary "| ``$($instance.Id)`` | $resourceGroup | $($results.preflight) | $($results.apply) |`n"
    }
    Write-SandboxSummary "`nSucceeded through ``$env:SANDBOX_RUN_THROUGH``: $succeeded of $script:count. Failed or not run: $($script:count - $succeeded).`n`n"
    Write-SandboxSummary "[Originating run]($script:runBase$script:runId)`n`n"
    foreach ($name in $stages) {
        $statusPath = Join-Path $script:directory "$name-status.json"
        if ([System.IO.File]::Exists($statusPath)) {
            $status = Read-SandboxJson $statusPath
            Write-SandboxSummary "Run-wide ${name}: exit ``$($status.exit_code)``, start ``$($status.started_at)``, end ``$($status.finished_at)``. Private log: ``~/.local/state/azuresandbox/deployments/$script:deploymentId/runs/$script:runId-$script:attempt/$name.log```n`n"
        }
    }
    foreach ($number in 1..$script:count) {
        $instance = Get-SandboxInstance $number
        $runPath = "~/.local/state/azuresandbox/deployments/$($instance.Id)/runs/$script:runId-$script:attempt"
        Write-SandboxSummary "<details><summary>$($instance.Id)</summary>`n`nState key: ``sandboxes/$($instance.Id)/terraform.tfstate```n`n"
        $receiptPath = Join-Path $instance.Directory 'plan-receipt.json'
        if ([System.IO.File]::Exists($receiptPath)) {
            $record = Read-SandboxJson $receiptPath
            Write-SandboxSummary ("Source commit: ``$($record.source_sha)``; plan SHA-256: ``$($record.plan_sha256)``; " +
                "changes: create=$($record.changes.create), update=$($record.changes.update), delete=$($record.changes.delete).`n`n")
        }
        foreach ($name in $stages) {
            $statusPath = Join-Path $instance.Directory "$name-status.json"
            if (-not [System.IO.File]::Exists($statusPath)) { continue }
            $status = Read-SandboxJson $statusPath
            Write-SandboxSummary "${name}: exit ``$($status.exit_code)``, start ``$($status.started_at)``, end ``$($status.finished_at)``. Private log: ``$runPath/$name.log```n`n"
            $errorPath = Join-Path $instance.Directory "$name-error.txt"
            if ([System.IO.File]::Exists($errorPath)) {
                Write-SandboxSummary (ConvertTo-SandboxErrorMarkdown $name ([System.IO.File]::ReadAllText($errorPath)))
            }
        }
        Write-SandboxSummary "</details>`n`n"
    }
    Write-SandboxSummary "Preflight PASS is not proof that infrastructure was applied. Tear down each sandbox manually.`n"
}

function Remove-SandboxProviderCache {
    # Terraform links each provider in TF_DATA_DIR to this cache, so it's needed until the run's last stage.
    $cache = $script:childEnvironment['TF_PLUGIN_CACHE_DIR']
    if ([System.IO.Directory]::Exists($cache)) { [System.IO.Directory]::Delete($cache, $true) }
}

function Remove-SandboxFleetSource {
    # The source trees and provider cache are needed only by this run's stages. Plans and logs stay private on the runner.
    if (-not [System.IO.Directory]::Exists($script:directory)) { return }
    $script:logPath = Join-Path $script:directory 'summary.log'
    foreach ($number in 1..$script:count) {
        $source = (Get-SandboxInstance $number).Source
        if (-not [System.IO.Directory]::Exists($source)) { continue }
        if ((Invoke-SandboxCommand @('git', 'worktree', 'remove', '--force', $source) -AllowFailure) -ne 0) {
            Write-SandboxStatus "summary: could not remove the source tree of sandbox-$script:runId-$number; see the private summary log."
        }
    }
    $null = Invoke-SandboxCommand @('git', 'worktree', 'prune') -AllowFailure
    Remove-SandboxProviderCache
}

try {
    if (-not $IsLinux) { Stop-SandboxStage 'This runner helper requires Linux.' }
    foreach ($name in @('GITHUB_WORKSPACE', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SERVER_URL',
            'GITHUB_REPOSITORY', 'GITHUB_STEP_SUMMARY', 'SANDBOX_RUN_THROUGH')) {
        if (-not [Environment]::GetEnvironmentVariable($name)) { Stop-SandboxStage 'Required workflow metadata is missing.' }
    }
    if ($env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]*$' -or $env:GITHUB_RUN_ATTEMPT -cnotmatch '^[1-9][0-9]*$') {
        Stop-SandboxStage 'Invalid workflow run metadata.'
    }
    if ($env:SANDBOX_RUN_THROUGH -cnotin @('preflight', 'apply', 'unit-test') -or
        $env:SANDBOX_DEPLOYMENT_MODE -cnotin @($null, '', 'new') -or $env:SANDBOX_EXISTING_ID) {
        Stop-SandboxStage 'Automated deployments provision new Sandboxes only with a valid stage selection.'
    }
    $script:root = $env:GITHUB_WORKSPACE
    $script:runId = $env:GITHUB_RUN_ID
    $script:attempt = $env:GITHUB_RUN_ATTEMPT
    # SANDBOX_COUNT sandboxes (1-20) deploy in parallel. More than one runs a parent process that starts one process per
    # sandbox (-Instance); tests share host-wide state on the runner, so they run only for a single sandbox.
    $countText = if ($env:SANDBOX_COUNT) { $env:SANDBOX_COUNT } else { '1' }
    if ($countText -cnotmatch '^([1-9]|1[0-9]|20)$') { Stop-SandboxStage 'Invalid sandbox count.' }
    $script:count = [int]$countText
    if ($script:count -ne 1 -and ($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:SANDBOX_RUN_THROUGH -ceq 'unit-test')) {
        Stop-SandboxStage 'More than one sandbox is supported only for manual runs through preflight or apply.'
    }
    if ($Instance -gt $script:count -or ($Instance -and ($script:count -eq 1 -or $Stage -cnotin @('preflight', 'apply')))) {
        Stop-SandboxStage 'Invalid sandbox instance.'
    }
    $script:fanOut = $script:count -gt 1 -and -not $Instance
    $script:deploymentId = if ($Instance) { "sandbox-$script:runId-$Instance" } else { "sandbox-$script:runId" }
    $script:key = "sandboxes/$script:deploymentId/terraform.tfstate"
    $script:deploymentDirectory = Join-Path $HOME ".local/state/azuresandbox/deployments/$script:deploymentId"
    $script:directory = Join-Path $script:deploymentDirectory "runs/$script:runId-$script:attempt"
    if ($Instance) {
        $script:root = (Get-SandboxInstance $Instance).Source
        # Sandbox processes keep their summary private; the parent reports every sandbox.
        $env:GITHUB_STEP_SUMMARY = Join-Path $script:directory "$Stage-summary.md"
    }
    $script:plan = Join-Path $script:directory 'sandbox.tfplan'
    $script:receipt = Join-Path $script:directory 'plan-receipt.json'
    $script:runBase = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/"
    $script:jitRoles = [ordered]@{
        'Contributor'                             = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
        'Role Based Access Control Administrator' = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
    }
    $script:childEnvironment = @{}
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        if ($entry.Key -cnotmatch '^(TF_VAR_|ARM_|TF_CLI_ARGS)' -and
            $entry.Key -cnotin @('SANDBOX_BACKEND_HCL', 'SANDBOX_TFVARS_HCL')) {
            $script:childEnvironment[$entry.Key] = $entry.Value
        }
    }
    $script:childEnvironment['TF_IN_AUTOMATION'] = 'true'
    $script:childEnvironment['TF_INPUT'] = 'false'
    $script:childEnvironment['TF_DATA_DIR'] = Join-Path $script:directory 'terraform-data'
    $script:childEnvironment['AZURE_CONFIG_DIR'] = Join-Path $script:directory 'azure-cli'
    $script:childEnvironment['ARM_USE_MSI'] = 'true'
    $script:childEnvironment['TF_WORKSPACE'] = 'default'
    # Providers are downloaded once per run into this cache, and TF_DATA_DIR links to them; the summary stage removes it.
    $script:childEnvironment['TF_PLUGIN_CACHE_DIR'] = Join-Path $HOME (
        ".local/state/azuresandbox/deployments/sandbox-$script:runId/runs/$script:runId-$script:attempt/plugin-cache")
    if ($Stage -eq 'summary') {
        if ($script:fanOut) {
            Write-SandboxFleetReport
            Remove-SandboxFleetSource
        }
        else {
            try { Write-SandboxReport }
            finally { Remove-SandboxProviderCache }
        }
        exit 0
    }
    if ($Stage -eq 'preflight') {
        $null = [System.IO.Directory]::CreateDirectory($script:deploymentDirectory)
        [System.IO.File]::SetUnixFileMode($script:deploymentDirectory, [System.IO.UnixFileMode]448)
        if ([System.IO.Directory]::Exists($script:directory)) { Stop-SandboxStage 'This run attempt already has private records.' }
        $null = [System.IO.Directory]::CreateDirectory($script:directory)
    }
    $script:logPath = Join-Path $script:directory "$Stage.log"
    $stream = [System.IO.File]::Open($script:logPath, [System.IO.FileMode]::CreateNew)
    $stream.Dispose()
    $started = [DateTimeOffset]::UtcNow.ToString('o')
    $code = 0
    Write-SandboxLog "Stage: $Stage`nStarted: $started`n"
    try {
        switch ($Stage) {
            preflight { if ($script:fanOut) { Invoke-SandboxFanOut } else { Invoke-SandboxPreflight } }
            apply { if ($script:fanOut) { Invoke-SandboxFanOut } else { Invoke-SandboxApply } }
            unit-test { Invoke-SandboxUnitTest }
        }
    }
    catch {
        Write-SandboxLog "$($_ | Out-String)`n$($_.ScriptStackTrace)`n"
        $code = if ($_.Exception.Data.Contains('ExitCode')) { [int]$_.Exception.Data['ExitCode'] } else { 1 }
    }
    finally {
        # Don't leave the stage's Azure CLI tokens on the runner; the next stage signs in again.
        $azureConfig = $script:childEnvironment['AZURE_CONFIG_DIR']
        if ([System.IO.Directory]::Exists($azureConfig)) { [System.IO.Directory]::Delete($azureConfig, $true) }
    }
    if ($code -ne 0 -and $Stage -in @('preflight', 'apply')) {
        try { Publish-SandboxTerraformError }
        catch {
            Write-SandboxLog "$($_ | Out-String)`n$($_.ScriptStackTrace)`n"
            Write-SandboxStatus "${Stage}: Terraform error details unavailable; see private diagnostics."
        }
    }
    if ($Stage -eq 'unit-test') {
        try { Export-SandboxEvidence }
        catch {
            Write-SandboxLog "$($_ | Out-String)`n$($_.ScriptStackTrace)`n"
            Write-SandboxSummary "`nUnit-test evidence preparation failed; no artifact was approved for upload. Check the private result files and staging permissions.`n"
            if ($code -eq 0) { $code = 1 }
        }
    }
    $finished = [DateTimeOffset]::UtcNow.ToString('o')
    Write-SandboxLog "`nFinished: $finished`nStage exit code: $code`n"
    Write-SandboxJson (Join-Path $script:directory "$Stage-status.json") @{
        started_at = $started; finished_at = $finished; exit_code = $code
    }
    if ($code -ne 0) { Write-SandboxStatus "::error::$Stage failed (exit $code); review its private runner log." }
    else { Write-SandboxStatus "${Stage}: PASS. Raw output retained privately on the runner." }
    exit $code
}
catch {
    Write-Host '::error::Runner setup/reporting failed; check workflow inputs, private records, and filesystem permissions.'
    exit 1
}
