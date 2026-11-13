# Sets Configure Automatic Updates to 4 ("Auto download and schedule the install") on the build VM. VMs deployed from
# gallery images use patch_mode = "AutomaticByOS", because automatic VM guest patching doesn't work on custom images,
# and Windows Server's default (3) only downloads updates.
# See https://learn.microsoft.com/azure/update-manager/manage-updates-customized-images
# Used by the jumpwin and mssqlwin image templates as their last customize step, so Windows Update doesn't start
# installing on its own during the build. Runs elevated, as SYSTEM, under the Azure VM Image Builder PowerShell
# customizer, and is idempotent.

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

$path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'

try {
    if (-not (Test-Path -Path $path)) {
        $null = New-Item -Path $path -Force
    }

    Set-ItemProperty -Path $path -Name 'NoAutoUpdate' -Value 0 -Type DWord
    Set-ItemProperty -Path $path -Name 'AUOptions' -Value 4 -Type DWord
    Write-Log "Set NoAutoUpdate = 0 and AUOptions = 4 under '$path'."
}
catch {
    Exit-WithError $_
}

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
