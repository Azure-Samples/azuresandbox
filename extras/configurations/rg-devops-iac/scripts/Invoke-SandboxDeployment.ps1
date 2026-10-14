#requires -Version 7.3

param(
    [Parameter(Mandatory)]
    [ValidateSet('preflight', 'apply', 'unit-test', 'summary')]
    [string]$Stage
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SandboxProgress.ps1')
$script:utf8 = [System.Text.UTF8Encoding]::new($false)

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

function Write-SandboxSummary {
    param([string]$Text)
    [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $Text, $script:utf8)
}

function Write-SandboxJson {
    param([string]$Path, $Value)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30) + "`n", $script:utf8)
}

function Read-SandboxJson {
    param([string]$Path)
    ConvertFrom-Json -AsHashtable -InputObject ([System.IO.File]::ReadAllText($Path))
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
        [AllowNull()][string]$InputText
    )
    Write-SandboxLog "`n[$([DateTimeOffset]::UtcNow.ToString('o'))] $($Arguments | ConvertTo-Json -Compress)`n"
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
            Write-Host "${Stage}: $([int][Math]::Floor($timer.Elapsed.TotalMinutes)) min elapsed; $health."
            if ($Stage -in @('apply', 'unit-test') -and $size -gt $lastSize) {
                try {
                    foreach ($line in @(Read-SandboxProgress -Path $script:logPath -Start $lastSize -Stage $Stage)) {
                        Write-Host "  $line"
                    }
                }
                catch [System.IO.IOException] {
                    Write-SandboxLog "$($_ | Out-String)`n"
                    $size = ([System.IO.FileInfo]::new($script:logPath)).Length
                    Write-Host "${Stage}: sanitized progress preview unavailable; see private diagnostics."
                }
                catch [System.UnauthorizedAccessException] {
                    Write-SandboxLog "$($_ | Out-String)`n"
                    $size = ([System.IO.FileInfo]::new($script:logPath)).Length
                    Write-Host "${Stage}: sanitized progress preview unavailable; see private diagnostics."
                }
            }
            $lastSize = $size
        }
        Write-SandboxLog ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
        $code = $process.ExitCode
        Write-SandboxLog "[$([DateTimeOffset]::UtcNow.ToString('o'))] Exit code: $code`n"
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

function Connect-SandboxProvider {
    param([System.Collections.IDictionary]$DeploymentProfile)
    $script:childEnvironment['ARM_TENANT_ID'] = $DeploymentProfile.aad_tenant_id
    Invoke-SandboxCommand @('az', 'login', '--identity', '--client-id', $DeploymentProfile.arm_client_id, '--output', 'none')
    Invoke-SandboxCommand @('az', 'account', 'set', '--subscription', $DeploymentProfile.subscription_id)
    $account = Get-SandboxOutput @('az', 'account', 'show', '--output', 'json') 'account.json' | ConvertFrom-Json -AsHashtable
    if ($account.id -cne $DeploymentProfile.subscription_id -or $account.tenantId -cne $DeploymentProfile.aad_tenant_id) {
        Stop-SandboxStage 'Azure CLI context does not match the approved deployment.'
    }
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
    if ([string]::IsNullOrWhiteSpace($env:SANDBOX_BACKEND_HCL) -or [string]::IsNullOrWhiteSpace($env:SANDBOX_TFVARS_HCL)) {
        Stop-SandboxStage 'Both environment HCL secrets are required.'
    }
    $backendText = $env:SANDBOX_BACKEND_HCL
    foreach ($name in @('backend.tf', 'terraform.tfvars')) {
        $text = if ($name -eq 'backend.tf') { $backendText } else { $env:SANDBOX_TFVARS_HCL }
        $path = Join-Path $script:root $name
        [System.IO.File]::WriteAllText($path, $text, $script:utf8)
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]384)
        [System.IO.File]::Copy($path, (Join-Path $script:directory $name), $false)
    }
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
    $script:childEnvironment['ARM_TENANT_ID'] = $backend.tenant_id
    Write-SandboxSummary "## Sandbox target`n`nDeployment: ``$script:deploymentId```n`nState key: ``$script:key```n`n[Originating run]($script:runBase$script:runId) / [Current run]($script:runBase$script:runId)`n`n"
    Invoke-SandboxCommand @('git', '--version')
    Invoke-SandboxCommand @('terraform', 'version')
    Invoke-SandboxCommand @('az', 'version')
    Invoke-SandboxCommand @('az', 'login', '--identity', '--allow-no-subscriptions', '--output', 'none')
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
    Invoke-SandboxCommand @('terraform', 'init', '-input=false', "-backend-config=key=$script:key")
    Invoke-SandboxCommand @('terraform', 'validate', '-no-color')
    $expression = 'jsonencode({arm_auth_mode=var.arm_auth_mode,arm_client_id=var.arm_client_id,aad_tenant_id=var.aad_tenant_id,subscription_id=var.subscription_id,base=[var.enable_module_vnet_app,var.enable_module_vm_jumpbox_linux,var.enable_module_vm_mssql_win,var.enable_module_mssql,var.enable_module_mysql,var.enable_module_vwan],extras=[var.enable_module_avd,var.enable_module_petstore,var.enable_module_vnet_onprem]})' + "`n"
    $console = Get-SandboxOutput -Arguments @('terraform', 'console', '-no-color') -Name 'console.txt' -InputText $expression
    $deploymentProfile = ConvertFrom-Json -AsHashtable -InputObject (ConvertFrom-Json -InputObject $console)
    if ($deploymentProfile.arm_auth_mode -cne 'msi' -or $deploymentProfile.aad_tenant_id -cne $backend.tenant_id -or
        $deploymentProfile.subscription_id -cne $backend.subscription_id -or -not $deploymentProfile.arm_client_id -or
        @($deploymentProfile.base | Where-Object { $_ -isnot [bool] -or -not $_ }).Count -gt 0 -or
        @($deploymentProfile.extras | Where-Object { $_ -isnot [bool] -or $_ }).Count -gt 0) {
        Stop-SandboxStage 'Inputs do not match the approved MSI, backend, or module scope.'
    }
    Write-SandboxJson (Join-Path $script:directory 'profile.json') $deploymentProfile
    Connect-SandboxProvider $deploymentProfile
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
    Connect-SandboxProvider (Read-SandboxJson (Join-Path $script:directory 'profile.json'))
    Invoke-SandboxCommand @('terraform', 'apply', '-input=false', '-no-color', $script:plan)
}

