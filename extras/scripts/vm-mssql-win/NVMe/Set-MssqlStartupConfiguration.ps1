# Set-MssqlStartupConfiguration.ps1
# Startup script for SQL Server 2025 / Windows Server 2025 Azure VM.
# Reconfigures ephemeral NVMe temp drive after Azure VM stop/deallocate.
# Designed to run as a scheduled task with an 'AtStartup' trigger.
#
# The script is idempotent:
#   - If the temp volume exists and SQLTEMP folder is present → starts SQL services and exits.
#   - If NVMe disks are RAW (post-deallocation) → pools, formats, creates folder, starts SQL.
#
# Supports:
#   - Single NVMe Direct Disk (pooled as single-disk Storage Space)
#   - Multiple NVMe Direct Disks (striped via Storage Spaces, RAID-0)
#   - D: drive (v5 VM sizes, SCSI temp disk) or T: drive (v6 VM sizes, NVMe)
#
# Prerequisites:
#   - Windows Server 2025, PowerShell 5.x
#   - Azure VM sizes with local NVMe temp storage (v6-series) or SCSI temp (v5-series)
#   - SQL Server default instance configured for MANUAL startup
#   - SQL Server Agent configured for MANUAL startup
#   - Runs as local administrator or domain administrator
#
# Storage approach: Uses Windows Storage Spaces (Simple/RAID-0) per Microsoft best practices.
# Reference: https://learn.microsoft.com/azure/virtual-machines/enable-nvme-temp-faqs

#region constants
$ErrorActionPreference = "Stop"

$StoragePoolName   = "NVMeTempPool"
$VirtualDiskName   = "NVMeTempDisk"
$VolumeLabel       = "Temporary Storage"
$AllocationUnit    = 65536  # 64KB — optimal for SQL Server tempdb extent alignment
$TempFolderName    = "SQLTEMP"
$SQLServiceName    = "MSSQLSERVER"
$SQLAgentName      = "SQLSERVERAGENT"

# Drive letter for v6-series NVMe temp storage
$NVMeDriveLetter = "T"

$LogPath = Join-Path $PSScriptRoot "Set-MssqlStartupConfiguration.log"

$DataLossWarning = @"
WARNING: THIS IS A TEMPORARY / EPHEMERAL DISK.
Any data stored on this drive is SUBJECT TO LOSS and THERE IS NO WAY TO RECOVER IT.
Do not use this disk for storing any personal or application data.

This drive is used exclusively for SQL Server tempdb.
After VM stop/deallocate, this volume is automatically reprovisioned at startup.

Reference: https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/tempdb-ephemeral-storage
"@
#endregion

#region functions
function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') | $Message"
    $entry | Out-File -FilePath $LogPath -Append -Force
    Write-Verbose $entry
}

function Exit-WithError {
    param([string]$Message)
    Write-Log "ERROR: $Message"
    throw $Message
}
#endregion

#region main
Write-Log ("=" * 80)
Write-Log "START: $PSCommandPath"

