#region constants
$logpath = $PSCommandPath + '.log'
$usernameSecretSecure = ConvertTo-SecureString -String $UsernameSecret -AsPlainText -Force
$usernameSecretSecure.MakeReadOnly()
#endregion

#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Out-File -FilePath $logpath -Append -Force
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

# Checking OS disk for unallocated space
Write-Log "$('=' * 80)"

$osDisk = Get-Disk | Where-Object IsSystem
$unallocatedSpace = $osDisk.Size - $osDisk.AllocatedSize

Write-Log "OS disk DiskNumber -------: $($osDisk.DiskNumber)"
Write-Log "OS disk UniqueId ---------: $($osDisk.UniqueId)"
Write-Log "OS disk PartitionStyle ---: $($osDisk.PartitionStyle)"
Write-Log "OS disk Size -------------: $($osDisk.Size / 1Gb) Gb"
Write-Log "OS disk AlloocatedSize ---: $($osDisk.AllocatedSize / 1Gb) Gb"
Write-Log "OS disk UnallocatedSpace -: $($unallocatedSpace / 1Gb) Gb"
Write-Log "OS disk Location ---------: $($osDisk.Location)"
Write-Log "OS disk BusType ----------: $($osDisk.BusType)"

if ($unallocatedSpace -le 0) {
    Write-Log "There is no unallocated space, skipping boot partition resize."
    exit 0
}

$bootPartition = Get-Partition -DiskNumber $osDisk.DiskNumber | Where-Object IsBoot
$maxSize = (Get-PartitionSupportedSize -DriveLetter $bootPartition.DriveLetter).SizeMax

Write-Log "Resizing boot partition to maximum size '$($maxSize / 1Gb)' Gb...'"

try {
    Resize-Partition -DriveLetter $bootPartition.DriveLetter -Size $maxSize
}
catch {
    Exit-WithError $_
}

# Prepare data disks
Write-Log "$('=' * 80)"

$localRawDisks = Get-Disk | Where-Object PartitionStyle -eq 'RAW'

if ($null -eq $localRawDisks ) {
    Write-Log "No local raw disks found..."
    exit 0
}
else {
    if ($null -eq $localRawDisks.Count) {
        Write-Log "Located 1 local raw disk..."
    }
    else {
        Write-Log "Located $($localRawDisks.Count) local raw disks..."    
    }
}

$driveLetterAscii = 69 # Ascii code for 'F'
foreach ( $disk in $localRawDisks ) {
    Write-Log "$('=' * 80)"
    Write-Log "Local data disk DiskNumber -----: $($disk.DiskNumber)"
    Write-Log "Local data disk UniqueId -------: $($disk.UniqueId)"
    Write-Log "Local data disk PartitionStyle -: $($disk.PartitionStyle)"
    Write-Log "Local data disk Size -----------: $($disk.Size / 1Gb) Gb"
    Write-Log "Local data disk Location -------: $($disk.Location)"
    Write-Log "Local data disk BusType --------: $($disk.BusType)"

    $partitionStyle = "GPT"
    Write-Log "Initializing disk '$($disk.UniqueId)' using parition style '$partitionStyle'..."
    
    try {
        Initialize-Disk -UniqueId $disk.UniqueId -PartitionStyle $partitionStyle -Confirm:$false | Out-Null
    } catch {
        Exit-WithError $_
    }

    $driveLetterAscii += 1
    $driveLetter = [char]$driveLetterAscii

    Write-Log "Partitioning disk '$($disk.UniqueId)' using maximum volume size '$($disk.Size / 1Gb)' Gb and drive letter '$($driveLetter):'..."

    try {
        New-Partition -DiskId $disk.UniqueId -UseMaximumSize -DriveLetter $driveLetter | Out-Null
    } catch {
        Exit-WithError $_
    }

    $fileSystem = "NTFS"
    $allocationUnitSize = 4096
    $fileSystemLabel = "$($driveLetter)_DATA"

    Write-Log "Formatting volume '$($driveLetter):' using file system '$fileSystem', label '$fileSystemLabel' and allocation unit size '$allocationUnitSize'..."

    try {
        Format-Volume -DriveLetter $driveLetter -FileSystem $fileSystem -NewFileSystemLabel $fileSystemLabel -AllocationUnitSize $allocationUnitSize -Confirm:$false -Force | Out-Null
    } catch {
        Exit-WithError $_
    }
}

# Exiting normally
Write-Log "$('=' * 80)"
Write-Log "'$PSCommandPath' exiting normally..."
exit 0
#endregion
