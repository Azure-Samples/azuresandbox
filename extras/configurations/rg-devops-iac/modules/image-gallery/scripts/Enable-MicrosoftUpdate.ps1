# Opts the build VM into Microsoft Update, so Windows Update also offers updates for other Microsoft products such as
# SQL Server. Used by every Windows image template before its WindowsUpdate passes. Runs elevated, as SYSTEM, under the
# Azure VM Image Builder PowerShell customizer, and is idempotent.

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

# The Microsoft Update service id is a well-known public value.
$microsoftUpdateServiceId = '7971f918-a847-4430-9279-4a52d1efe18d'

try {
    $serviceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
    $registered = $serviceManager.Services | Where-Object { $_.ServiceID -eq $microsoftUpdateServiceId -and $_.IsDefaultAUService }

    if ($registered) {
        Write-Log "Microsoft Update is already the default Automatic Updates service."
    }
    else {
        # 7 = asfAllowPendingRegistration + asfAllowOnlineRegistration + asfRegisterServiceWithAU
        Write-Log "Registering Microsoft Update as the default Automatic Updates service..."
        $null = $serviceManager.AddService2($microsoftUpdateServiceId, 7, '')
        Write-Log "Microsoft Update registered."
    }
}
catch {
    Exit-WithError $_
}

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
