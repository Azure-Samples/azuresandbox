# This script must be run on a domain joined Azure VM provisioned with a Windows Server 2025 / SQL Server 2025 platform image
# This script is only tested with vm size Standard_D4ds_v6

param (
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory = $true)]
    [string]$AdminPwdSecret,

    [Parameter(Mandatory = $true)]
    [int]$TempDiskSizeMb
)

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

function Get-DataDisks {
    $sleepSeconds = 10
    $maxAttempts = 30

    for ($currentAttempt = 1; $currentAttempt -le $maxAttempts; $currentAttempt++) {
        Write-Log "Querying Azure instance metadata service for virtual machine storageProfile, attempt '$currentAttempt' of '$maxAttempts'..."

        try {
            $storageProfile = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Method GET -Uri http://169.254.169.254/metadata/instance/compute/storageProfile?api-version=2020-06-01
        }
        catch {
            Exit-WithError $_
        }

        if ($null -eq $storageProfile) {
            Exit-WithError "Azure instance metadata service did not return a storage profile..."
        }

        if ($storageProfile.dataDisks.Count -ge 2) {
            Write-Log "At least 2 Azure data disks were discovered..."
            break
        }

        if (($storageProfile.dataDisks.Count -lt 2) -and ($currentAttempt -lt $maxAttempts)) {
            Write-Log "Waiting for Azure instance metadata service to refresh for '$sleepSeconds' seconds..."
            Start-Sleep -Seconds $sleepSeconds
        }
    }

    return $storageProfile.dataDisks
}

function Stop-SqlServer {
    Write-Log "Stopping SQL Server..."
        
    try {
        Stop-Service -Name SQLSERVERAGENT
        Stop-Service -Name MSSQLLaunchpad
        Stop-Service -Name MSSQLSERVER
    }
    catch {
        Exit-WithError $_
    }        
}

function Start-SqlServer {
    Write-Log "Starting SQL Server..."
        
    try {
        Start-Service -Name MSSQLSERVER
        Start-Service -Name MSSQLLaunchpad
        Start-Service -Name SQLSERVERAGENT
    }
    catch {
        Exit-WithError $_
    }
    
    $sqlService = Get-Service -Name MSSQLSERVER

    if ($sqlService.Status -eq "Stopped") {
        Exit-WithError "Unable to start SQL Server. Please check the SQL Server error log."
    }
}
function Restart-SqlServer {
    Stop-SqlServer
    Start-SqlServer
}

function Invoke-Sql {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlCommand
    )

    $cxnstring = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $cxnstring."Data Source" = '.'
    $cxnstring."Initial Catalog" = 'master'
    $cxnstring."Integrated Security" = $true
    $cxn = New-Object System.Data.SqlClient.SqlConnection($cxnstring.ConnectionString)    

    $maxRetries = 10
    $retryCount = 0
    $retryDelay = 60 # seconds
    
    while ($retryCount -lt $maxRetries) {
        try {
            $cxn.Open()
            break
        }
        catch {
            $retryCount++
            Write-Log "Invoke-Sql: Attempt $retryCount failed. Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
        }
    }
    
    if ($retryCount -eq $maxRetries) {
        Exit-WithError "Invoke-Sql: Failed to open connection after $maxRetries attempts."
    }

    $cmd = $cxn.CreateCommand()
    $cmd.CommandText = $SqlCommand

    try {
        $cmd.ExecuteNonQuery()
    }
    catch {
        Exit-WithError $_
    }      
        
    $cxn.Close()
}

