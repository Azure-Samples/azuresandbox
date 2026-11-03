# Shared helper for running the vwan P2S VPN test wrapper (scripts/vwan-tunnel.sh) on Linux and macOS.
# Dot-sourced by Invoke-UnitTests.ps1 and Test-Integration-VwanConnectivity.ps1. Not used on Windows.
#
# The wrapper is the only privileged command the vwan integration test runs. The same code path works
# everywhere; only how the wrapper is reached differs:
#   - Running as root: the wrapper runs directly, so sudo isn't needed (or even installed).
#   - Running as non-root: the wrapper runs through 'sudo -n'. Passwordless sudo comes from
#     scripts/install-vwan-tunnel.sh --user (workstations and the self-hosted runner), or from
#     credentials cached by an interactive 'sudo -v' prompt.
# The root-owned installed copy is preferred when present; otherwise the repo copy is used.

$script:VwanTunnelInstalledPath = '/usr/local/libexec/azuresandbox/vwan-tunnel'
$script:VwanTunnelRepoPath = Join-Path $PSScriptRoot 'vwan-tunnel.sh'

function Test-VwanTunnelIsRoot {
    return ((& id -u) -eq '0')
}

# Returns the wrapper path to run. Throws if the installed copy's interface version doesn't match the
# repo copy's, since the test script expects the repo copy's commands.
function Get-VwanTunnelPath {
    if (-not (Test-Path -Path $script:VwanTunnelInstalledPath -PathType Leaf)) {
        return $script:VwanTunnelRepoPath
    }

    $installedVersion = "$(& $script:VwanTunnelInstalledPath version 2>$null)".Trim()
    $repoVersion = "$(& bash $script:VwanTunnelRepoPath version 2>$null)".Trim()
    if ($installedVersion -ne $repoVersion) {
        throw "The installed vwan tunnel wrapper at '$($script:VwanTunnelInstalledPath)' has interface version '$installedVersion', but this repo expects '$repoVersion'. Re-run 'sudo ./scripts/install-vwan-tunnel.sh' (on the self-hosted runner, redeploy rg-devops-iac)."
    }
    return $script:VwanTunnelInstalledPath
}

# Runs a wrapper command and returns its exit code and combined output.
function Invoke-VwanTunnel {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('check', 'start', 'status', 'log', 'stop')]
        [string]$Action,

        [ValidateRange(1, 10000)]
        [int]$Tail,

        [string]$InputText
    )

    $wrapperArgs = @($Action)
    if ($PSBoundParameters.ContainsKey('Tail')) { $wrapperArgs += @('--tail', "$Tail") }

    $wrapperPath = Get-VwanTunnelPath
    if (Test-VwanTunnelIsRoot) {
        $command = $wrapperPath
        $commandArgs = $wrapperArgs
    }
    else {
        $command = 'sudo'
        $commandArgs = @('-n', $wrapperPath) + $wrapperArgs
    }

    $output = if ($PSBoundParameters.ContainsKey('InputText')) {
        $InputText | & $command @commandArgs 2>&1
    }
    else {
        & $command @commandArgs 2>&1
    }

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = (@($output | ForEach-Object { "$_" }) -join "`n")
    }
}

# Checks that the wrapper can run as root without a password prompt mid-test. With -AllowPrompt, falls
# back to an interactive 'sudo -v' prompt when a terminal is available.
function Test-VwanTunnelAccess {
    param([switch]$AllowPrompt)

    if (Test-VwanTunnelIsRoot) {
        return [pscustomobject]@{ Success = $true; Message = 'Running as root; sudo not needed.' }
    }

    if (-not (Get-Command sudo -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Success = $false; Message = 'sudo not found. Run the tests as root or install sudo.' }
    }

    try {
        $wrapperPath = Get-VwanTunnelPath
    }
    catch {
        return [pscustomobject]@{ Success = $false; Message = "$_" }
    }

    & sudo -n $wrapperPath check 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return [pscustomobject]@{ Success = $true; Message = "Passwordless sudo available for '$wrapperPath'." }
    }

    if ($AllowPrompt -and ([System.Environment]::UserInteractive -or (Test-Path /dev/tty))) {
        & sudo -v
        if ($LASTEXITCODE -eq 0) {
            & sudo -n $wrapperPath check 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return [pscustomobject]@{ Success = $true; Message = "sudo credentials cached for '$wrapperPath'." }
            }
        }
    }

    return [pscustomobject]@{
        Success = $false
        Message = "Can't run '$wrapperPath' through sudo without a password. Run the tests as root, run them interactively to answer a sudo prompt, or run 'sudo ./scripts/install-vwan-tunnel.sh --user $(& id -un)' to allow unattended runs."
    }
}
