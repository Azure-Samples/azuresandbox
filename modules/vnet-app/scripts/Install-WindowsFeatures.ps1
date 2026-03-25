#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}

function Exit-WithError {
    param( [string]$msg )
    Write-Log "There was an exception during the process, please review..."
    Write-Log $msg
    Exit 2
}
#endregion

#region main
Write-Log "Running '$PSCommandPath'..."

# Install Windows features in parallel
$features = @('RSAT-ADDS', 'RSAT-DNS-Server')
$jobs = @()

foreach ($feature in $features) {
    Write-Log "Starting parallel install of Windows feature '$feature'..."

    $jobs += Start-Job -Name $feature -ArgumentList $feature -ScriptBlock {
        param($featureName)
        $result = Install-WindowsFeature -Name $featureName -ErrorAction Stop
        [PSCustomObject]@{
            Feature       = $featureName
            Success       = $result.Success
            RestartNeeded = $result.RestartNeeded
        }
    }
}

Write-Log "Waiting for all feature installs to complete..."
$jobs | Wait-Job | Out-Null

$failed = $false

foreach ($job in $jobs) {
    if ($job.State -eq 'Failed') {
        $err = $job | Receive-Job -ErrorAction SilentlyContinue 2>&1
        Write-Log "FAILED: $($job.Name) - $err"
        $failed = $true
        continue
    }

    $output = $job | Receive-Job
    Write-Log "$($output.Feature) installation result: Success=$($output.Success), RestartNeeded=$($output.RestartNeeded)"

    if (-not $output.Success) {
        $failed = $true
    }
}

$jobs | Remove-Job -Force

if ($failed) {
    Exit-WithError "One or more Windows feature installations failed. See log above."
}

Write-Log "Install-WindowsFeatures complete."
Exit 0
#endregion