function Move-SqlDatabase {
    param (
        [string]$DefaultSqlInstance,
        [string]$Name,
        [string]$DataDeviceName,
        [string]$DataFileName,
        [string]$LogDeviceName,
        [string]$LogFileName,
        [string]$SqlDataPath,
        [string]$SqlLogPath 
    )
    
    Write-Log "Move-SqlDatabase: Checking if database '$Name' needs to be moved..."
    
    if ((Test-Path "$SqlDataPath\$DataFileName" -PathType leaf) -and 
        (Test-Path "$SqlLogPath\$LogFileName" -PathType leaf)) {
        Write-Log "Move-SqlDatabase: Database '$Name' does not need to be moved..."
        return
    }

    # Get SQL Server setup data root 
    Write-Log "Move-SqlDatabase: Looking for default SQL Server setup data root directory..."

    try {
        $sqlDataRootObject = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$DefaultSqlInstance\Setup" -Name SQLDataRoot
        $sqlDataRoot = "$($sqlDataRootObject.SQLDataRoot)\DATA"
    }
    catch {
        Exit-WithError $_
    }

    Write-Log "Move-SqlDatabase: SQL Server setup data root directory is '$sqlDataRoot'..."

    # Check that data file exists
    $currentDataFilePath = "$sqlDataRoot\$DataFileName"

    if (-not (Test-Path $currentDataFilePath -PathType leaf) ) {
        Write-Log "Move-SqlDatabase: Unable to locate data file '$currentDataFilePath'..."
        Exit-WithError $_
    }

    # Check that log file exists
    $currentLogFilePath = "$sqlDataRoot\$LogFileName"

    if (-not (Test-Path $currentLogFilePath -PathType leaf) ) {
        Write-Log "Move-SqlDatabase: Unable to locate log file '$currentLogFilePath'..."
        Exit-WithError $_
    }

    $newDataFilePath = "$SqlDataPath\$DataFileName"
    $newLogFilePath = "$SqlLogPath\$LogFileName"

    if ($Name -eq 'master') {
        Write-Log "Move-SqlDatabase: Updating SQL Server startup parameters to new master database file locations..."

        try {
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$DefaultSqlInstance\MSSQLServer\Parameters" -Name SQLArg0 -Value "-d$newDataFilePath"
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$DefaultSqlInstance\MSSQLServer\Parameters" -Name SQLArg2 -Value "-l$newLogFilePath"
        }
        catch {
            Exit-WithError $_
        }
    }
    elseif ( ( $Name -eq 'model' ) -or ( $Name -eq 'msdb' ) ) {
        Write-Log "Move-SqlDatabase: Altering '$Name' and setting database file location to '$newDataFilePath'..."
        $sqlCommand = "ALTER DATABASE $Name MODIFY FILE ( NAME = $DataDeviceName, FILENAME = N'$newDataFilePath' );"
        Invoke-Sql $sqlCommand

        Write-Log "Move-SqlDatabase: Altering '$Name' and setting log file location to '$newLogFilePath'..."
        $sqlCommand = "ALTER DATABASE $Name MODIFY FILE ( NAME = $LogDeviceName, FILENAME = N'$newLogFilePath' ) "
        Invoke-Sql $sqlCommand
    }

    Stop-SqlServer

    Write-Log "Sleeping for 60 seconds to wait for SQL Server to shutdown completely..."
    Start-Sleep -Seconds 60
    
    Write-Log "Move-SqlDatabase: Moving '$Name' database data file from '$currentDataFilePath' to '$newDataFilePath'..."
    try {
        Move-Item -Path $currentDataFilePath -Destination $newDataFilePath -Force -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }

    Write-Log "Move-SqlDatabase: Moving '$Name' database log file from '$currentLogFilePath' to '$newLogFilePath'..."
    try {
        Move-Item -Path $currentLogFilePath -Destination $newLogFilePath -Force -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }
    
    Start-SqlServer
}