function Invoke-SandboxUnitTest {
    $status = Read-SandboxJson (Join-Path $script:directory 'apply-status.json')
    if ($status.exit_code -isnot [long] -or $status.exit_code -ne 0) {
        Stop-SandboxStage 'Unit-test requires a successful apply.'
    }
    $null = Confirm-SandboxReceipt
    Connect-SandboxProvider (Read-SandboxJson (Join-Path $script:directory 'profile.json'))
    Invoke-SandboxCommand @('bash', 'scripts/manage-vms.sh', 'start')
    $names = Get-SandboxOutput @('terraform', 'output', '-json', 'resource_names') 'resource-names.json' | ConvertFrom-Json -AsHashtable
    $vmNames = @($names.Keys | Where-Object { $_.StartsWith('virtual_machine_', [StringComparison]::Ordinal) } | ForEach-Object { $names[$_] })
    if ($vmNames.Count -eq 0) { Stop-SandboxStage 'Approved all-module scope must contain VMs.' }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $vms = @(Get-SandboxOutput @('az', 'vm', 'list', '-g', $names.resource_group, '-d', '--output', 'json') 'vm-status.json' | ConvertFrom-Json -AsHashtable)
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
        [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT, "ready=false`n", $script:utf8)
        return
    }
    $record = Read-SandboxJson $path
    if ($record -isnot [System.Collections.IDictionary] -or $record.schemaVersion -ne 1 -or
        $record.exitCode -isnot [long] -or $record.exitCode -notin @(0, 1, 2)) {
        Stop-SandboxStage 'Invalid unit-test JSON; evidence was not published.'
    }
    $staging = Join-Path $env:RUNNER_TEMP "sandbox-test-evidence-$script:runId-$script:attempt"
    if ([System.IO.Directory]::Exists($staging)) { Stop-SandboxStage 'Evidence staging directory already exists.' }
    $null = [System.IO.Directory]::CreateDirectory($staging)
    [System.IO.File]::SetUnixFileMode($staging, [System.IO.UnixFileMode]448)
    $jsonPath = Join-Path $staging $name
    [System.IO.File]::Copy($path, $jsonPath, $false)
    [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT,
        "json_path=$jsonPath`nname=unit-test-evidence-$script:deploymentId-$script:runId-$script:attempt`nready=true`n", $script:utf8)
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
    foreach ($name in $stages.Keys) {
        $statusPath = Join-Path $script:directory "$name-status.json"
        if ([System.IO.File]::Exists($statusPath)) {
            $status = Read-SandboxJson $statusPath
            Write-SandboxSummary "`n${name}: exit ``$($status.exit_code)``, start ``$($status.started_at)``, end ``$($status.finished_at)``.`n`nPrivate log: ``~/.local/state/azuresandbox/deployments/$script:deploymentId/runs/$script:runId-$script:attempt/$name.log```n`n"
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
        Write-SandboxSummary "`n[Download sanitized unit-test evidence (JSON)]($env:UNIT_TEST_ARTIFACT_URL)`n"
    }
    elseif ($env:UNIT_TEST_ARTIFACT_OUTCOME -eq 'failure') {
        Write-SandboxSummary "`nUnit-test evidence upload failed; structured results remain on the runner.`n"
    }
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
    $script:deploymentId = "sandbox-$script:runId"
    $script:key = "sandboxes/$script:deploymentId/terraform.tfstate"
    $script:deploymentDirectory = Join-Path $HOME ".local/state/azuresandbox/deployments/$script:deploymentId"
    $script:directory = Join-Path $script:deploymentDirectory "runs/$script:runId-$script:attempt"
    $script:plan = Join-Path $script:directory 'sandbox.tfplan'
    $script:receipt = Join-Path $script:directory 'plan-receipt.json'
    $script:runBase = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/"
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
    if ($Stage -eq 'summary') {
        Write-SandboxReport
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
            preflight { Invoke-SandboxPreflight }
            apply { Invoke-SandboxApply }
            unit-test { Invoke-SandboxUnitTest }
        }
    }
    catch {
        Write-SandboxLog "$($_ | Out-String)`n$($_.ScriptStackTrace)`n"
        $code = if ($_.Exception.Data.Contains('ExitCode')) { [int]$_.Exception.Data['ExitCode'] } else { 1 }
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
    if ($code -ne 0) { Write-Host "::error::$Stage failed (exit $code); review its private runner log." }
    else { Write-Host "${Stage}: PASS. Raw output retained privately on the runner." }
    exit $code
}
catch {
    Write-Host '::error::Runner setup/reporting failed; check workflow inputs, private records, and filesystem permissions.'
    exit 1
}
