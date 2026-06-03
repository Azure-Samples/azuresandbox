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