function Grant-SqlFullContol {
    param ( [string]$FolderPath )

    Write-Log "Getting SQL Server Service account..."
    
    try {
        $serviceAccount = Get-WmiObject -Class Win32_service -Filter "name='MSSQLSERVER'" | ForEach-Object { return $_.startname }
    }
    catch {
        Exit-WithError $_
    }

    Write-Log "Updating ACL for folder '$FolderPath' to allow 'FullControl' for '$serviceAccount'..."

    try {
        $folderAcl = Get-ACL $FolderPath
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule( $serviceAccount, "FullControl", 3, 0, "Allow" )
        $folderAcl.SetAccessRule( $fileSystemAccessRule )
        Set-Acl -Path $FolderPath -AclObject $folderAcl
    }
    catch {
        Exit-WithError $_
    }
}

function Get-MatchingAzureDataDiskBySize {
    param (
        [Parameter(Mandatory = $true)]
        $Disk,

        [Parameter(Mandatory = $true)]
        $AzureDataDisks
    )

    $diskSizeBytes = [int64]$Disk.Size
    $matchingAzureDataDisk = $AzureDataDisks |
        Where-Object { ([int64]$_.diskSizeGb * 1GB) -eq $diskSizeBytes } |
        Select-Object -First 1

    if ($null -eq $matchingAzureDataDisk) {
        Exit-WithError "Unable to locate Azure data disk matching local disk '$($Disk.UniqueId)' with size '$($Disk.Size / 1Gb) Gb'..."
    }

    Write-Log "Disk '$($Disk.UniqueId)' matched to Azure data disk '$($matchingAzureDataDisk.name)' by size '$($matchingAzureDataDisk.diskSizeGb) Gb'..."
    return $matchingAzureDataDisk
}

function Write-InputParameters {
    param(
        [hashtable]$Parameters
    )

    Write-Log "Input parameters provided to script:"

    foreach ($key in ($Parameters.Keys | Sort-Object)) {
        $value = $Parameters[$key]

        if ($null -eq $value) {
            Write-Log "  $key = <null>"
            continue
        }

        Write-Log "Parameter '$key' = '$value'"
    }
}
#endregion

#region main
Write-Log "Running '$PSCommandPath'..."
Write-InputParameters -Parameters $PSBoundParameters

# Log into Azure
Write-Log "Logging into Azure using managed identity..."

try {
    Connect-AzAccount -Identity
}
catch {
    Exit-WithError $_
}

# Get Secrets from key vault
Write-Log "Getting secret '$AdminPwdSecret' from key vault '$KeyVaultName'..."

try {
    $adminPwd = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminPwdSecret -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($adminPwd)) {
    Exit-WithError "Secret '$AdminPwdSecret' not found in key vault '$KeyVaultName'..."
}

Write-Log "The length of secret '$AdminPwdSecret' is '$($adminPwd.Length)'..."

# Initialize RAW disks
$localRawDisks = Get-Disk | Where-Object PartitionStyle -eq 'RAW'

if ($null -eq $localRawDisks ) {
    Write-Log "No local raw disks found, exiting..."
    Exit 0
}
else {
    if ($null -eq $localRawDisks.Count) {
        Write-Log "Located 1 local raw disk..."
        Exit-WithError "Expecting 3 local raw disks..."
    }
    else {
        Write-Log "Located $($localRawDisks.Count) local raw disks..."
        if ($localRawDisks.Count -ne 3) {
            Exit-WithError "Expecting 3 local raw disks..."
        }
    }
}

foreach ( $disk in $localRawDisks ) {
    Write-Log "$('=' * 80)"
    Write-Log "Local disk DiskNumber -----: $($disk.DiskNumber)"
    Write-Log "Local disk UniqueId -------: $($disk.UniqueId)"
    Write-Log "Local disk FriendlyName ---: $($disk.FriendlyName)"
    Write-Log "Local disk Size -----------: $($disk.Size / 1Gb) Gb"
    Write-Log "Local disk Location -------: $($disk.Location)"
    Write-Log "Local disk BusType --------: $($disk.BusType)"
    Write-Log "Local disk Model ----------: $($disk.Model)"
    Write-Log "Local disk SerialNumber ---: $($disk.SerialNumber)"
    Write-Log "Local disk Path -----------: $($disk.Path)"
}

