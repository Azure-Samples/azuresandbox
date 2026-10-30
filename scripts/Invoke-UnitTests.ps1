#requires -Version 7.0
# Az modules are imported explicitly in the main region rather than via '#requires -Modules':
# with Az modules loaded by '#requires', 'pwsh -File' discards the script's exit code (always 0).

# Overview:
#   This script is the unit/integration test orchestrator for the sandbox. It auto-discovers
#   which modules are actually deployed (via `terraform output`) and runs the appropriate unit
#   tests for each. Integration tests are dispatched per-module to the scripts/Test-Integration-*.ps1
#   helpers; do not invoke those helpers directly (the orchestrator populates their parameters —
#   resource names, FQDNs — from Terraform outputs). Exit code is 0 (pass) / 1 (fail) for CI use;
#   tests require an applied sandbox in the current Terraform state.
#
# Test scope rules (important):
#   - No -Module  -> runs unit tests for ALL installed modules. Integration tests for those
#                    modules are run AUTOMATICALLY. The -Integration switch does NOT apply here
#                    and is ignored when -Module is omitted.
#   - -Module X   -> runs only module X's unit tests.
#   - -Module X -Integration -> runs module X's unit tests AND its integration tests.
#   In short: -Integration is meaningful ONLY together with -Module (a single-module run).
#
# Usage:
#   Step 1: Authenticate to Azure (one-time, persisted to ~/.Azure/)
#     From bash:       pwsh -Command 'Connect-AzAccount -UseDeviceAuthentication'
#     From PowerShell: Connect-AzAccount -UseDeviceAuthentication
#
#   Step 2: Run unit tests for all installed modules (integration tests run automatically)
#     From bash:       pwsh -File ./scripts/Invoke-UnitTests.ps1
#     From PowerShell: .\scripts\Invoke-UnitTests.ps1
#
#   Step 2 (alt): Run unit tests for a single module
#     From bash:       pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vnet_shared
#     From PowerShell: .\scripts\Invoke-UnitTests.ps1 -Module vnet_app
#
#   Step 2 (alt): Run a single module's unit tests AND its integration tests
#     From bash:       pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vnet_app -Integration
#     From PowerShell: .\scripts\Invoke-UnitTests.ps1 -Module vm_mssql_win -Integration
#
#   Valid module names: vnet_shared, vnet_app, vm_jumpbox_linux, vm_mssql_win, mssql, mysql,
#                       vwan, vnet_onprem, avd, petstore (ai_foundry is not currently supported)
#
#   Optional: emit machine-readable JSON results for CI/CD (any scope above)
#     From bash:       pwsh -File ./scripts/Invoke-UnitTests.ps1 -ResultsJsonPath ./test-results.json
#     From PowerShell: .\scripts\Invoke-UnitTests.ps1 -Module vnet_app -ResultsJsonPath .\test-results.json
#   Results are sanitized by default. Add -VerboseResults for the original
#   environment-specific check text and diagnostics (private use only).
#
# Exit codes: 0 = all tests passed, 1 = one or more tests failed, 2 = harness error (bad
#   parameters, missing Azure auth / terraform state, etc. - no or partial tests ran).
#
# Machine-readable results (-ResultsJsonPath):
#   Off by default; supplying the path does not change the exit code, log file, or console
#   output. JSON is written on every exit (0, 1, and 2), relative paths resolve against the
#   current directory, and missing parent directories are created. Per-check detail is parsed
#   from the '[MODULE:<name>] [PASS|FAIL|SKIP] <message>' lines every test script emits; a
#   following 'FAIL Exception: ...' line is attached as detail to the preceding failed check.
#   - JSON (schemaVersion 1): result ('pass'|'fail'|'error'), exitCode, error, module,
#     integration, startedAt/finishedAt (UTC ISO 8601), durationSeconds, totals, and suites[]
#     (one per module test config or integration test; name, type 'module'|'integration',
#     module, target, status 'passed'|'failed'|'skipped', passed, failed, skipped, skipReason,
#     attempts, retryReason, startedAt, durationSeconds, checks[] of { name, status, message }).
#     attempts is 1 for a suite that ran once, 2 when it was re-run after a VM reboot (see
#     below), and 0 for a skipped suite; retryReason is null or a static reason string. Suite and overall
#     passed/failed counts mirror the log's [SUMMARY] counts (the exit-code source of truth).
#     If a test script reports more failures than [FAIL] lines, an 'Unattributed failures'
#     check is added; if a script cannot be run or parsed, a 'Test harness' check is added.
#   Default JSON preserves counts/statuses and static child check descriptions,
#   excluding runtime values and exception text. -VerboseResults restores full detail
#   in JSON. General console/log diagnostics remain private.
#
# VM readiness and reboot-aware retry:
#   - mssqlwin1 is stopped/deallocated/started before its suite to exercise its startup task.
#     It counts as ready only when SQL Server is running, the Set-MssqlStartupConfiguration task
#     ran after the last boot and succeeded, and the boot time is unchanged across two probes
#     (the task itself may reboot the VM). A pending-reboot flag is logged as a warning.
#   - Any VM can reboot unexpectedly (automatic patching, Azure Policy, Defender for Servers), which
#     kills an in-flight run command. When a VM-based module or integration suite fails, the boot
#     time of each watched VM (the VM the suite runs on plus its RequiredVMs) is checked. If one
#     rebooted during the suite, the harness waits for it to settle and re-runs the suite once;
#     only the retry's results count, and the suite is annotated (attempts / retryReason). If the
#     retry is also interrupted by a reboot, the suite fails with a 'VM rebooted during test
#     execution' harness error. Passing suites incur no extra probes. Local suites are not retried.
#
# Prerequisites:
#   - PowerShell 7.x (pwsh) with Az.Accounts, Az.Compute, Az.Resources, Az.Sql, Az.Network,
#     Az.PrivateDns, Az.MySql, and Az.DesktopVirtualization installed (missing modules exit 2)
#   - Authenticated Azure session (see Step 1 above)
#   - Terraform CLI in PATH with initialized state in the repo root
#   - All VMs started before running (a policy may deallocate them); a deallocated domain
#     controller (adds1) breaks AD DNS, Kerberos, domain join, CIFS, and SQL auth. Start with
#     ./scripts/manage-vms.sh start and confirm all report 'VM running' before testing.

