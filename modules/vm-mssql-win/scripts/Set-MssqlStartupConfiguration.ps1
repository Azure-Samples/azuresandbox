# Startup script for SQL Server 2025 / Windows Server 2025 Azure VM. Reconfigures temp drive after Azure VM stop/deallocate.
# Designed to run as a scheduled task with an 'AtStartup' trigger.
# This script must be run after a VM stop/deallocate to prevent SQL Server service start failures when tempdb has been moved to the temp drive
# The script is idempotent and at a minimum it will ensure that the SQL Server and SQL Agent services are started.

# This script has only been tested under the following conditions:
# - Windows Server 2025 using PowerShell 5.x for Windows
# - Azure VM size Standard_D4ds_v6
# - MicrosoftSQLServer platform image sql2025-ws2025 entdev-gen2
# - VM must be pre-configured at first boot using 'Set-MssqlConfiguration.ps1' VM extension script
# - Default SQL Server instance is configured for manual startup
# - Runs as domain administrator on the machine being configured

#region constants
$dataLossWarningReadmeContent = @"
WARNING: THIS IS A TEMPORARY DISK.
Any data stored on this drive is SUBJECT TO LOSS and THERE IS NO WAY TO RECOVER IT.
Please do not use this disk for storing any personal or application data.

For additional details to please refer to the MSDN documentation at:
https://learn.microsoft.com/en-us/azure/virtual-machines/managed-disks-overview#temporary-disk
"@
$ErrorActionPreference = "Stop"
$logpath = $PSCommandPath + '.log'
#endregion

#region functions
function Exit-WithError {
    param( [string]$msg )
    Write-ScriptLog "There was an exception during the process, please review..."
    Write-ScriptLog $msg
    throw $msg
}

function Write-ScriptLog {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Out-File -FilePath $logpath -Append -Force
}
#endregion

#region main
Write-ScriptLog "$('=' * 80)"
Write-ScriptLog "Running '$PSCommandPath'..."

try {
    $tempDiskDriveLetter = "T"
    $tempDiskFriendlyName = "Microsoft NVMe Direct Disk v2"

    $tempVolume = Get-Volume -DriveLetter $tempDiskDriveLetter -ErrorAction SilentlyContinue

    if ($null -eq $tempVolume) {
        # Initialize, partition and format the temporary disk after a stop/deallocate operation
        $rawTempDisks = @(Get-Disk | Where-Object { $_.PartitionStyle -eq "RAW" -and $_.FriendlyName -eq $tempDiskFriendlyName })

        if ($rawTempDisks.Count -ne 1) {
            Exit-WithError "Expected exactly 1 RAW temporary disk with friendly name '$tempDiskFriendlyName', found '$($rawTempDisks.Count)'."
        }

        $tempDisk = $rawTempDisks[0]

        $partitionStyle = "GPT"
        Write-ScriptLog "Initializing disk '$($tempDisk.UniqueId)' using partition style '$partitionStyle'..."
        Initialize-Disk -UniqueId $tempDisk.UniqueId -PartitionStyle GPT -Confirm:$false | Out-Null

        Write-ScriptLog "Partitioning disk '$($tempDisk.UniqueId)' using maximum volume size and drive letter '$($tempDiskDriveLetter):'..."
        New-Partition -DiskId $tempDisk.UniqueId -UseMaximumSize -DriveLetter $tempDiskDriveLetter | Out-Null

        $fileSystem = "NTFS"
        $allocationUnitSize = 65536
        $fileSystemLabel = "Temporary Storage"
        Write-ScriptLog "Formatting volume '$($tempDiskDriveLetter):' using file system '$fileSystem', label '$fileSystemLabel' and allocation unit size '$allocationUnitSize'..."
        Format-Volume -DriveLetter $tempDiskDriveLetter -FileSystem $fileSystem -NewFileSystemLabel $fileSystemLabel -AllocationUnitSize $allocationUnitSize -Confirm:$false -Force | Out-Null

        $restartRequired = $true
        Write-ScriptLog "Restart required..."
    }

    # Recreate the data loss warning file if it is missing
    $warningReadmePath = "$($tempDiskDriveLetter):\DATALOSS_WARNING_README.txt"
    if (-not (Test-Path -Path $warningReadmePath -PathType Leaf)) {
        Write-ScriptLog "Creating '$warningReadmePath'..."
        Set-Content -Path $warningReadmePath -Value $dataLossWarningReadmeContent -Force
    }

    # Reconfigure page file settings if not already configured. This will force a reboot.
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($cs.AutomaticManagedPagefile) {
        Write-ScriptLog "Disabling automatic managed pagefile..."
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } | Out-Null
        $restartRequired = $true
        Write-ScriptLog "Restart required..."
    }

    $bootPFMB  = 4096  # 4GB fixed on C:
    $pagingFiles = @(
    "C:\pagefile.sys $bootPFMB $bootPFMB"
    "$($tempDiskDriveLetter):\pagefile.sys 0 0"
    )
    $memoryMgmtRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $currentPagingFiles = @((Get-ItemProperty -Path $memoryMgmtRegPath -Name 'PagingFiles' -ErrorAction SilentlyContinue).PagingFiles)

    if (($pagingFiles -join ';') -ne ($currentPagingFiles -join ';')) {
        Write-ScriptLog "Configuring page file settings..."
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'PagingFiles' -Value $pagingFiles
        $restartRequired = $true
        Write-ScriptLog "Restart required..."
    }

    # Recreate the SQLTEMP directory if necessary
    $sqlTempPath = "$($tempDiskDriveLetter):\SQLTEMP"
    if (-not (Test-Path -Path $sqlTempPath)) {
        Write-ScriptLog "Creating SQL temp directory at '$sqlTempPath'..."
        New-Item -ItemType Directory -Path $sqlTempPath -Force | Out-Null
    }

    if ($restartRequired) {
        Write-ScriptLog "Restarting computer..."
        Restart-Computer -Force
    }

    # Start MSSQLSERVER and SQLSERVERAGENT services if not already running
    if ((Get-Service -Name MSSQLSERVER).Status -ne "Running") { 
        Write-ScriptLog "Starting MSSQLSERVER service..."
        Start-Service -Name MSSQLSERVER 
    }
    if ((Get-Service -Name SQLSERVERAGENT).Status -ne "Running") { 
        Write-ScriptLog "Starting SQLSERVERAGENT service..."
        Start-Service -Name SQLSERVERAGENT 
    }
}
catch {
    Exit-WithError "Set-MssqlStartupConfiguration failed. $_"
}

Write-ScriptLog "'$PSCommandPath' exiting normally..."
Write-ScriptLog "$('=' * 80)"
Exit 0
#endregion