Write-Log "$('=' * 80)"

$azureDataDisks = Get-DataDisks

if (($null -eq $azureDataDisks) -or ($azureDataDisks.Count -eq 0)) {
    Exit-WithError "No attached Azure data disks found..."
}

if ($null -eq $azureDataDisks.Count) {
    Write-Log "Located 1 attached Azure data disk..."
    Exit-WithError "Expecting 2 attached Azure data disks..."
}
else {
    Write-Log "Located $($azureDataDisks.Count) attached Azure data disks..."
    if ($azureDataDisks.Count -ne 2) {
        Exit-WithError "Expecting 2 attached Azure data disks..."
    }
}

foreach ( $azureDataDisk in $azureDataDisks ) {
    Write-Log "$('=' * 80)"
    Write-Log "Azure data disk name --------: $($azureDataDisk.name)"
    Write-Log "Azure data disk size --------: $($azureDataDisk.diskSizeGb) Gb"
    Write-Log "Azure data disk caching -----: $($azureDataDisk.caching)"
    Write-Log "Azure data disk resource id -: $($azureDataDisk.managedDisk.id)"
    Write-Log "Azure data disk sku ---------: $($azureDataDisk.managedDisk.storageAccountType)"
    Write-Log "Azure data disk createOpt ---: $($azureDataDisk.createOption)"
    Write-Log "Azure data disk deleteOpt ---: $($azureDataDisk.deleteOption)"
    Write-Log "Azure data disk LUN ---------: $($azureDataDisk.lun)"
}

# Partition and format RAW disks
foreach ($disk in $localRawDisks) {
    Write-Log "$('=' * 80)"

    $tempDiskFriendlyName = "Microsoft NVMe Direct Disk v2"
    $dataDiskFriendlyName = "Virtual_Disk NVME Ultra"

    if ($disk.FriendlyName -eq $tempDiskFriendlyName) {
        Write-Log "Disk '$($disk.UniqueId)' identified as local temporary disk based on friendly name '$tempDiskFriendlyName'..."
        $fileSystemLabel = "Temporary Storage"
        $driveLetter = "T"
    }
    elseif ($disk.FriendlyName -eq $dataDiskFriendlyName) {
        Write-Log "Disk '$($disk.UniqueId)' identified as Azure data disk based on friendly name '$dataDiskFriendlyName'..."

        $azureDataDisk = Get-MatchingAzureDataDiskBySize -Disk $disk -AzureDataDisks $azureDataDisks
        
        $fileSystemLabel = $azureDataDisk.name.Split("-").Trim()[3]
        $driveLetter = $fileSystemLabel.Substring($fileSystemLabel.Length - 1, 1)

        $matchedAzureDiskResourceId = $azureDataDisk.managedDisk.id
        $azureDataDisks = @($azureDataDisks | Where-Object { $_.managedDisk.id -ne $matchedAzureDiskResourceId })
        Write-Log "Removed matched Azure data disk '$($azureDataDisk.name)' from future matching candidates..."
    }
    else {
        Exit-WithError "Unable to identify RAW disk '$($disk.UniqueId)' with friendly name '$($disk.FriendlyName)' as either local temporary disk or Azure data disk..."
    }

    $partitionStyle = "GPT"
    Write-Log "Initializing disk '$($disk.UniqueId)' using partition style '$partitionStyle'..."
    
    try {
        Initialize-Disk -UniqueId $disk.UniqueId -PartitionStyle $partitionStyle -Confirm:$false | Out-Null
    }
    catch {
        Exit-WithError $_
    }

    Write-Log "Partitioning disk '$($disk.UniqueId)' using maximum volume size and drive letter '$($driveLetter):'..."

    try {
        New-Partition -DiskId $disk.UniqueId -UseMaximumSize -DriveLetter $driveLetter | Out-Null
    }
    catch {
        Exit-WithError $_
    }

    $fileSystem = "NTFS"
    $allocationUnitSize = 65536

    Write-Log "Formatting volume '$($driveLetter):' using file system '$fileSystem', label '$fileSystemLabel' and allocation unit size '$allocationUnitSize'..."

    try {
        Format-Volume -DriveLetter $driveLetter -FileSystem $fileSystem -NewFileSystemLabel $fileSystemLabel -AllocationUnitSize $allocationUnitSize -Confirm:$false -Force | Out-Null
    }
    catch {
        Exit-WithError $_
    }
}