param(
    [Parameter(Mandatory = $false)]
    [string]$Module,

    [Parameter(Mandatory = $false)]
    [switch]$Integration,

    [Parameter(Mandatory = $false)]
    [string]$ResultsJsonPath,

    [Parameter(Mandatory = $false)]
    [switch]$VerboseResults
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
    Write-ResultFiles -ExitCode 2 -ErrorMessage $msg
    exit 2
}

function Remove-AnsiEscape {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    return ($Value -replace '\x1B\[[0-9;?]*[ -/]*[@-~]', '')
}

function Get-PublicTestDescriptions {
    param([string]$ScriptPath)

    $descriptions = [System.Collections.Generic.List[string]]::new()
    if ([IO.Path]::GetExtension($ScriptPath) -eq '.ps1') {
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw 'Cannot parse child test descriptions.' }
        foreach ($command in $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-TestResult'
                }, $true)) {
            for ($index = 0; $index -lt $command.CommandElements.Count - 1; $index++) {
                $element = $command.CommandElements[$index]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -eq 'SanitizedMessage') {
                    $label = $command.CommandElements[$index + 1]
                    if ($label -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        throw 'Public child descriptions must be static strings.'
                    }
                    $descriptions.Add($label.Value)
                }
            }
        }
    }
    else {
        foreach ($line in [IO.File]::ReadAllLines($ScriptPath)) {
            if ($line -match "^\s*write_test_result\s+'(?:PASS|FAIL|SKIP)'.*\s+'([^']*)'\s*$") {
                $descriptions.Add($Matches[1])
            }
        }
    }
    return , $descriptions.ToArray()
}

function ConvertFrom-TestOutput {
    # Parses the per-check protocol shared by all test scripts: '[MODULE:<name>] [PASS|FAIL|SKIP] <message>'.
    # A 'FAIL Exception: ...' line, and any untimestamped continuation lines of a multi-line
    # message, are detail for the preceding failed check rather than separate checks.
    param(
        [string[]]$Lines,
        [string[]]$PublicDescriptions = @()
    )

    $statusMap = @{ PASS = 'passed'; FAIL = 'failed'; SKIP = 'skipped' }
    $parsed = [System.Collections.Generic.List[object]]::new()
    $current = $null

    foreach ($entry in $Lines) {
        foreach ($line in ((Remove-AnsiEscape "$entry") -split '\r?\n')) {
            $trimmed = $line.Trim()
            if (-not $trimmed) { continue }

            if ($trimmed -match '\[MODULE:[^\]]*\]\s+\[(PASS|FAIL|SKIP)\]\s?(.*)$') {
                $status = $statusMap[$Matches[1]]
                $text = $Matches[2].Trim()
                if ($status -eq 'failed' -and $text -like 'Exception:*' -and $current -and $current.Status -eq 'failed') {
                    $current.Details.Add($text)
                    continue
                }
                $current = @{ Name = $text; Status = $status; Details = [System.Collections.Generic.List[string]]::new() }
                $parsed.Add($current)
            }
            elseif ($current -and $current.Status -eq 'failed' -and $trimmed -notmatch '^\d{4}-?\d{2}-?\d{2}[T ]') {
                $current.Details.Add($trimmed)
            }
            else {
                $current = $null
            }
        }
    }

    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $parsed) {
        $name = $p.Name
        if (-not $VerboseResults -and $name -notin $PublicDescriptions) {
            Write-Log '[WARNING] Child emitted an unrecognized check description; runtime text withheld from results.'
            $name = 'Unrecognized check description (details withheld)'
        }
        $checks.Add([ordered]@{
                name    = $name
                status  = $p.Status
                message = if ($VerboseResults -and $p.Details.Count -gt 0) { $p.Details -join "`n" } else { $null }
            })
    }
    return , $checks.ToArray()
}

function Get-UtcTimestamp {
    param([datetime]$Date = (Get-Date))
    return $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [cultureinfo]::InvariantCulture)
}

function Add-SuiteResult {
    param(
        [string]$Name,
        [string]$Type,
        [string]$ModuleName,
        [string]$Target,
        [hashtable]$TestResult,
        [datetime]$StartedAt,
        [System.Diagnostics.Stopwatch]$Stopwatch
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @($TestResult.Checks)) { if ($c) { $checks.Add($c) } }

    if ($TestResult.HarnessError) {
        $detail = if ($VerboseResults) { Remove-AnsiEscape $TestResult.HarnessError }
        elseif ($TestResult.PublicHarnessError) { $TestResult.PublicHarnessError }
        else { 'Child test execution or summary parsing failed. Use -VerboseResults for private diagnostics.' }
        $checks.Add([ordered]@{ name = 'Test harness'; status = 'failed'; message = $detail })
    }
    else {
        $attributed = @($checks | Where-Object { $_.status -eq 'failed' }).Count
        if ($TestResult.Failed -gt $attributed) {
            $checks.Add([ordered]@{
                    name    = 'Unattributed failures'
                    status  = 'failed'
                    message = "[SUMMARY] reported $($TestResult.Failed) failed check(s) but only $attributed [FAIL] line(s) were emitted; see the log file for details."
                })
        }
    }

    $script:suiteResults.Add([ordered]@{
            name            = $Name
            type            = $Type
            module          = $ModuleName
            target          = $Target
            status          = if ($TestResult.Failed -gt 0) { 'failed' } else { 'passed' }
            passed          = [int]$TestResult.Passed
            failed          = [int]$TestResult.Failed
            skipped         = @($checks | Where-Object { $_.status -eq 'skipped' }).Count
            skipReason      = $null
            attempts        = if ($TestResult.Attempts) { [int]$TestResult.Attempts } else { 1 }
            retryReason     = if ($TestResult.RetryReason) { $TestResult.RetryReason } else { $null }
            startedAt       = Get-UtcTimestamp $StartedAt
            durationSeconds = [math]::Round($Stopwatch.Elapsed.TotalSeconds, 3)
            checks          = $checks.ToArray()
        })
}

