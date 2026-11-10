# Readiness gate run before installPatches (issue #1023). On a freshly created VM the Windows guest
# agent may self-update (older platform images ship an older agent). While it updates it skips goal
# states, so an installPatches request issued then never reaches the patch extension and the platform
# fails it. This script is delivered as a goal state, so it only runs once the agent is processing
# goal states again. It logs the agent versions for diagnostics and, if a newer staged agent is not
# yet the running one, waits a bounded time for the switch to finish. It never fails the apply.

#region functions
function Write-ScriptLog {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}

function Get-RunningAgentVersion {
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='WindowsAzureGuestAgent'" -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return $null
    }

    $match = [regex]::Match($service.PathName, 'GuestAgent_(\d+(\.\d+){3})')
    if ($match.Success) {
        return [version]$match.Groups[1].Value
    }

    return $null
}

function Get-NewestStagedAgentVersion {
    $versions = Get-ChildItem -Path 'C:\WindowsAzure' -Directory -Filter 'GuestAgent_*' -ErrorAction SilentlyContinue |
        ForEach-Object { [regex]::Match($_.Name, '^GuestAgent_(\d+(\.\d+){3})') } |
        Where-Object { $_.Success } |
        ForEach-Object { [version]$_.Groups[1].Value } |
        Sort-Object -Descending

    return $versions | Select-Object -First 1
}
#endregion

#region main
Write-ScriptLog "Running '$PSCommandPath'..."

$timeoutSeconds = 600
$pollSeconds = 15
$deadline = (Get-Date).AddSeconds($timeoutSeconds)

while ($true) {
    $service = Get-Service -Name 'WindowsAzureGuestAgent' -ErrorAction SilentlyContinue
    $serviceStatus = if ($null -ne $service) { $service.Status } else { 'NotFound' }
    $running = Get-RunningAgentVersion
    $staged = Get-NewestStagedAgentVersion

    Write-ScriptLog "Guest agent service status '$serviceStatus', running version '$running', newest staged version '$staged'."

    $updateInProgress = ($null -ne $staged) -and (($null -eq $running) -or ($staged -gt $running))

    if ($serviceStatus -eq 'Running' -and -not $updateInProgress) {
        Write-ScriptLog "Guest agent is ready."
        break
    }

    if ((Get-Date) -ge $deadline) {
        Write-ScriptLog "WARNING: Guest agent did not report ready within $timeoutSeconds seconds. Continuing anyway."
        break
    }

    Write-ScriptLog "Guest agent update in progress or service not running. Waiting $pollSeconds seconds..."
    Start-Sleep -Seconds $pollSeconds
}

Write-ScriptLog "'$PSCommandPath' completed successfully."
Exit 0
#endregion
