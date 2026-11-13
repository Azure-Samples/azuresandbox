# Installs the jumpwin1 RSAT Windows features. This is the single source for that step, shared by
# the deploy-time run command (compute.tf) and the pre-built image build. Runs elevated, as SYSTEM
# under a run command or the image builder's PowerShell customizer, and is idempotent.

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

# Install Windows features serially
$features = @('RSAT-ADDS', 'RSAT-DNS-Server')

foreach ($feature in $features) {
    Write-Log "Installing Windows feature '$feature'..."

    try {
        $result = Install-WindowsFeature -Name $feature -ErrorAction Stop
        Write-Log "$feature installation result: Success=$($result.Success), RestartNeeded=$($result.RestartNeeded)"

        if (-not $result.Success) {
            Exit-WithError "Windows feature '$feature' installation failed."
        }
    }
    catch {
        Exit-WithError "Windows feature '$feature' installation failed: $_"
    }
}

Write-Log "Install-WindowsFeatures complete."
Exit 0
#endregion