function Add-SkippedSuite {
    param(
        [string]$Name,
        [string]$Type,
        [string]$ModuleName,
        [string]$Target,
        [string]$Reason
    )

    $script:suiteResults.Add([ordered]@{
            name            = $Name
            type            = $Type
            module          = $ModuleName
            target          = $Target
            status          = 'skipped'
            passed          = 0
            failed          = 0
            skipped         = 0
            skipReason      = $Reason
            attempts        = 0
            retryReason     = $null
            startedAt       = Get-UtcTimestamp
            durationSeconds = 0
            checks          = @()
        })
}

function Write-ResultFiles {
    # Best-effort: a failure to write results is logged but never changes the exit code.
    param(
        [int]$ExitCode,
        [string]$ErrorMessage
    )

    if (-not $script:resultsJsonFullPath) { return }

    $ErrorMessage = Remove-AnsiEscape $ErrorMessage
    if ($ErrorMessage -and -not $VerboseResults) {
        $ErrorMessage = 'Test harness error. Use -VerboseResults for private diagnostics.'
    }
    $finishedAt = Get-Date
    $startedAt = if ($script:runStartedAt) { $script:runStartedAt } else { $finishedAt }
    $durationSeconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    $suites = if ($script:suiteResults) { $script:suiteResults.ToArray() } else { @() }
    $passed = [int]$script:overallPassed
    $failed = [int]$script:overallFailed

    if ($script:resultsJsonFullPath) {
        try {
            $doc = [ordered]@{
                schemaVersion   = 1
                generator       = 'scripts/Invoke-UnitTests.ps1'
                result          = switch ($ExitCode) { 0 { 'pass' } 1 { 'fail' } default { 'error' } }
                exitCode        = $ExitCode
                error           = if ($ErrorMessage) { $ErrorMessage } else { $null }
                module          = if ($Module -and ($VerboseResults -or $Module -in @('vnet_shared', 'vnet_app', 'vm_jumpbox_linux', 'vm_mssql_win', 'mssql', 'mysql', 'vwan', 'vnet_onprem', 'avd', 'petstore', 'ai_foundry'))) { $Module } else { $null }
                integration     = [bool]$Integration
                startedAt       = Get-UtcTimestamp $startedAt
                finishedAt      = Get-UtcTimestamp $finishedAt
                durationSeconds = $durationSeconds
                totals          = [ordered]@{
                    passed        = $passed
                    failed        = $failed
                    total         = $passed + $failed
                    suites        = $suites.Count
                    suitesFailed  = @($suites | Where-Object { $_.status -eq 'failed' }).Count
                    suitesSkipped = @($suites | Where-Object { $_.status -eq 'skipped' }).Count
                }
                suites          = $suites
            }
            $dir = Split-Path $script:resultsJsonFullPath -Parent
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $doc | ConvertTo-Json -Depth 10 | Set-Content -Path $script:resultsJsonFullPath -Encoding utf8NoBOM
            Write-Log "Results JSON: $($script:resultsJsonFullPath)"
        }
        catch {
            Write-Log "[WARNING] Failed to write results JSON '$($script:resultsJsonFullPath)': $_"
        }
    }
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

    $testResult = @{ Passed = 0; Failed = 1; Checks = @(); HarnessError = $null }

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "[WARNING] Test script not found: $ScriptPath. Skipping."
        $testResult.HarnessError = "Test script not found: $ScriptPath"
        return $testResult
    }

    Write-Log "Executing test script on VM '$VMName' via run command..."

    try {
        $publicDescriptions = Get-PublicTestDescriptions -ScriptPath $ScriptPath
        $runParams = @{
            ResourceGroupName = $ResourceGroupName
            VMName            = $VMName
            CommandId         = $CommandId
            ScriptPath        = $ScriptPath
            ErrorAction       = 'Stop'
        }

        $childParameters = @{} + $Parameters
        $childParameters['VerboseResults'] = ([bool]$VerboseResults).ToString().ToLowerInvariant()
        $runParams['Parameter'] = $childParameters

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
        $lines = @()

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
            $testResult.Passed = [int]$Matches[1]
            $testResult.Failed = [int]$Matches[2]
        }
        else {
            Write-Log "[WARNING] Could not parse summary line from '$Label'. Treating as failure."
            $testResult.HarnessError = "Could not parse the [SUMMARY] line from the test output (VM '$VMName'). Treating as failure."
        }
        $testResult.Checks = ConvertFrom-TestOutput -Lines $lines -PublicDescriptions $publicDescriptions
    }
    catch {
        Write-Log "[$Label] [FAIL] Failed to execute tests on VM '$VMName'"
        Write-Log "[$Label] [FAIL] Exception: $_"
        $testResult.HarnessError = "Failed to execute tests on VM '$VMName'. Exception: $_"
    }

    return $testResult
}