Write-Log "$('=' * 80)"

# Get SQL Server default instance
Write-Log "Looking for default SQL Server instance..."

try {
    $defaultSqlInstanceObject = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL' -Name MSSQLSERVER
    $defaultSqlInstance = $defaultSqlInstanceObject.MSSQLSERVER
}
catch {
    Exit-WithError $_
}

Write-Log "Default SQL Server instance '$defaultSqlInstance' located..."

# Configure data disks
Write-Log "$('=' * 80)"
Write-Log "Configuring data disks..."

$volumes = Get-Volume
$volumeIndex = -1

foreach ( $volume in $volumes) {
    $volumeIndex ++ 
    Write-Log "$('=' * 80)"
    Write-Log "Volume index ----------------: $volumeIndex"
    Write-Log "Volume FileSystemType -------: $($volume.FileSystemType)"
    Write-Log "Volume Size -----------------: $($volume.Size / 1Gb) Gb"
    Write-Log "Volume Path -----------------: $($volume.Path)"
    Write-Log "Volume DriveLetter ----------: $($volume.DriveLetter)"
    Write-Log "Volume FileSystemLabel ------: $($volume.FileSystemLabel)"
    Write-Log "Volume DriveType ------------: $($volume.DriveType)"    

    
    if ( $volume.FileSystemLabel -in @( 'System Reserved', 'Windows', 'Recovery' ) ) {
        Write-Log "Skipping FileSystemLabel '$($volume.FileSystemLabel)'..."
        continue 
    }

    if ( $volume.DriveType -in @( 'CD-ROM', 'Removable' ) ) {
        Write-Log "Skipping DriveType '$($volume.DriveType)'..."
        continue 
    }

    if ( $volume.FileSystemType -in @( 'FAT32' ) ) {
        Write-Log "Skipping FileSystemType '$($volume.FileSystemType)'..."
        continue 
    }

    if ( $volume.FileSystemLabel -eq "Temporary Storage" ) {
        Write-Log "Located local temporary disk at '$($volume.DriveLetter):'..."

        $warningReadmeSourcePath = Join-Path -Path (Split-Path -Path $PSCommandPath -Parent) -ChildPath "DATALOSS_WARNING_README.txt"
        $warningReadmeDestinationPath = "$($volume.DriveLetter):\DATALOSS_WARNING_README.txt"

        if (-not (Test-Path -Path $warningReadmeSourcePath -PathType Leaf)) {
            Exit-WithError "Unable to locate required file '$warningReadmeSourcePath'..."
        }

        Write-Log "Copying '$warningReadmeSourcePath' to '$warningReadmeDestinationPath'..."
        try {
            Copy-Item -Path $warningReadmeSourcePath -Destination $warningReadmeDestinationPath -Force -ErrorAction Stop
        }
        catch {
            Exit-WithError "Failed to copy '$warningReadmeSourcePath' to '$warningReadmeDestinationPath'. $_"
        }

        $path = "$($volume.DriveLetter):\SQLTEMP"

        if ( -not ( Test-Path $path ) ) {
            Write-Log "Creating file path '$path'..."

            try {
                New-Item -ItemType Directory -Path $path -Force 
            }
            catch {
                Exit-WithError $_
            }
        }

        $filePath = "$path\tempdb.mdf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = N'$filePath' );"
        Write-Log "Altering tempdb and setting primary database file location to '$filePath'..."
        Invoke-Sql $sqlCommand

        $filePath = "$path\tempdb_mssql_2.ndf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = temp2, FILENAME = N'$filePath' ) "
        Write-Log "Altering tempdb and setting secondary database file location to '$filePath'..."
        Invoke-Sql $sqlCommand

        $filePath = "$path\templog.ldf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = N'$filePath' ) "
        Write-Log "Altering tempdb and setting log file location to '$filePath'..."
        Invoke-Sql $sqlCommand

        Restart-SqlServer
        
        # Configure page file on temporary disk

        # 1) Disable automatic pagefile management (global checkbox)
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } | Out-Null
        # AutomaticManagedPagefile is a Win32_ComputerSystem property [3](https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/memory-dump-file-options)

        # 2) Configure PagingFiles registry value (this is what Win32_PageFileSetting maps to)
        $bootPFMB  = 4096  # 4GB fixed on C:
        $pagingFiles = @(
        "C:\pagefile.sys $bootPFMB $bootPFMB"
        "$($volume.DriveLetter):\pagefile.sys 0 0"
        )

        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
        -Name 'PagingFiles' -Value $pagingFiles

        Write-Host "Paging file configuration written. Reboot is required to apply." -ForegroundColor Yellow

        continue 
    }

    # Create SQL Server data and log directories if they don't already exist, and set default data and log directories
    $sqlPath = $null

    switch -Wildcard ( $volume.FileSystemLabel ) {
        '*sqldata*' {
            $sqlPath = "$($volume.DriveLetter):\MSSQL\DATA"
            
            Write-Log "Changing default SQL Server data directory to '$sqlPath'..."
            try {
                Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$($defaultSqlInstance)\MSSQLServer" -Name DefaultData -Value $sqlPath
            }
            catch {
                Exit-WithError $_
            }
            
            $sqlDataPath = $sqlPath
            break
        }

        '*sqllog*' {
            $sqlPath = "$($volume.DriveLetter):\MSSQL\LOG"

            Write-Log "Changing default SQL Server log directory to '$sqlPath'..."
            try {
                Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$($defaultSqlInstance)\MSSQLServer" -Name DefaultLog -Value $sqlPath
            }
            catch {
                Exit-WithError $_
            }

            $sqlLogPath = $sqlPath
            break
        }
    }

    if ( ( $null -ne $sqlPath ) -and ( -not ( Test-Path $sqlPath ) )) {
        Write-Log "Creating directory '$sqlPath'..."

        try {
            New-Item -ItemType Directory -Path $sqlPath -Force 
        }
        catch {
            Exit-WithError $_
        }

        Grant-SqlFullContol $sqlPath
    }

    Restart-SqlServer
    continue
}