try {

    # ══════════════════════════════════════════════════════════════════════════
    # Step 1: Determine temp drive letter and check if already provisioned
    # ══════════════════════════════════════════════════════════════════════════
    #
    # v5-series: Azure auto-provisions D: as a formatted SCSI temp disk.
    # v6-series: NVMe Direct Disks arrive RAW. We provision them as T:.

    $tempDriveLetter = $null
    $needsProvisioning = $false

    # Check if D: exists as an Azure SCSI temp disk (v5-series behavior)
    $dVolume = Get-Volume -DriveLetter "D" -ErrorAction SilentlyContinue
    if ($null -ne $dVolume -and $dVolume.FileSystemLabel -like '*Temporary Storage*') {
        $tempDriveLetter = "D"
        Write-Log "Detected v5-series: D: volume exists with label '$($dVolume.FileSystemLabel)'."
    }
    else {
        # v6-series path: check if T: is already provisioned (soft reboot scenario)
        $tempDriveLetter = $NVMeDriveLetter
        $tVolume = Get-Volume -DriveLetter $tempDriveLetter -ErrorAction SilentlyContinue
        if ($null -ne $tVolume) {
            Write-Log "Volume ${tempDriveLetter}: already exists (FileSystem: $($tVolume.FileSystem), Size: $([math]::Round($tVolume.Size/1GB, 1)) GB). No provisioning needed."
        }
        else {
            $needsProvisioning = $true
            Write-Log "Volume ${tempDriveLetter}: not found. Provisioning required."
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # Step 2: Provision NVMe disks via Storage Spaces (only if needed)
    # ══════════════════════════════════════════════════════════════════════════

    if ($needsProvisioning) {

        # ── 2a: Clean up any stale/failed Storage Spaces pool from prior boot ──
        $existingPool = Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction SilentlyContinue
        if ($null -ne $existingPool) {
            Write-Log "Found existing Storage Pool '$StoragePoolName' (HealthStatus: $($existingPool.HealthStatus)). Removing stale pool..."
            # Remove virtual disks first
            $existingPool | Get-VirtualDisk -ErrorAction SilentlyContinue | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
            # Remove the pool
            Remove-StoragePool -FriendlyName $StoragePoolName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Stale pool removed."
        }

        # ── 2b: Find poolable NVMe Direct Disks ──
        $nvmeDisks = @(Get-PhysicalDisk -CanPool $true | Where-Object { $_.FriendlyName -like '*NVMe Direct Disk*' })

        if ($nvmeDisks.Count -eq 0) {
            Exit-WithError "No poolable NVMe Direct Disks found. Cannot provision temp drive. Manual intervention required."
        }

        Write-Log "Found $($nvmeDisks.Count) poolable NVMe Direct Disk(s):"
        foreach ($d in $nvmeDisks) {
            Write-Log "  - DeviceId: $($d.DeviceId), Size: $([math]::Round($d.Size/1GB, 1)) GB, MediaType: $($d.MediaType)"
        }

        # ── 2c: Create Storage Pool ──
        Write-Log "Creating Storage Pool '$StoragePoolName'..."
        $null = New-StoragePool `
            -FriendlyName $StoragePoolName `
            -StorageSubsystemFriendlyName "Windows Storage*" `
            -PhysicalDisks $nvmeDisks `
            -ResiliencySettingNameDefault Simple

        # ── 2d: Create Virtual Disk (striped across all disks) ──
        Write-Log "Creating Virtual Disk '$VirtualDiskName' (Simple/Stripe, $($nvmeDisks.Count) columns)..."
        $vDisk = New-VirtualDisk `
            -FriendlyName $VirtualDiskName `
            -StoragePoolFriendlyName $StoragePoolName `
            -NumberOfColumns $nvmeDisks.Count `
            -PhysicalDiskRedundancy 0 `
            -ResiliencySettingName "Simple" `
            -UseMaximumSize

        # ── 2e: Initialize the disk (GPT) ──
        Write-Log "Initializing disk..."
        $vDisk | Get-Disk | Initialize-Disk -PartitionStyle GPT

        # ── 2f: Create partition, assign drive letter, format NTFS 64KB ──
        Write-Log "Creating partition and formatting (NTFS, ${AllocationUnit} byte allocation unit)..."
        $partition = $vDisk | Get-Disk | New-Partition -UseMaximumSize -DriveLetter $tempDriveLetter
        $partition | Format-Volume `
            -FileSystem NTFS `
            -AllocationUnitSize $AllocationUnit `
            -NewFileSystemLabel $VolumeLabel `
            -Confirm:$false `
            -Force

        # ── 2g: Verify ──
        $tempVolume = Get-Volume -DriveLetter $tempDriveLetter -ErrorAction SilentlyContinue
        if ($null -eq $tempVolume) {
            Exit-WithError "Failed to create volume ${tempDriveLetter}: after Storage Spaces provisioning."
        }

        $totalGB = [math]::Round($tempVolume.Size / 1GB, 1)
        Write-Log "Volume ${tempDriveLetter}: created successfully. Total capacity: ${totalGB} GB."
    }

    # ══════════════════════════════════════════════════════════════════════════
    # Step 3: Ensure SQLTEMP directory and warning file exist
    # ══════════════════════════════════════════════════════════════════════════

    $sqlTempPath = "${tempDriveLetter}:\${TempFolderName}"
    if (-not (Test-Path -Path $sqlTempPath)) {
        Write-Log "Creating SQL temp directory: $sqlTempPath"
        New-Item -ItemType Directory -Path $sqlTempPath -Force | Out-Null
    }

    # Grant the SQL Server service account full control on the tempdb folder
    $sqlServiceAccount = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$SQLServiceName'" -ErrorAction SilentlyContinue).StartName
    if ($null -ne $sqlServiceAccount -and $sqlServiceAccount -ne "") {
        $acl = Get-Acl -Path $sqlTempPath
        $identity = $sqlServiceAccount
        # Check if the ACE already exists
        $existingRule = $acl.Access | Where-Object {
            $_.IdentityReference.Value -eq $identity -and
            $_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl
        }
        if ($null -eq $existingRule) {
            Write-Log "Granting FullControl on '$sqlTempPath' to '$identity'..."
            $inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $identity,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.AddAccessRule($rule)
            Set-Acl -Path $sqlTempPath -AclObject $acl
            Write-Log "Permissions applied."
        }
        else {
            Write-Log "SQL service account '$identity' already has FullControl on '$sqlTempPath'."
        }
    }
    else {
        Write-Log "WARNING: Could not determine SQL Server service account. Verify permissions manually."
    }

    # Data-loss warning file
    $warningPath = "${tempDriveLetter}:\DATALOSS_WARNING_README.txt"
    if (-not (Test-Path -Path $warningPath -PathType Leaf)) {
        Set-Content -Path $warningPath -Value $DataLossWarning -Force
        Write-Log "Created data-loss warning file."
    }

    # ══════════════════════════════════════════════════════════════════════════
    # Step 4: Start SQL Server services
    # ══════════════════════════════════════════════════════════════════════════

    $sqlSvc = Get-Service -Name $SQLServiceName -ErrorAction SilentlyContinue
    $agentSvc = Get-Service -Name $SQLAgentName -ErrorAction SilentlyContinue

    if ($null -ne $sqlSvc -and $sqlSvc.Status -ne 'Running') {
        Write-Log "Starting $SQLServiceName..."
        Start-Service -Name $SQLServiceName -ErrorAction Stop
        Write-Log "$SQLServiceName started."
    }
    elseif ($null -ne $sqlSvc) {
        Write-Log "$SQLServiceName is already running."
    }
    else {
        Write-Log "WARNING: Service '$SQLServiceName' not found on this machine."
    }

    if ($null -ne $agentSvc -and $agentSvc.Status -ne 'Running') {
        Write-Log "Starting $SQLAgentName..."
        Start-Service -Name $SQLAgentName -ErrorAction Stop
        Write-Log "$SQLAgentName started."
    }
    elseif ($null -ne $agentSvc) {
        Write-Log "$SQLAgentName is already running."
    }
    else {
        Write-Log "WARNING: Service '$SQLAgentName' not found on this machine."
    }

    Write-Log "Completed successfully. No further action required."
}
catch {
    Exit-WithError "FATAL: $($_.Exception.Message) | ScriptStackTrace: $($_.ScriptStackTrace)"
}

Write-Log "END: $PSCommandPath"
Write-Log ("=" * 80)
Exit 0
#endregion