function Invoke-LocalTest {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters,
        [string]$Label
    )

    $testResult = @{ Passed = 0; Failed = 1; Checks = @(); HarnessError = $null }
    $publicDescriptions = @()

    if (-not (Test-Path $ScriptPath)) {
        Write-Log "[WARNING] Test script not found: $ScriptPath. Skipping."
        $testResult.HarnessError = "Test script not found: $ScriptPath"
        return $testResult
    }

    Write-Log "Executing test script locally..."

    try {
        $publicDescriptions = Get-PublicTestDescriptions -ScriptPath $ScriptPath
        # Stream output line-by-line so progress is visible in real time
        $collectedLines = [System.Collections.Generic.List[string]]::new()

        $childParameters = @{} + $Parameters
        $childParameters['VerboseResults'] = ([bool]$VerboseResults).ToString().ToLowerInvariant()
        & $ScriptPath @childParameters 2>&1 | ForEach-Object {
            $line = "$_".Trim()
            if ($line) {
                Write-Log $line
                $collectedLines.Add($line)
            }
        }

        # Parse summary line
        $summaryLine = $collectedLines | Where-Object { $_ -match '\[SUMMARY\]' } | Select-Object -Last 1
        if ($summaryLine -match 'Passed:\s*(\d+)\s+Failed:\s*(\d+)\s+Total:\s*(\d+)') {
            $testResult.Passed = [int]$Matches[1]
            $testResult.Failed = [int]$Matches[2]
        }
        else {
            Write-Log "[WARNING] Could not parse summary line from '$Label'. Treating as failure."
            $testResult.HarnessError = "Could not parse the [SUMMARY] line from the local test output. Treating as failure."
        }
        $testResult.Checks = ConvertFrom-TestOutput -Lines $collectedLines.ToArray() -PublicDescriptions $publicDescriptions
    }
    catch {
        Write-Log "[$Label] [FAIL] Failed to execute local tests"
        Write-Log "[$Label] [FAIL] Exception: $_"
        $testResult.HarnessError = "Failed to execute local tests. Exception: $_"
        if ($collectedLines) { $testResult.Checks = ConvertFrom-TestOutput -Lines $collectedLines.ToArray() -PublicDescriptions $publicDescriptions }
    }

    return $testResult
}

function Get-RunCommandStdOut {
    # Windows (RunPowerShellScript) returns ComponentStatus/StdOut; Linux (RunShellScript) returns a
    # single ProvisioningState/succeeded value with combined output.
    param($Result)
    $value = $Result.Value | Where-Object { $_.Code -like '*StdOut*' } | Select-Object -First 1
    if (-not $value) { $value = $Result.Value | Where-Object { $_.Code -like '*succeeded*' } | Select-Object -First 1 }
    return "$($value.Message)"
}

function Invoke-VMProbeScript {
    # Runs a short probe script on a VM via run command and returns its stdout.
    param(
        [string]$ResourceGroupName,
        [string]$VMName,
        [string]$CommandId,
        [string]$ScriptText
    )

    $extension = if ($CommandId -eq 'RunShellScript') { '.sh' } else { '.ps1' }
    $probePath = Join-Path ([System.IO.Path]::GetTempPath()) ("probe-$([guid]::NewGuid().ToString('N'))$extension")
    try {
        Set-Content -Path $probePath -Value $ScriptText
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId $CommandId -ScriptPath $probePath -ErrorAction Stop
        return Get-RunCommandStdOut $result
    }
    finally {
        Remove-Item $probePath -Force -ErrorAction SilentlyContinue
    }
}

function ConvertFrom-ProbeTimestamp {
    # Accepts an ISO 8601 string or a DateTime (ConvertFrom-Json converts ISO strings to DateTime).
    param([object]$Value)
    if (-not $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) }
        return $Value.ToUniversalTime()
    }
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.UtcDateTime
    }
    return $null
}

function Get-VMOsType {
    param(
        [string]$ResourceGroupName,
        [string]$VMName
    )
    if (-not $script:vmOsTypes.ContainsKey($VMName)) {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
        $script:vmOsTypes[$VMName] = [string]$vm.StorageProfile.OsDisk.OsType
    }
    return $script:vmOsTypes[$VMName]
}

function Get-VMLastBootTime {
    # Returns the VM's last OS boot time (UTC), or $null if it cannot be determined.
    param(
        [string]$ResourceGroupName,
        [string]$VMName
    )

    try {
        if ((Get-VMOsType -ResourceGroupName $ResourceGroupName -VMName $VMName) -eq 'Linux') {
            $stdout = Invoke-VMProbeScript -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId 'RunShellScript' -ScriptText "awk '/^btime/ { print `"BOOT_EPOCH=`" `$2 }' /proc/stat"
            if ($stdout -match 'BOOT_EPOCH=(\d+)') {
                return [datetimeoffset]::FromUnixTimeSeconds([long]$Matches[1]).UtcDateTime
            }
        }
        else {
            $stdout = Invoke-VMProbeScript -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId 'RunPowerShellScript' -ScriptText "'BOOT=' + (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')"
            if ($stdout -match 'BOOT=(\S+)') {
                return ConvertFrom-ProbeTimestamp $Matches[1]
            }
        }
        Write-Log "[WARNING] Could not parse the last boot time of VM '$VMName'."
    }
    catch {
        Write-Log "[WARNING] Could not read the last boot time of VM '$VMName': $_"
    }
    return $null
}

function Get-RebootedVM {
    # Returns the VMs (from -VMNames) whose last boot time is later than -SinceUtc.
    param(
        [string]$ResourceGroupName,
        [string[]]$VMNames,
        [datetime]$SinceUtc
    )

    $rebooted = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $VMNames) {
        $boot = Get-VMLastBootTime -ResourceGroupName $ResourceGroupName -VMName $name
        if ($boot -and $boot -gt $SinceUtc) {
            Write-Log "VM '$name' last booted at $(Get-UtcTimestamp $boot), after the suite started at $(Get-UtcTimestamp $SinceUtc)."
            $rebooted.Add($name)
        }
    }
    return , $rebooted.ToArray()
}

