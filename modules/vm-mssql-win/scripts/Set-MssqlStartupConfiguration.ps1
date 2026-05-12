# Startup script for SQL Server 2025 / Windows Server 2025 Azure VM. Reconfigures temp drive after Azure VM stop/deallocate.
# Designed to run as a scheduled task with an 'AtStartup' trigger.
# This script must be run after a VM stop/deallocate to prevent SQL Server service start failures when tempdb has been moved to the temp drive
# The script is idempotent and at a minimum it will ensure that the SQL Server and SQL Agent services are started.

# This script has only been tested under the following conditions:
# - Windows Server 2025 using PowerShell 5.x for Windows
# - Azure VM sizes from the Ddsv6 series (e.g. Standard_D4ds_v6, Standard_D8ds_v6) and the Edsv6 series (e.g. Standard_E4ds_v6, Standard_E16ds_v6)
# - VM sizes with multiple local NVMe temp disks are supported: all temp disks are striped into a single 'T:' volume via Windows Storage Spaces (Simple resiliency, NumberOfColumns = N, 64 KB interleave). Storage Spaces is used uniformly for all temp-disk counts (including N=1) so that VM resize across SKUs with different temp-disk counts is handled by the same code path on the next boot.
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

function New-TempDiskStripe {
    # Creates a single striped volume across all local NVMe temp disks identified by friendly name,
    # using Windows Storage Spaces (Simple resiliency, one column per disk, 64 KB interleave).
    # Cleans up any stale Storage Pool / Virtual Disk objects left over from a previous boot, since
    # Azure wipes local NVMe data on stop/deallocate but the WMI Storage Spaces objects from the
    # previous boot may persist as 'Lost communication' / 'Stale metadata' / 'Unrecognized metadata'.
    # See https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-states
    # NOTE: This function is intentionally duplicated from Set-MssqlConfiguration.ps1 -- each script
    # uploads as its own remote-script blob, so a shared helper would require a third blob.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helper invoked unconditionally during boot; ShouldProcess is unnecessary.')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PhysicalDiskFriendlyName,

        [Parameter(Mandatory = $true)]
        [string]$DriveLetter,

        [Parameter(Mandatory = $true)]
        [string]$FileSystemLabel,

        [string]$StoragePoolFriendlyName = "StoragePool-Temp",
        [string]$VirtualDiskFriendlyName = "VirtualDisk-Temp",
        [int]$InterleaveBytes = 65536,
        [int]$AllocationUnitSize = 65536
    )

    # Step 1: Remove any stale virtual disk left over from a previous boot
    $existingVirtualDisk = Get-VirtualDisk -FriendlyName $VirtualDiskFriendlyName -ErrorAction SilentlyContinue
    if ($null -ne $existingVirtualDisk) {
        Write-ScriptLog "Removing stale virtual disk '$VirtualDiskFriendlyName'..."
        Remove-VirtualDisk -InputObject $existingVirtualDisk -Confirm:$false
    }

    # Step 2: Remove any stale storage pool left over from a previous boot
    $existingStoragePool = Get-StoragePool -FriendlyName $StoragePoolFriendlyName -ErrorAction SilentlyContinue
    if ($null -ne $existingStoragePool) {
        Write-ScriptLog "Removing stale storage pool '$StoragePoolFriendlyName'..."
        Remove-StoragePool -InputObject $existingStoragePool -Confirm:$false
    }

    # Step 3: Reset any NVMe temp physical disks reporting unrecognized/stale Storage Spaces metadata
    $allTempPhysicalDisks = @(Get-PhysicalDisk | Where-Object FriendlyName -eq $PhysicalDiskFriendlyName)
    foreach ($pd in $allTempPhysicalDisks) {
        $opStatus = @($pd.OperationalStatus) -join ','
        if ($opStatus -match 'Unrecognized|Stale|Lost') {
            Write-ScriptLog "Resetting physical disk '$($pd.UniqueId)' (OperationalStatus: $opStatus)..."
            Reset-PhysicalDisk -InputObject $pd
        }
    }

    # Step 4: Get the now-poolable physical disks
    $physicalDisks = @(Get-PhysicalDisk -CanPool $true | Where-Object FriendlyName -eq $PhysicalDiskFriendlyName)
    if ($physicalDisks.Count -eq 0) {
        Exit-WithError "No poolable physical disks found with friendly name '$PhysicalDiskFriendlyName'..."
    }
    $diskCount = $physicalDisks.Count
    Write-ScriptLog "Found $diskCount poolable physical disk(s) with friendly name '$PhysicalDiskFriendlyName'..."

    # Step 5: Create the storage pool
    $storageSubSystem = Get-StorageSubSystem -FriendlyName "Windows Storage*"
    Write-ScriptLog "Creating storage pool '$StoragePoolFriendlyName' from $diskCount physical disk(s)..."
    New-StoragePool `
        -FriendlyName $StoragePoolFriendlyName `
        -StorageSubSystemUniqueId $storageSubSystem.UniqueId `
        -PhysicalDisks $physicalDisks | Out-Null

    # Step 6: Create the virtual disk (Simple = RAID-0 stripe)
    Write-ScriptLog "Creating virtual disk '$VirtualDiskFriendlyName' (Simple, NumberOfColumns=$diskCount, Interleave=$InterleaveBytes)..."
    $virtualDisk = New-VirtualDisk `
        -StoragePoolFriendlyName $StoragePoolFriendlyName `
        -FriendlyName $VirtualDiskFriendlyName `
        -ResiliencySettingName Simple `
        -NumberOfColumns $diskCount `
        -Interleave $InterleaveBytes `
        -UseMaximumSize

    # Step 7: Initialize, partition, and format the virtual disk
    $disk = Get-Disk -VirtualDisk $virtualDisk
    Write-ScriptLog "Initializing virtual disk '$($disk.UniqueId)' as GPT..."
    Initialize-Disk -InputObject $disk -PartitionStyle GPT -Confirm:$false | Out-Null

    Write-ScriptLog "Creating partition on virtual disk with drive letter '$($DriveLetter):'..."
    New-Partition -InputObject $disk -UseMaximumSize -DriveLetter $DriveLetter | Out-Null

    Write-ScriptLog "Formatting volume '$($DriveLetter):' as NTFS, label '$FileSystemLabel', allocation unit size $AllocationUnitSize..."
    Format-Volume `
        -DriveLetter $DriveLetter `
        -FileSystem NTFS `
        -NewFileSystemLabel $FileSystemLabel `
        -AllocationUnitSize $AllocationUnitSize `
        -Confirm:$false `
        -Force | Out-Null

    Write-ScriptLog "Temp disk stripe '$($DriveLetter):' created across $diskCount disk(s)."
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
        # Recreate the temporary disk after a stop/deallocate operation. Azure wipes the underlying
        # local NVMe disks, so they come back RAW. We rebuild the Storage Spaces stripe from scratch;
        # New-TempDiskStripe handles cleanup of any stale Storage Pool / Virtual Disk objects from
        # the previous boot.
        $rawTempDisks = @(Get-Disk | Where-Object { $_.PartitionStyle -eq "RAW" -and $_.FriendlyName -eq $tempDiskFriendlyName })

        if ($rawTempDisks.Count -lt 1) {
            Exit-WithError "Expected at least 1 RAW temporary disk with friendly name '$tempDiskFriendlyName', found '$($rawTempDisks.Count)'."
        }

        Write-ScriptLog "Recreating temp disk stripe across $($rawTempDisks.Count) NVMe temp disk(s)..."
        New-TempDiskStripe `
            -PhysicalDiskFriendlyName $tempDiskFriendlyName `
            -DriveLetter $tempDiskDriveLetter `
            -FileSystemLabel "Temporary Storage"

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
