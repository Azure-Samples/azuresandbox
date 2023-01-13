param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,
    
    [Parameter(Mandatory = $true)]
    [string]$Username,
    
    [Parameter(Mandatory = $true)]
    [string]$UsernameSecret
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
        [string]$SqlCommand,

        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [SecureString]$UsernameSecret
    )

    $cred = New-Object System.Data.SqlClient.SqlCredential($Username, $UsernameSecret)
    $cxnstring = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $cxnstring."Data Source" = '.'
    $cxnstring."Initial Catalog" = 'master'
    $cxn = New-Object System.Data.SqlClient.SqlConnection($cxnstring, $cred)

    try {
        $cxn.Open()
    }
    catch {
        Exit-WithError $_
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
        Invoke-Sql $sqlCommand 'sa' $usernameSecretSecure

        Write-Log "Move-SqlDatabase: Altering '$Name' and setting log file location to '$newLogFilePath'..."
        $sqlCommand = "ALTER DATABASE $Name MODIFY FILE ( NAME = $LogDeviceName, FILENAME = N'$newLogFilePath' ) "
        Invoke-Sql $sqlCommand 'sa' $usernameSecretSecure
    }

    Stop-SqlServer

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
#endregion

#region main
Write-Log "Running '$PSCommandPath'..."

# Initialize data disks
$localRawDisks = Get-Disk | Where-Object PartitionStyle -eq 'RAW'

if ($null -eq $localRawDisks ) {
    Write-Log "No local raw disks found..."
    Exit
}
else {
    if ($null -eq $localRawDisks.Count) {
        Write-Log "Located 1 local raw disk..."
    }
    else {
        Write-Log "Located $($localRawDisks.Count) local raw disks..."    
    }
}

foreach ( $disk in $localRawDisks ) {
    Write-Log "$('=' * 80)"
    Write-Log "Local disk DiskNumber -----: $($disk.DiskNumber)"
    Write-Log "Local disk UniqueId -------: $($disk.UniqueId)"
    Write-Log "Local disk PartitionStyle -: $($disk.PartitionStyle)"
    Write-Log "Local disk Size -----------: $($disk.Size / 1Gb) Gb"
    Write-Log "Local disk Location -------: $($disk.Location)"
    Write-Log "Local disk BusType --------: $($disk.BusType)"
}

Write-Log "$('=' * 80)"

$azureDataDisks = Get-DataDisks

if (($null -eq $azureDataDisks) -or ($azureDataDisks.Count -eq 0)) {
    Exit-WithError "No attached Azure data disks found..."
}

if ($null -eq $azureDataDisks.Count) {
    Write-Log "Located 1 attached Azure data disk..."
}
else {
    Write-Log "Located $($azureDataDisks.Count) attached Azure data disks..."
}

foreach ( $azureDataDisk in $azureDataDisks ) {
    Write-Log "$('=' * 80)"
    Write-Log "Azure data disk name ------: $($azureDataDisk.name)"
    Write-Log "Azure data disk size ------: $($azureDataDisk.diskSizeGb) Gb"
    Write-Log "Azure data disk LUN -------: $($azureDataDisk.lun)"
}

# Partition and format disks
foreach ($disk in $localRawDisks) {
    Write-Log "$('=' * 80)"

    $lun = $disk.Location.Split(":").Trim() -match 'LUN' -replace 'LUN ', ''
    
    if ($null -eq $azureDataDisks.Count) {
        $azureDataDisk = $azureDataDisks

        if ($azureDataDisk.lun -ne $lun) {
            Exit-WithError "Unable to locate Azure data disk with LUN '$lun'..."
        }
    }
    else {
        $azureDataDisk = $azureDataDisks | Where-Object lun -eq $lun

        if ($null -eq $azureDataDisk) {
            Exit-WithError "Unable to locate Azure data disk with LUN '$lun'..."
        }
    }

    $partitionStyle = "GPT"
    Write-Log "Initializing disk '$($disk.UniqueId)' using parition style '$partitionStyle'..."
    
    try {
        Initialize-Disk -UniqueId $disk.UniqueId -PartitionStyle $partitionStyle -Confirm:$false | Out-Null
    }
    catch {
        Exit-WithError $_
    }

    $fileSystemLabel = $azureDataDisk.name.Split("-").Trim()[2]
    $driveLetter = $fileSystemLabel.Substring($fileSystemLabel.Length - 1, 1)

    Write-Log "Partitioning disk '$($disk.UniqueId)' using maximum volume size '$($azureDataDisk.diskSizeGb)' Gb and drive letter '$($driveLetter):'..."

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
    Write-Log "Volume index -------------: $volumeIndex"
    Write-Log "Volume DriveLetter -------: $($volume.DriveLetter)"
    Write-Log "Volume FileSystemLabel ---: $($volume.FileSystemLabel)"
    Write-Log "Volume FileSystemType ----: $($volume.FileSystemType)"
    Write-Log "Volume DriveType ---------: $($volume.DriveType)"
    
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
        Write-Log "Located local temporary disk at '$($volume.DriveLetter)'..."
        $path = "$($volume.DriveLetter):\SQLTEMP"

        if ( -not ( Test-Path $path ) ) {
            Write-Log "Creating $path..."

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
        Invoke-Sql $sqlCommand 'sa' $usernameSecretSecure

        $filePath = "$path\tempdb_mssql_2.ndf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = temp2, FILENAME = N'$filePath' ) "
        Write-Log "Altering tempdb and setting secondary database file location to '$filePath'..."
        Invoke-Sql $sqlCommand 'sa' $usernameSecretSecure

        $filePath = "$path\templog.ldf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = N'$filePath' ) "
        Write-Log "Altering tempdb and setting log file location to '$filePath'..."
        Invoke-Sql $sqlCommand 'sa' $usernameSecretSecure

        Restart-SqlServer                            
        
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
Write-Log "Configuring SQL Server services for manual startup..."

try {
    Set-Service -Name MSSQLSERVER -StartupType Manual
    Set-Service -Name SQLSERVERAGENT -StartupType Manual
}
catch {
    Exit-WithError $_
}

# Register scheduled task to recreate SQL Server tempdb folders on ephemeral drive
$taskName = "SQL-startup"
$sqlStartupScriptPath = "$((Get-Item $PSCommandPath).DirectoryName)\$taskName.ps1"

if ( -not (Test-Path $sqlStartupScriptPath) ) {
    Exit-WithError "Unable to locate '$sqlStartupScriptPath'..."
}

$domainUsername = $Domain.Split('.')[0].ToUpper() + "\" + $Username
$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Unrestricted -File `"$sqlStartupScriptPath`"" 
$taskTrigger = New-ScheduledTaskTrigger -AtStartup

Write-Log "Registering scheduled task to execute '$sqlStartupScriptPath' under user '$domainUserName'..."

try {
    Register-ScheduledTask `
        -Force `
        -Password $UsernameSecret `
        -User $domainUsername `
        -TaskName $taskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -RunLevel 'Highest' `
        -Description "Prepare temp drive folders for tempdb and start SQL Server."
}
catch {
    Exit-WithError $_
}

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