function Wait-MssqlReady {
    # Waits until the SQL Server VM has finished its startup configuration on a stable boot:
    #   - MSSQLSERVER is Running
    #   - the Set-MssqlStartupConfiguration task is not running, ran after the last boot, and succeeded
    #   - the last boot time is unchanged across two consecutive probes
    # The startup task can restart the VM (e.g. after rebuilding the temp disk following a deallocate),
    # so a Running service alone is not proof the VM has settled. A pending reboot flag (e.g. Windows
    # Update) is logged as a warning; the reboot-aware retry covers a reboot during the tests.
    param(
        [string]$ResourceGroupName,
        [string]$VMName
    )

    Write-Log "Waiting for VM '$VMName' to complete startup configuration..."
    $probeScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$info = Get-ScheduledTaskInfo -TaskName 'Set-MssqlStartupConfiguration'
$task = Get-ScheduledTask -TaskName 'Set-MssqlStartupConfiguration'
$cbs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$wu = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
'READY_PROBE=' + ([ordered]@{
    Service       = [string](Get-Service -Name MSSQLSERVER).Status
    BootUtc       = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
    TaskState     = [string]$task.State
    TaskLastRun   = if ($info.LastRunTime) { $info.LastRunTime.ToUniversalTime().ToString('o') } else { $null }
    TaskResult    = $info.LastTaskResult
    RebootPending = (Test-Path $cbs) -or (Test-Path $wu)
} | ConvertTo-Json -Compress)
'@

    $previousBoot = $null
    for ($attempt = 1; $attempt -le $script:readinessMaxAttempts; $attempt++) {
        Start-Sleep -Seconds $script:readinessIntervalSeconds

        try {
            $stdout = Invoke-VMProbeScript -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId 'RunPowerShellScript' -ScriptText $probeScript
            if ($stdout -notmatch 'READY_PROBE=(\{.*\})') { throw 'Probe returned no readiness data.' }
            $state = $Matches[1] | ConvertFrom-Json
            $boot = ConvertFrom-ProbeTimestamp $state.BootUtc
            $lastRun = ConvertFrom-ProbeTimestamp $state.TaskLastRun
            $taskDone = $state.TaskState -ne 'Running' -and $lastRun -and $boot -and $lastRun -gt $boot -and $state.TaskResult -eq 0
            $stableBoot = $boot -and $previousBoot -and $boot -eq $previousBoot

            if ($state.Service -eq 'Running' -and $taskDone -and $stableBoot) {
                if ($state.RebootPending) {
                    Write-Log "[WARNING] VM '$VMName' reports a pending reboot (e.g. Windows Update). Proceeding; a reboot during the tests triggers one retry."
                }
                Write-Log "VM '$VMName' is ready - startup configuration completed and SQL Server service is running."
                return $true
            }

            Write-Log "VM '$VMName' probe attempt $attempt/$($script:readinessMaxAttempts) - SQL Server: $($state.Service), startup task: $($state.TaskState) (result: $($state.TaskResult), ran this boot: $([bool]($lastRun -and $boot -and $lastRun -gt $boot))), boot stable: $([bool]$stableBoot)"
            $previousBoot = $boot
        }
        catch {
            Write-Log "VM '$VMName' probe attempt $attempt/$($script:readinessMaxAttempts) - VM agent not ready yet."
            $previousBoot = $null
        }
    }

    Write-Log "[WARNING] VM '$VMName' may not be fully ready after $($script:readinessMaxAttempts) probe attempts. Proceeding with tests."
    return $false
}

function Wait-VMSettled {
    # Waits for a VM that rebooted to settle: its boot time is readable and unchanged across two
    # consecutive probes and it has been up for at least the minimum settle time. The SQL Server VM
    # uses its stricter startup-configuration readiness check instead.
    param(
        [string]$ResourceGroupName,
        [string]$VMName
    )

    if ($script:mssqlVmName -and $VMName -eq $script:mssqlVmName) {
        return Wait-MssqlReady -ResourceGroupName $ResourceGroupName -VMName $VMName
    }

    Write-Log "Waiting for VM '$VMName' to settle after a reboot..."
    $previousBoot = $null
    for ($attempt = 1; $attempt -le $script:readinessMaxAttempts; $attempt++) {
        Start-Sleep -Seconds $script:readinessIntervalSeconds
        $boot = Get-VMLastBootTime -ResourceGroupName $ResourceGroupName -VMName $VMName
        $uptimeSeconds = if ($boot) { [math]::Round(((Get-Date).ToUniversalTime() - $boot).TotalSeconds) } else { 0 }
        $stableBoot = $boot -and $previousBoot -and [math]::Abs(($boot - $previousBoot).TotalSeconds) -le 5
        if ($stableBoot -and $uptimeSeconds -ge $script:minSettledUptimeSeconds) {
            Write-Log "VM '$VMName' has settled (up for $uptimeSeconds s)."
            return $true
        }
        Write-Log "VM '$VMName' settle probe $attempt/$($script:readinessMaxAttempts) - boot stable: $([bool]$stableBoot), uptime: $uptimeSeconds s"
        $previousBoot = $boot
    }

    Write-Log "[WARNING] VM '$VMName' may not have settled after $($script:readinessMaxAttempts) probe attempts. Proceeding."
    return $false
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

    # The startup scheduled task (Set-MssqlStartupConfiguration.ps1) runs at boot. After a deallocate
    # the temp disk is wiped, so the task rebuilds it, reconfigures the pagefile and restarts the VM
    # once more; SQL Server is started on the following boot.
    $null = Wait-MssqlReady -ResourceGroupName $ResourceGroupName -VMName $VMName
}

function Test-SuiteFailed {
    param([hashtable]$TestResult)
    return [bool]($TestResult.HarnessError -or $TestResult.Failed -gt 0)
}