Write-Log "$('=' * 80)"

# Move databases 
Move-SqlDatabase `
    -DefaultSqlInstance $defaultSqlInstance `
    -Name 'master' `
    -DataFileName 'master.mdf' `
    -LogFileName 'mastlog.ldf' `
    -SqlDataPath $sqlDataPath `
    -SqlLogPath $sqlLogPath

Move-SqlDatabase `
    -DefaultSqlInstance $defaultSqlInstance `
    -Name 'msdb' `
    -DataDeviceName 'MSDBData' `
    -DataFileName 'MSDBData.mdf' `
    -LogDeviceName 'MSDBLog' `
    -LogFileName 'MSDBLog.ldf' `
    -SqlDataPath $sqlDataPath `
    -SqlLogPath $sqlLogPath

Move-SqlDatabase `
    -DefaultSqlInstance $defaultSqlInstance `
    -Name 'model' `
    -DataDeviceName 'modeldev' `
    -DataFileName 'model.mdf' `
    -LogDeviceName 'modellog' `
    -LogFileName 'modellog.ldf' `
    -SqlDataPath $sqlDataPath `
    -SqlLogPath $sqlLogPath

if ($TempDiskSizeMb -eq 0) {
    Write-Log "There is no Azure temp disk, moving tempdb data files to '$sqlDataPath' and tempdb log files to '$sqlLogPath'..."

    $filePath = "$sqlDataPath\tempdb.mdf"
    $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = N'$filePath' );"
    Write-Log "Altering tempdb and setting primary database file location to '$filePath'..."
    Invoke-Sql $sqlCommand

    $filePath = "$sqlDataPath\tempdb_mssql_2.ndf"
    $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = temp2, FILENAME = N'$filePath' ) "
    Write-Log "Altering tempdb and setting secondary database file location to '$filePath'..."
    Invoke-Sql $sqlCommand

    $filePath = "$sqlLogPath\templog.ldf"
    $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = N'$filePath' ) "
    Write-Log "Altering tempdb and setting log file location to '$filePath'..."
    Invoke-Sql $sqlCommand

    Restart-SqlServer                            
}

