#requires -Version 7.2

param(
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]*$')][string]$RunId,
    [ValidatePattern('^[1-9][0-9]*$')][string]$Attempt = '1',
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SandboxProgress.ps1')
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Invoke-SandboxSystemCommand {
    param([string[]]$Arguments)
    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo.FileName = $Arguments[0]
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        foreach ($argument in $Arguments[1..($Arguments.Count - 1)]) {
            $process.StartInfo.ArgumentList.Add($argument)
        }
        if (-not $process.Start()) { throw 'Monitor command did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text = $stdout.GetAwaiter().GetResult()
        $diagnostics = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Monitor command failed (exit $($process.ExitCode)): $diagnostics"
        }
        return $text.Trim()
    }
    finally { $process.Dispose() }
}

function Get-SandboxProcessCount {
    $counts = @{ 'Runner.Listener' = 0; 'Runner.Worker' = 0; terraform = 0; pwsh = 0 }
    foreach ($directory in [System.IO.Directory]::EnumerateDirectories('/proc')) {
        $processId = [System.IO.Path]::GetFileName($directory)
        if ($processId -cnotmatch '^[0-9]+$' -or $processId -eq "$PID") { continue }
        try { $name = [System.IO.File]::ReadAllText((Join-Path $directory 'comm')).Trim() }
        catch [System.IO.FileNotFoundException] { continue }
        catch [System.IO.DirectoryNotFoundException] { continue }
        if ($counts.ContainsKey($name)) { $counts[$name]++ }
    }
    return $counts
}

function Get-SandboxLogInfo {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    $info = [System.IO.FileInfo]::new($Path)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $buffer = [byte[]]::new(512)
        $length = $stream.Read($buffer, 0, $buffer.Length)
        $header = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $length)
    }
    finally { $stream.Dispose() }
    $elapsed = $null
    $started = [regex]::Match($header, '(?m)^Started: (.+)$')
    if ($started.Success) {
        $when = [DateTimeOffset]::Parse($started.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        $elapsed = [long][Math]::Max(0, [Math]::Floor(([DateTimeOffset]::UtcNow - $when).TotalSeconds))
    }
    @{
        bytes = $info.Length
        modified = ([DateTimeOffset]$info.LastWriteTimeUtc).ToUnixTimeMilliseconds() / 1000.0
        elapsed_seconds = $elapsed
    }
}

if (-not $IsLinux) { throw 'This monitor requires Linux.' }
$null = [System.IO.Directory]::CreateDirectory($OutputDirectory)
[System.IO.File]::SetUnixFileMode($OutputDirectory, [System.IO.UnixFileMode]448)
$units = Invoke-SandboxSystemCommand @('systemctl', 'list-units', '--all', '--type=service',
    '--plain', '--no-legend', 'actions.runner.*')
$services = @($units -split '\r?\n' | Where-Object { $_.Trim() } | ForEach-Object { ($_.Trim() -split '\s+')[0] })
if ($services.Count -ne 1) { throw 'Expected exactly one runner service.' }
$unit = $services[0]
$user = Invoke-SandboxSystemCommand @('systemctl', 'show', $unit, '--property=User', '--value')
$account = Invoke-SandboxSystemCommand @('getent', 'passwd', $user)
$fields = $account -split ':'
if ($fields.Count -ne 7 -or -not $fields[5]) { throw 'Could not resolve the runner service home directory.' }
$directory = Join-Path $fields[5] ".local/state/azuresandbox/deployments/sandbox-$RunId/runs/$RunId-$Attempt"
$previous = $null
$timer = [System.Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalSeconds -lt 21600) {
    $service = Invoke-SandboxSystemCommand @('systemctl', 'show', $unit, '--property=ActiveState', '--value')
    $stages = @{}
    $stage = 'awaiting-job'
    $logInfo = $null
    $logPath = $null
    foreach ($name in @('preflight', 'apply', 'unit-test')) {
        $statusPath = Join-Path $directory "$name-status.json"
        if ([System.IO.File]::Exists($statusPath)) {
            $status = ConvertFrom-Json -AsHashtable -InputObject ([System.IO.File]::ReadAllText($statusPath))
            if ($status.exit_code -isnot [long]) { throw 'Invalid stage exit code.' }
            $stages[$name] = @{ exit_code = $status.exit_code }
        }
        $path = Join-Path $directory "$name.log"
        $info = Get-SandboxLogInfo $path
        if ($null -ne $info) { $stage = $name; $logInfo = $info; $logPath = $path }
    }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
    $changedAt = if ($null -eq $previous) { $now } else { $previous.changed_at }
    if ($null -eq $previous -or $stage -cne $previous.stage -or
        ($null -ne $logInfo -and ($null -eq $previous.log -or
            $logInfo.bytes -ne $previous.log.bytes -or $logInfo.modified -ne $previous.log.modified)) -or
        ($null -eq $logInfo -and $null -ne $previous.log)) {
        $changedAt = $now
    }
    $quiet = [long][Math]::Floor($now - $changedAt)
    $failed = @($stages.Values | Where-Object { $_.exit_code -ne 0 }).Count -gt 0
    $terminal = $failed -or $stages.ContainsKey('unit-test')
    $health = if ($stage -eq 'awaiting-job') { 'waiting' } else { 'healthy' }
    if ($terminal) { $health = if ($failed) { 'failed' } else { 'completed' } }
    elseif ($stage -ne 'awaiting-job' -and $quiet -ge 600) { $health = 'suspected-hang' }
    elseif ($stage -ne 'awaiting-job' -and $quiet -ge 240) { $health = 'possibly-stalled' }
    if ($service -ne 'active' -and -not $terminal) { $health = 'runner-unavailable' }
    $progress = @()
    $errorSeen = $false
    if ($logPath) {
        $previewStage = if ($stage -eq 'unit-test') { 'unit-test' } else { 'apply' }
        $progress = @(Read-SandboxProgress -Path $logPath -Stage $previewStage)
        $stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $stream.Position = [Math]::Max(0, $stream.Length - 65536)
            $reader = [System.IO.StreamReader]::new($stream, $utf8)
            try { $errorSeen = [regex]::IsMatch($reader.ReadToEnd(), '(?m)^Error:') }
            finally { $reader.Dispose() }
        }
        finally { $stream.Dispose() }
    }
    $result = @{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        runner_service = $service; processes = Get-SandboxProcessCount
        stage = $stage; stages = $stages; log = $logInfo
        quiet_seconds = $quiet; health = $health; progress = $progress
        error_seen = $errorSeen; terminal = $terminal; changed_at = $changedAt
    }
    $encoded = ($result | ConvertTo-Json -Depth 10 -Compress) + "`n"
    $temporary = Join-Path $OutputDirectory 'latest.tmp'
    [System.IO.File]::WriteAllText($temporary, $encoded, $utf8)
    [System.IO.File]::Move($temporary, (Join-Path $OutputDirectory 'latest.json'), $true)
    [System.IO.File]::AppendAllText((Join-Path $OutputDirectory 'history.jsonl'), $encoded, $utf8)
    $previous = $result
    if ($terminal) { exit 0 }
    Start-Sleep -Seconds 120
}
throw 'Monitor lifetime expired after six hours.'