function Invoke-VMTestWithRebootRetry {
    # Runs a VM-based suite. If it fails and any watched VM (the VM the suite runs on, plus any VMs it
    # depends on) rebooted while it ran, waits for the rebooted VMs to settle and re-runs the suite
    # once. Only the final attempt's results are reported. Boot times are probed only after a
    # failure, so passing suites cost nothing extra.
    param(
        [string]$ResourceGroupName,
        [string]$VMName,
        [string]$CommandId,
        [string]$ScriptPath,
        [hashtable]$Parameters,
        [string]$Label,
        [string[]]$WatchedVMs
    )

    $watched = @($WatchedVMs | Where-Object { $_ } | Select-Object -Unique)
    $attemptStartUtc = (Get-Date).ToUniversalTime()
    $testResult = Invoke-VMTest -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId $CommandId -ScriptPath $ScriptPath -Parameters $Parameters -Label $Label
    $testResult.Attempts = 1
    $testResult.RetryReason = $null

    if (-not (Test-SuiteFailed $testResult) -or $watched.Count -eq 0) { return $testResult }

    $rebooted = Get-RebootedVM -ResourceGroupName $ResourceGroupName -VMNames $watched -SinceUtc $attemptStartUtc
    if ($rebooted.Count -eq 0) { return $testResult }

    Write-Log "[WARNING] [$Label] VM(s) '$($rebooted -join "', '")' rebooted during test execution. Waiting for them to settle and retrying the suite once."
    foreach ($name in $rebooted) {
        $null = Wait-VMSettled -ResourceGroupName $ResourceGroupName -VMName $name
    }

    $attemptStartUtc = (Get-Date).ToUniversalTime()
    $retryResult = Invoke-VMTest -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId $CommandId -ScriptPath $ScriptPath -Parameters $Parameters -Label $Label
    $retryResult.Attempts = 2
    $retryResult.RetryReason = $script:rebootRetryReason

    if (Test-SuiteFailed $retryResult) {
        $reboundAgain = Get-RebootedVM -ResourceGroupName $ResourceGroupName -VMNames $watched -SinceUtc $attemptStartUtc
        if ($reboundAgain.Count -gt 0) {
            Write-Log "[$Label] [FAIL] VM(s) '$($reboundAgain -join "', '")' rebooted again during the retry."
            $retryResult.HarnessError = "VM(s) '$($reboundAgain -join "', '")' rebooted during test execution; the retry was also interrupted."
            $retryResult.PublicHarnessError = 'VM rebooted during test execution; the retry was also interrupted.'
            if ($retryResult.Failed -lt 1) { $retryResult.Failed = 1 }
        }
        else {
            Write-Log "[$Label] Retry after VM reboot also failed."
        }
    }
    else {
        Write-Log "[$Label] Retry after VM reboot passed."
    }

    return $retryResult
}
#endregion

#region main
$script:logPath = Join-Path $PWD 'Invoke-UnitTests.ps1.log'
$repoRoot = Split-Path $PSScriptRoot -Parent
$script:runStartedAt = Get-Date
$script:suiteResults = [System.Collections.Generic.List[object]]::new()
$script:resultsJsonFullPath = if ($ResultsJsonPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultsJsonPath) } else { $null }
# VM readiness / reboot-aware retry settings
$script:readinessMaxAttempts = 20
$script:readinessIntervalSeconds = 30
$script:minSettledUptimeSeconds = 120
$script:rebootRetryReason = 'VM rebooted during test execution'
$script:vmOsTypes = @{}
$script:mssqlVmName = $null

# Clear previous log
if (Test-Path $script:logPath) { Remove-Item $script:logPath -Force }

Write-Log "Starting unit test collection..."
Write-Log "Log file: $($script:logPath)"

try {
    Import-Module Az.Accounts, Az.Compute, Az.Resources, Az.Sql, Az.Network, Az.PrivateDns, Az.MySql, Az.DesktopVirtualization -ErrorAction Stop
}
catch {
    Exit-WithError "Required Az PowerShell modules could not be imported. Install them with 'Install-Module Az -Scope CurrentUser'. Exception: $_"
}

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
$script:mssqlVmName = $resourceNames['virtual_machine_mssqlwin1']

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
    'vnet_onprem'      = 'virtual_machine_adds2'
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
    'vnet_onprem'      = @('Onprem -> cloud connectivity', 'Cloud -> onprem DNS')
}

