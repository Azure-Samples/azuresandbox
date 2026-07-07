$Action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-ExecutionPolicy Bypass -NoProfile -File C:\Scripts\Set-MssqlStartupConfiguration.ps1'

$Trigger = New-ScheduledTaskTrigger -AtStartup

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$Principal = New-ScheduledTaskPrincipal `
    -UserId 'NT AUTHORITY\SYSTEM' `
    -RunLevel Highest `
    -LogonType ServiceAccount

Register-ScheduledTask `
    -TaskName 'SQL Server Startup - Ephemeral Storage' `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Principal $Principal `
    -Description 'Provisions NVMe ephemeral storage and starts SQL Server after VM deallocation.' `
    -Force

# ── Lock down the scripts directory ──
# The scheduled task runs as SYSTEM, so only Administrators and SYSTEM should
# have write access to prevent privilege escalation.
$scriptsDir = 'C:\Scripts'
if (Test-Path $scriptsDir) {
    $acl = Get-Acl -Path $scriptsDir
    $inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit

    # Disable inheritance, remove inherited ACEs
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null

    # SYSTEM — FullControl
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT AUTHORITY\SYSTEM',
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )))

    # Administrators — FullControl
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators',
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )))

    Set-Acl -Path $scriptsDir -AclObject $acl
    Write-Host "Secured '$scriptsDir' - access restricted to Administrators and SYSTEM only."
}