# Update errorlog file location
$sqlErrorlogPath = "$($sqlDataPath.Substring(0,2))\MSSQL\Log"

if ( ( $null -ne $sqlErrorlogPath ) -and ( -not ( Test-Path $sqlErrorlogPath ) )) {
    Write-Log "Creating SQL Server ERRORLOG directory '$sqlErrorlogPath'..."

    try {
        New-Item -ItemType Directory -Path $sqlErrorlogPath -Force 
    }
    catch {
        Exit-WithError $_
    }

    Grant-SqlFullContol $sqlErrorlogPath
}

Write-Log "Updating SQL Server startup parameter for ERRORLOG path to '$sqlErrorlogPath'..."

try {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$defaultSqlInstance\MSSQLServer\Parameters" -Name SQLArg1 -Value "-e$sqlErrorlogPath\ERRORLOG"
}
catch {
    Exit-WithError $_
}

Restart-SqlServer

# Set SQL for manaual startup 
if ($TempDiskSizeMb -ne 0) {
    Write-Log "Azure temp disk detected. Configuring SQL Server services for manual startup..."

    try {
        Set-Service -Name MSSQLSERVER -StartupType Manual
        Set-Service -Name SQLSERVERAGENT -StartupType Manual
    }
    catch {
        Exit-WithError $_
    }

    # Register scheduled task to recreate SQL Server tempdb folders on ephemeral drive
    $taskName = "Set-MssqlStartupConfiguration"
    $sqlStartupScriptPath = "$((Get-Item $PSCommandPath).DirectoryName)\$taskName.ps1"

    if ( -not (Test-Path $sqlStartupScriptPath) ) {
        Exit-WithError "Unable to locate '$sqlStartupScriptPath'..."
    }

    $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Unrestricted -File `"$sqlStartupScriptPath`"" 
    $taskTrigger = New-ScheduledTaskTrigger -AtStartup

    Write-Log "Registering scheduled task to execute '$sqlStartupScriptPath' under user '$DomainAdminUser'..."

    try {
        Register-ScheduledTask `
            -Force `
            -Password $adminPwd `
            -User $DomainAdminUser `
            -TaskName $taskName `
            -Action $taskAction `
            -Trigger $taskTrigger `
            -RunLevel 'Highest' `
            -Description "Prepare temp drive folders for tempdb and start SQL Server."
    }
    catch {
        Exit-WithError $_
    }
}

# Configure Windows Update 
Write-Log "Configuring Windows Update first-party updates to enable SQL Server patching..."
$serviceManager = (New-Object -com "Microsoft.Update.ServiceManager")
$serviceManager.Services
$serviceID = "7971f918-a847-4430-9279-4a52d1efe18d"

try {
    $serviceManager.AddService2($serviceID,7,"")
}
catch {
    Exit-WithError $_
}

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