# Pre-validate sudo early if vwan integration tests will run (avoids waiting for prompt mid-test)
$willRunVwanIntegration = ((-not $Module) -or ($Module -eq 'vwan' -and $Integration)) -and $resourceNames['virtual_wan'] -and $resourceNames['virtual_wan_hub']
if ($willRunVwanIntegration -and ($IsLinux -or $IsMacOS)) {
    Write-Log "Pre-validating sudo access for vwan integration test..."
    # Probe an allowed command (cat); command-scoped NOPASSWD won't permit 'true'.
    & sudo -n cat /dev/null 2>&1 | Out-Null
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
            KeyVaultName                = $resourceNames['key_vault']
            StorageAccountName          = $resourceNames['storage_account']
            StorageShareName            = $resourceNames['storage_share']
            ApplicationInsightsName     = $resourceNames['application_insights']
            MonitorPrivateLinkScopeName = $resourceNames['monitor_private_link_scope']
            ResourceGroupName           = $resourceGroupName
            SubscriptionId              = $context.Subscription.Id
            LogAnalyticsWorkspaceId     = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$($resourceNames['log_analytics_workspace'])"
            # Mirrors root main.tf install_ssms / install_mysql_workbench wiring, derived from deployed modules.
            ExpectSsms                  = ($resourceNames.ContainsKey('mssql_server') -or $resourceNames.ContainsKey('virtual_machine_mssqlwin1')).ToString().ToLower()
            ExpectMysqlWorkbench        = $resourceNames.ContainsKey('mysql_server').ToString().ToLower()
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
    # Control-plane checks for the always-on vnet_shared module that do not need to run
    # VM-side on the domain controller (e.g. the Azure Firewall diagnostic setting). Running
    # these in the orchestrator's authenticated Az session avoids granting adds1 a standing
    # Monitoring Reader role. VM-side vnet_shared checks remain in Test-VnetShared.ps1.
    '$local_vnet_shared' = @{
        Module     = 'vnet-shared'
        ModuleName = 'vnet_shared'
        RunLocal   = $true
        ScriptPath = Join-Path $repoRoot 'modules' 'vnet-shared' 'scripts' 'Test-VnetSharedLocal.ps1'
        Parameters = @{
            ResourceGroupName = $resourceGroupName
            FirewallName      = $resourceNames['firewall']
            BastionName       = $resourceNames['bastion_host']
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
            ApplicationInsightsName      = $resourceNames['application_insights']
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
    'virtual_machine_adds2' = @{
        Module     = 'vnet-onprem'
        ModuleName = 'vnet_onprem'
        ScriptPath = Join-Path $repoRoot 'extras' 'modules' 'vnet-onprem' 'scripts' 'Test-VnetOnpremAdds.ps1'
        CommandId  = 'RunPowerShellScript'
        Parameters = @{}
    }
    'virtual_machine_jumpwin2' = @{
        Module     = 'vnet-onprem'
        ModuleName = 'vnet_onprem'
        ScriptPath = Join-Path $repoRoot 'extras' 'modules' 'vnet-onprem' 'scripts' 'Test-VnetOnpremJumpbox.ps1'
        CommandId  = 'RunPowerShellScript'
        Parameters = @{}
    }
    '$local_vnet_onprem' = @{
        Module     = 'vnet-onprem'
        ModuleName = 'vnet_onprem'
        RunLocal   = $true
        ScriptPath = Join-Path $repoRoot 'extras' 'modules' 'vnet-onprem' 'scripts' 'Test-VnetOnpremLocal.ps1'
        Parameters = @{
            ResourceGroupName      = $resourceGroupName
            VnetOnpremName         = $resourceNames['virtual_network_onprem']
            PrivateDnsResolverName = $resourceNames['private_dns_resolver']
        }
    }
}

# Filter to single module if specified
if ($Module) {
    $targetVmKey = $moduleToVmKey[$Module]
    $filteredConfigs = [ordered]@{}

    # Include all test configs that belong to this module (handles modules with multiple test configs)
    foreach ($key in $testConfigs.Keys) {
        if ($key -eq $targetVmKey -or $testConfigs[$key].ModuleName -eq $Module) {
            $filteredConfigs[$key] = $testConfigs[$key]
        }
    }

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
            Add-SkippedSuite -Name "$($config.Module) (local)" -Type 'module' -ModuleName $config.ModuleName -Target 'local' -Reason 'Required terraform outputs not found (module not deployed).'
            continue
        }

        Write-Log "========================================"
        Write-Log "Module: $($config.Module) | Local"
        Write-Log "========================================"

        $suiteTarget = 'local'
        $suiteStartedAt = Get-Date
        $suiteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $testResult = Invoke-LocalTest -ScriptPath $config.ScriptPath -Parameters $config.Parameters -Label "MODULE:$($config.Module)"
    }
    else {
        # VM-based test
        $vmName = $resourceNames[$configKey]
        $suiteTarget = $configKey -replace '^virtual_machine_', ''

        if (-not $vmName) {
            Write-Log "Skipping module '$($config.Module)': VM key '$configKey' not found in terraform outputs (module not deployed)."
            Add-SkippedSuite -Name "$($config.Module) ($suiteTarget)" -Type 'module' -ModuleName $config.ModuleName -Target $suiteTarget -Reason "VM key '$configKey' not found in terraform outputs (module not deployed)."
            continue
        }

        Write-Log "========================================"
        Write-Log "Module: $($config.Module) | VM: $vmName"
        Write-Log "========================================"

        $suiteStartedAt = Get-Date
        $suiteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Stop/deallocate and restart VM if required (tests startup configuration after temp disk wipe)
        if ($config.StopDeallocateBeforeTest) {
            try {
                Invoke-VMStopDeallocateStart -ResourceGroupName $resourceGroupName -VMName $vmName
            }
            catch {
                Write-Log "[MODULE:$($config.Module)] [FAIL] Failed to stop/deallocate/start VM '$vmName': $_"
                $overallFailed++
                $moduleResults += @{ Module = $config.Module; Passed = 0; Failed = 1 }
                Add-SuiteResult -Name "$($config.Module) ($suiteTarget)" -Type 'module' -ModuleName $config.ModuleName -Target $suiteTarget -StartedAt $suiteStartedAt -Stopwatch $suiteStopwatch -TestResult @{
                    Passed = 0; Failed = 1; Checks = @(); HarnessError = "Failed to stop/deallocate/start VM '$vmName': $_"
                }
                continue
            }
        }

        $testResult = Invoke-VMTestWithRebootRetry -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId $config.CommandId -ScriptPath $config.ScriptPath -Parameters $config.Parameters -Label "MODULE:$($config.Module)" -WatchedVMs @($vmName)
    }
    $overallPassed += $testResult.Passed
    $overallFailed += $testResult.Failed
    $moduleResults += @{ Module = $config.Module; Passed = $testResult.Passed; Failed = $testResult.Failed; RetryReason = $testResult.RetryReason }
    Add-SuiteResult -Name "$($config.Module) ($suiteTarget)" -Type 'module' -ModuleName $config.ModuleName -Target $suiteTarget -TestResult $testResult -StartedAt $suiteStartedAt -Stopwatch $suiteStopwatch
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
                PetstoreFqdn                    = $fqdns['petstore']
                LogAnalyticsWorkspaceResourceId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$($resourceNames['log_analytics_workspace'])"
                ExpectedRoleName                = 'petstore'
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
        @{
            Name        = 'Onprem -> cloud connectivity'
            RequiredVMs = @('virtual_machine_jumpwin2')
            RunOnVM     = 'virtual_machine_jumpwin2'
            ScriptPath  = Join-Path $repoRoot 'scripts' 'Test-Integration-OnpremToCloudDns.ps1'
            CommandId   = 'RunPowerShellScript'
            Parameters  = @{
                JumpLinuxFqdn      = if ($resourceNames['virtual_machine_jumplinux1']) { "$($resourceNames['virtual_machine_jumplinux1']).$addsDomainName" } else { '' }
                MssqlWinFqdn       = if ($resourceNames['virtual_machine_mssqlwin1']) { "$($resourceNames['virtual_machine_mssqlwin1']).$addsDomainName" } else { '' }
                MssqlServerFqdn    = if ($fqdns['mssql_server']) { $fqdns['mssql_server'] } else { '' }
                MysqlServerFqdn    = if ($fqdns['mysql_server']) { $fqdns['mysql_server'] } else { '' }
                StorageAccountName = if ($resourceNames['storage_account']) { $resourceNames['storage_account'] } else { '' }
                JumpWinCloudFqdn   = if ($resourceNames['virtual_machine_jumpwin1']) { "$($resourceNames['virtual_machine_jumpwin1']).$addsDomainName" } else { '' }
            }
        }
        @{
            Name        = 'Cloud -> onprem DNS'
            RequiredVMs = @('virtual_machine_jumpwin1', 'virtual_machine_jumpwin2')
            RunOnVM     = 'virtual_machine_jumpwin1'
            ScriptPath  = Join-Path $repoRoot 'scripts' 'Test-Integration-CloudToOnpremDns.ps1'
            CommandId   = 'RunPowerShellScript'
            Parameters  = @{}
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
        $suiteName = "integration: $($test.Name)"
        $suiteTarget = if ($test.RunLocal) { 'local' } else { $test.RunOnVM -replace '^virtual_machine_', '' }

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
            Add-SkippedSuite -Name $suiteName -Type 'integration' -ModuleName $null -Target $suiteTarget -Reason "Required VM '$missingVm' not deployed."
            continue
        }

        # Check required FQDN is available (for tests that depend on PaaS modules)
        if ($test.RequiredFqdn -and -not $fqdns[$test.RequiredFqdn]) {
            Write-Log "Skipping integration test '$($test.Name)': required FQDN '$($test.RequiredFqdn)' not found in terraform outputs (module not deployed)."
            Add-SkippedSuite -Name $suiteName -Type 'integration' -ModuleName $null -Target $suiteTarget -Reason "Required FQDN '$($test.RequiredFqdn)' not found in terraform outputs (module not deployed)."
            continue
        }

        # For local integration tests, skip if required parameters are missing (module not deployed)
        if ($test.RunLocal) {
            $skipLocal = $false
            foreach ($key in @('ResourceGroupName', 'KeyVaultName', 'VirtualWanName', 'VirtualHubName')) {
                if ($test.Parameters.ContainsKey($key) -and -not $test.Parameters[$key]) {
                    Write-Log "Skipping integration test '$($test.Name)': required parameter '$key' not found in terraform outputs (module not deployed)."
                    Add-SkippedSuite -Name $suiteName -Type 'integration' -ModuleName $null -Target $suiteTarget -Reason "Required parameter '$key' not found in terraform outputs (module not deployed)."
                    $skipLocal = $true
                    break
                }
            }
            if ($skipLocal) { continue }
        }

        $suiteStartedAt = Get-Date
        $suiteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        if ($test.RunLocal) {
            # Local integration test (e.g. P2S VPN from Terraform execution environment)
            Write-Log "========================================"
            Write-Log "Integration: $($test.Name) | Local"
            Write-Log "========================================"

            # Pre-validate sudo: prompt interactively if needed, or rely on passwordless in CI.
            # Probe an allowed command (cat); command-scoped NOPASSWD won't permit 'true'.
            if ($test.RequiresSudo -and ($IsLinux -or $IsMacOS)) {
                & sudo -n cat /dev/null 2>&1 | Out-Null
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

            # Watch the VM the test runs on and every VM it depends on (e.g. the SQL Server VM).
            $watchedVMs = @(@($test.RunOnVM) + @($test.RequiredVMs) | ForEach-Object { $resourceNames[$_] } | Where-Object { $_ } | Select-Object -Unique)
            $testResult = Invoke-VMTestWithRebootRetry -ResourceGroupName $resourceGroupName -VMName $vmName -CommandId $test.CommandId -ScriptPath $test.ScriptPath -Parameters $test.Parameters -Label "INTEGRATION:$($test.Name)" -WatchedVMs $watchedVMs
        }
        $overallPassed += $testResult.Passed
        $overallFailed += $testResult.Failed
        $moduleResults += @{ Module = "integration: $($test.Name)"; Passed = $testResult.Passed; Failed = $testResult.Failed; RetryReason = $testResult.RetryReason }
        Add-SuiteResult -Name $suiteName -Type 'integration' -ModuleName $null -Target $suiteTarget -TestResult $testResult -StartedAt $suiteStartedAt -Stopwatch $suiteStopwatch
    }
}

# Final summary
Write-Log "========================================"
Write-Log "UNIT TEST RESULTS SUMMARY"
Write-Log "========================================"
foreach ($mr in $moduleResults) {
    $status = if ($mr.Failed -gt 0) { 'FAIL' } else { 'PASS' }
    $retryNote = if ($mr.RetryReason) { " (retried once: $($mr.RetryReason))" } else { '' }
    Write-Log "  [$status] $($mr.Module): Passed=$($mr.Passed) Failed=$($mr.Failed)$retryNote"
}
$overallTotal = $overallPassed + $overallFailed
Write-Log "Overall: Passed=$overallPassed Failed=$overallFailed Total=$overallTotal"

if ($overallFailed -gt 0) {
    Write-Log "RESULT: FAIL"
    Write-ResultFiles -ExitCode 1
    exit 1
}
else {
    Write-Log "RESULT: PASS"
    Write-ResultFiles -ExitCode 0
    exit 0
}
#endregion
