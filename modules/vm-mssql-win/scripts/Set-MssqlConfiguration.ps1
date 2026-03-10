# First boot Azure VM extension worker script for SQL Server 2025 / Windows Server 2025 Azure Virtual Machine configuration.
# Initializes and formats RAW disks.
# Configures Windows paging file to use temporary disk.
# Moves SQL Server tempdb to temporary disk.
# Moves SQL Server system databases to data and log disks.
# Moves SQL Server errorlog to data disk.
# Sets SQL Server for manual startup.
# Registers a scheduled task that runs on startup that prepares the temp disk if necessary and starts SQL Server.
# Configures Windows Update for first-party updates to enable SQL Server patching.

# This script has only been tested under the following conditions:
# - Windows Server 2025 using PowerShell 5.x for Windows
# - Azure VM size Standard_D4ds_v6
# - MicrosoftSQLServer platform image sql2025-ws2025 entdev-gen2
# - VM must be pre-configured using 'MssqlVmConfiguration.ps1' DSC configuration
# - Runs as domain administrator on the machine being configured

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function', Target = 'Restart-SqlServer', Justification = 'Strict one-off automation script; no -WhatIf/-Confirm support required.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function', Target = 'Start-SqlServer', Justification = 'Strict one-off automation script; no -WhatIf/-Confirm support required.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function', Target = 'Stop-SqlServer', Justification = 'Strict one-off automation script; no -WhatIf/-Confirm support required.')]

#region parameters
param (
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory = $true)]
    [string]$AdminPwdSecret
)
#endregion

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

function Get-DataDisk {
    $sleepSeconds = 10
    $maxAttempts = 30
    $storageProfile = $null

    for ($currentAttempt = 1; $currentAttempt -le $maxAttempts; $currentAttempt++) {
        Write-ScriptLog "Querying Azure instance metadata service for virtual machine storageProfile, attempt '$currentAttempt' of '$maxAttempts'..."

        try {
            $storageProfile = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Method GET -Uri http://169.254.169.254/metadata/instance/compute/storageProfile?api-version=2020-06-01
        }
        catch {
            Exit-WithError $_
        }

        if ($null -eq $storageProfile) {
            Exit-WithError "Azure instance metadata service did not return a storage profile..."
        }

        if ($storageProfile.dataDisks.Count -eq 2) {
            Write-ScriptLog "Located 2 attached Azure data disks..."
            break
        }

        if ($currentAttempt -lt $maxAttempts) {
            Write-ScriptLog "Waiting for Azure instance metadata service to refresh for '$sleepSeconds' seconds..."
            Start-Sleep -Seconds $sleepSeconds
        }
    }

    if (($null -eq $storageProfile.dataDisks) -or ($storageProfile.dataDisks.Count -eq 0)) {
        Exit-WithError "No attached Azure data disks found..."
    }

    if ($storageProfile.dataDisks.Count -ne 2) {
        Exit-WithError "Expecting 2 attached Azure data disks, found '$($storageProfile.dataDisks.Count)'..."
    }

    return $storageProfile.dataDisks
}

function Get-LocalRawDisk {
    param(
        [int]$ExpectedCount = 3
    )

    $elapsedSeconds = 0
    $localRawDisks = @()
    $sleepSeconds = 10
    $timeoutSeconds = 60

    do {
        $localRawDisks = @(Get-Disk | Where-Object PartitionStyle -eq 'RAW')
        Write-ScriptLog "Located $($localRawDisks.Count) local raw disks..."

        if ($localRawDisks.Count -eq $ExpectedCount) {
            break
        }

        if ($elapsedSeconds -ge $timeoutSeconds) {
            break
        }

        Write-ScriptLog "Waiting '$sleepSeconds' seconds for expected RAW disks to appear..."
        Start-Sleep -Seconds $sleepSeconds
        $elapsedSeconds += $sleepSeconds
    }
    while ($elapsedSeconds -le $timeoutSeconds)

    return $localRawDisks
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

    Write-ScriptLog "Disk '$($Disk.UniqueId)' matched to Azure data disk '$($matchingAzureDataDisk.name)' by size '$($matchingAzureDataDisk.diskSizeGb) Gb'..."
    return $matchingAzureDataDisk
}

function Grant-SqlFullControl {
    param ( [string]$FolderPath )

    Write-ScriptLog "Getting SQL Server Service account..."

    try {
        $serviceAccount = Get-CimInstance -ClassName Win32_Service -Filter "Name='MSSQLSERVER'" | Select-Object -ExpandProperty StartName
    }
    catch {
        Exit-WithError $_
    }

    Write-ScriptLog "Updating ACL for folder '$FolderPath' to allow 'FullControl' for '$serviceAccount'..."

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
            Write-ScriptLog "Invoke-Sql: Attempt $retryCount failed. Retrying in $retryDelay seconds..."
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

    Write-ScriptLog "Move-SqlDatabase: Checking if database '$Name' needs to be moved..."

    if ((Test-Path "$SqlDataPath\$DataFileName" -PathType leaf) -and
        (Test-Path "$SqlLogPath\$LogFileName" -PathType leaf)) {
        Write-ScriptLog "Move-SqlDatabase: Database '$Name' does not need to be moved..."
        return
    }

    # Get SQL Server setup data root
    Write-ScriptLog "Move-SqlDatabase: Looking for default SQL Server setup data root directory..."

    try {
        $sqlDataRootObject = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$DefaultSqlInstance\Setup" -Name SQLDataRoot
        $sqlDataRoot = "$($sqlDataRootObject.SQLDataRoot)\DATA"
    }
    catch {
        Exit-WithError $_
    }

    Write-ScriptLog "Move-SqlDatabase: SQL Server setup data root directory is '$sqlDataRoot'..."

    # Check that data file exists
    $currentDataFilePath = "$sqlDataRoot\$DataFileName"

    if (-not (Test-Path $currentDataFilePath -PathType leaf) ) {
        Exit-WithError "Move-SqlDatabase: Unable to locate data file '$currentDataFilePath'..."
    }

    # Check that log file exists
    $currentLogFilePath = "$sqlDataRoot\$LogFileName"

    if (-not (Test-Path $currentLogFilePath -PathType leaf) ) {
        Exit-WithError "Move-SqlDatabase: Unable to locate log file '$currentLogFilePath'..."
    }

    $newDataFilePath = "$SqlDataPath\$DataFileName"
    $newLogFilePath = "$SqlLogPath\$LogFileName"

    if ($Name -eq 'master') {
        Write-ScriptLog "Move-SqlDatabase: Updating SQL Server startup parameters to new master database file locations..."

        try {
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$DefaultSqlInstance\MSSQLServer\Parameters" -Name SQLArg0 -Value "-d$newDataFilePath"
            Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$DefaultSqlInstance\MSSQLServer\Parameters" -Name SQLArg2 -Value "-l$newLogFilePath"
        }
        catch {
            Exit-WithError $_
        }
    }
    elseif ( ( $Name -eq 'model' ) -or ( $Name -eq 'msdb' ) ) {
        Write-ScriptLog "Move-SqlDatabase: Altering '$Name' and setting database file location to '$newDataFilePath'..."
        $sqlCommand = "ALTER DATABASE $Name MODIFY FILE ( NAME = $DataDeviceName, FILENAME = N'$newDataFilePath' );"
        Invoke-Sql $sqlCommand

        Write-ScriptLog "Move-SqlDatabase: Altering '$Name' and setting log file location to '$newLogFilePath'..."
        $sqlCommand = "ALTER DATABASE $Name MODIFY FILE ( NAME = $LogDeviceName, FILENAME = N'$newLogFilePath' ) "
        Invoke-Sql $sqlCommand
    }

    Stop-SqlServer

    Write-ScriptLog "Sleeping for 60 seconds to wait for SQL Server to shutdown completely..."
    Start-Sleep -Seconds 60

    Write-ScriptLog "Move-SqlDatabase: Moving '$Name' database data file from '$currentDataFilePath' to '$newDataFilePath'..."
    try {
        Move-Item -Path $currentDataFilePath -Destination $newDataFilePath -Force -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }

    Write-ScriptLog "Move-SqlDatabase: Moving '$Name' database log file from '$currentLogFilePath' to '$newLogFilePath'..."
    try {
        Move-Item -Path $currentLogFilePath -Destination $newLogFilePath -Force -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }

    Start-SqlServer
}

function Restart-SqlServer {
    Stop-SqlServer
    Start-SqlServer
}

function Start-SqlServer {
    Write-ScriptLog "Starting SQL Server..."

    try {
        Start-Service -Name MSSQLSERVER
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

function Stop-SqlServer {
    Write-ScriptLog "Stopping SQL Server..."

    try {
        Stop-Service -Name SQLSERVERAGENT
        Stop-Service -Name MSSQLSERVER
    }
    catch {
        Exit-WithError $_
    }
}

function Write-InputParameter {
    param(
        [hashtable]$Parameters
    )

    Write-ScriptLog "Input parameters provided to script:"

    foreach ($key in ($Parameters.Keys | Sort-Object)) {
        $value = $Parameters[$key]

        if ($null -eq $value) {
            Write-ScriptLog "  $key = <null>"
            continue
        }

        Write-ScriptLog "Parameter '$key' = '$value'"
    }
}

function Write-ScriptLog {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Out-File -FilePath $logpath -Append -Force
}
#endregion

#region main
Write-ScriptLog "Running '$PSCommandPath'..."
Write-InputParameter -Parameters $PSBoundParameters

# Check for RAW disks to determine if the script has already been run
$localRawDisksExpected = 3
$localRawDisks = Get-LocalRawDisk -ExpectedCount $localRawDisksExpected

if ($localRawDisks.Count -eq 0) {
    Write-ScriptLog "No local raw disks found after '$TimeoutSeconds' seconds, exiting for idempotency)..."
    Exit 0
}

if ($localRawDisks.Count -ne $localRawDisksExpected) {
    Exit-WithError "Expected $localRawDisksExpected local raw disks after '$TimeoutSeconds' seconds, found '$($localRawDisks.Count)'..."
}

# Log into Azure
Write-ScriptLog "Logging into Azure using managed identity..."

try {
    Connect-AzAccount -Identity
}
catch {
    Exit-WithError $_
}

# Get Secrets from key vault
Write-ScriptLog "Getting secret '$AdminPwdSecret' from key vault '$KeyVaultName'..."

try {
    $adminPwd = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminPwdSecret -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($adminPwd)) {
    Exit-WithError "Secret '$AdminPwdSecret' not found in key vault '$KeyVaultName'..."
}

Write-ScriptLog "The length of secret '$AdminPwdSecret' is '$($adminPwd.Length)'..."

# Initialize RAW disks
foreach ( $disk in $localRawDisks ) {
    Write-ScriptLog "$('=' * 80)"
    Write-ScriptLog "Local disk DiskNumber -----: $($disk.DiskNumber)"
    Write-ScriptLog "Local disk UniqueId -------: $($disk.UniqueId)"
    Write-ScriptLog "Local disk FriendlyName ---: $($disk.FriendlyName)"
    Write-ScriptLog "Local disk Size -----------: $($disk.Size / 1Gb) Gb"
    Write-ScriptLog "Local disk Location -------: $($disk.Location)"
    Write-ScriptLog "Local disk BusType --------: $($disk.BusType)"
    Write-ScriptLog "Local disk Model ----------: $($disk.Model)"
    Write-ScriptLog "Local disk SerialNumber ---: $($disk.SerialNumber)"
    Write-ScriptLog "Local disk Path -----------: $($disk.Path)"
}

Write-ScriptLog "$('=' * 80)"

$azureDataDisks = Get-DataDisk

foreach ( $azureDataDisk in $azureDataDisks ) {
    Write-ScriptLog "$('=' * 80)"
    Write-ScriptLog "Azure data disk name --------: $($azureDataDisk.name)"
    Write-ScriptLog "Azure data disk size --------: $($azureDataDisk.diskSizeGb) Gb"
    Write-ScriptLog "Azure data disk caching -----: $($azureDataDisk.caching)"
    Write-ScriptLog "Azure data disk resource id -: $($azureDataDisk.managedDisk.id)"
    Write-ScriptLog "Azure data disk sku ---------: $($azureDataDisk.managedDisk.storageAccountType)"
    Write-ScriptLog "Azure data disk LUN ---------: $($azureDataDisk.lun)"
}

# Partition and format RAW disks
foreach ($disk in $localRawDisks) {
    Write-ScriptLog "$('=' * 80)"

    $tempDiskFriendlyName = "Microsoft NVMe Direct Disk v2"
    $dataDiskFriendlyName = "Virtual_Disk NVME Ultra"

    if ($disk.FriendlyName -eq $tempDiskFriendlyName) {
        Write-ScriptLog "Disk '$($disk.UniqueId)' identified as local temporary disk based on friendly name '$tempDiskFriendlyName'..."
        $fileSystemLabel = "Temporary Storage"
        $driveLetter = "T"
    }
    elseif ($disk.FriendlyName -eq $dataDiskFriendlyName) {
        Write-ScriptLog "Disk '$($disk.UniqueId)' identified as Azure data disk based on friendly name '$dataDiskFriendlyName'..."

        $azureDataDisk = Get-MatchingAzureDataDiskBySize -Disk $disk -AzureDataDisks $azureDataDisks

        $fileSystemLabel = $azureDataDisk.name.Split("-").Trim()[3]
        $driveLetter = $fileSystemLabel.Substring($fileSystemLabel.Length - 1, 1)

        $matchedAzureDiskResourceId = $azureDataDisk.managedDisk.id
        $azureDataDisks = @($azureDataDisks | Where-Object { $_.managedDisk.id -ne $matchedAzureDiskResourceId })
        Write-ScriptLog "Removed matched Azure data disk '$($azureDataDisk.name)' from future matching candidates..."
    }
    else {
        Exit-WithError "Unable to identify RAW disk '$($disk.UniqueId)' with friendly name '$($disk.FriendlyName)' as either local temporary disk or Azure data disk..."
    }

    $partitionStyle = "GPT"
    Write-ScriptLog "Initializing disk '$($disk.UniqueId)' using partition style '$partitionStyle'..."

    try {
        Initialize-Disk -UniqueId $disk.UniqueId -PartitionStyle $partitionStyle -Confirm:$false | Out-Null
    }
    catch {
        Exit-WithError $_
    }

    Write-ScriptLog "Partitioning disk '$($disk.UniqueId)' using maximum volume size and drive letter '$($driveLetter):'..."

    try {
        New-Partition -DiskId $disk.UniqueId -UseMaximumSize -DriveLetter $driveLetter | Out-Null
    }
    catch {
        Exit-WithError $_
    }

    $fileSystem = "NTFS"
    $allocationUnitSize = 65536

    Write-ScriptLog "Formatting volume '$($driveLetter):' using file system '$fileSystem', label '$fileSystemLabel' and allocation unit size '$allocationUnitSize'..."

    try {
        Format-Volume -DriveLetter $driveLetter -FileSystem $fileSystem -NewFileSystemLabel $fileSystemLabel -AllocationUnitSize $allocationUnitSize -Confirm:$false -Force | Out-Null
    }
    catch {
        Exit-WithError $_
    }
}

Write-ScriptLog "$('=' * 80)"

# Get SQL Server default instance
Write-ScriptLog "Looking for default SQL Server instance..."

try {
    $defaultSqlInstanceObject = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL' -Name MSSQLSERVER
    $defaultSqlInstance = $defaultSqlInstanceObject.MSSQLSERVER
}
catch {
    Exit-WithError $_
}

Write-ScriptLog "Default SQL Server instance '$defaultSqlInstance' located..."

# Configure data disks
Write-ScriptLog "$('=' * 80)"
Write-ScriptLog "Configuring data disks..."

$volumes = Get-Volume
$volumeIndex = -1

foreach ( $volume in $volumes) {
    $volumeIndex ++
    Write-ScriptLog "$('=' * 80)"
    Write-ScriptLog "Volume index ----------------: $volumeIndex"
    Write-ScriptLog "Volume FileSystemType -------: $($volume.FileSystemType)"
    Write-ScriptLog "Volume Size -----------------: $($volume.Size / 1Gb) Gb"
    Write-ScriptLog "Volume Path -----------------: $($volume.Path)"
    Write-ScriptLog "Volume DriveLetter ----------: $($volume.DriveLetter)"
    Write-ScriptLog "Volume FileSystemLabel ------: $($volume.FileSystemLabel)"
    Write-ScriptLog "Volume DriveType ------------: $($volume.DriveType)"


    if ( $volume.FileSystemLabel -in @( 'System Reserved', 'Windows', 'Recovery' ) ) {
        Write-ScriptLog "Skipping FileSystemLabel '$($volume.FileSystemLabel)'..."
        continue
    }

    if ( $volume.DriveType -in @( 'CD-ROM', 'Removable' ) ) {
        Write-ScriptLog "Skipping DriveType '$($volume.DriveType)'..."
        continue
    }

    if ( $volume.FileSystemType -in @( 'FAT32' ) ) {
        Write-ScriptLog "Skipping FileSystemType '$($volume.FileSystemType)'..."
        continue
    }

    if ( $volume.FileSystemLabel -eq "Temporary Storage" ) {
        Write-ScriptLog "Located local temporary disk at '$($volume.DriveLetter):'..."

        $warningReadmeDestinationPath = "$($volume.DriveLetter):\DATALOSS_WARNING_README.txt"

        Write-ScriptLog "Creating '$warningReadmeDestinationPath' from embedded script content..."
        try {
            Set-Content -Path $warningReadmeDestinationPath -Value $dataLossWarningReadmeContent -Force -ErrorAction Stop
        }
        catch {
            Exit-WithError "Failed to create '$warningReadmeDestinationPath' from embedded content. $_"
        }

        $path = "$($volume.DriveLetter):\SQLTEMP"

        if ( -not ( Test-Path $path ) ) {
            Write-ScriptLog "Creating file path '$path'..."

            try {
                New-Item -ItemType Directory -Path $path -Force
            }
            catch {
                Exit-WithError $_
            }
        }

        $filePath = "$path\tempdb.mdf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = N'$filePath' );"
        Write-ScriptLog "Altering tempdb and setting primary database file location to '$filePath'..."
        Invoke-Sql $sqlCommand

        $filePath = "$path\tempdb_mssql_2.ndf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = temp2, FILENAME = N'$filePath' ) "
        Write-ScriptLog "Altering tempdb and setting secondary database file location to '$filePath'..."
        Invoke-Sql $sqlCommand

        $filePath = "$path\templog.ldf"
        $sqlCommand = "ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = N'$filePath' ) "
        Write-ScriptLog "Altering tempdb and setting log file location to '$filePath'..."
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

        Write-ScriptLog "Paging file configuration written. Reboot is required to apply."

        continue
    }

    # Create SQL Server data and log directories if they don't already exist, and set default data and log directories
    $sqlPath = $null

    switch -Wildcard ( $volume.FileSystemLabel ) {
        '*sqldata*' {
            $sqlPath = "$($volume.DriveLetter):\MSSQL\DATA"

            Write-ScriptLog "Changing default SQL Server data directory to '$sqlPath'..."
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

            Write-ScriptLog "Changing default SQL Server log directory to '$sqlPath'..."
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
        Write-ScriptLog "Creating directory '$sqlPath'..."

        try {
            New-Item -ItemType Directory -Path $sqlPath -Force
        }
        catch {
            Exit-WithError $_
        }

        Grant-SqlFullControl $sqlPath
    }

    Restart-SqlServer
    continue
}

Write-ScriptLog "$('=' * 80)"

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
    Write-ScriptLog "Creating SQL Server ERRORLOG directory '$sqlErrorlogPath'..."

    try {
        New-Item -ItemType Directory -Path $sqlErrorlogPath -Force
    }
    catch {
        Exit-WithError $_
    }

    Grant-SqlFullControl $sqlErrorlogPath
}

Write-ScriptLog "Updating SQL Server startup parameter for ERRORLOG path to '$sqlErrorlogPath'..."

try {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\$defaultSqlInstance\MSSQLServer\Parameters" -Name SQLArg1 -Value "-e$sqlErrorlogPath\ERRORLOG"
}
catch {
    Exit-WithError $_
}

Restart-SqlServer

# Set SQL for manual startup
Write-ScriptLog "Configuring SQL Server services for manual startup..."

try {
    Set-Service -Name MSSQLSERVER -StartupType Manual
    Set-Service -Name SQLSERVERAGENT -StartupType Manual
}
catch {
    Exit-WithError $_
}

# Register scheduled task to recreate SQL Server tempdb folders on temp drive if necessary and start SQL Server on boot
$taskName = "Set-MssqlStartupConfiguration"
$sqlStartupScriptPath = "$((Get-Item $PSCommandPath).DirectoryName)\$taskName.ps1"

if ( -not (Test-Path $sqlStartupScriptPath) ) {
    Exit-WithError "Unable to locate '$sqlStartupScriptPath'..."
}

$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Unrestricted -File `"$sqlStartupScriptPath`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup

Write-ScriptLog "Registering scheduled task to execute '$sqlStartupScriptPath' under user '$DomainAdminUser'..."

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

# Configure Windows Update
Write-ScriptLog "Configuring Windows Update first-party updates to enable SQL Server patching..."
$serviceManager = (New-Object -com "Microsoft.Update.ServiceManager")
$serviceManager.Services
$serviceID = "7971f918-a847-4430-9279-4a52d1efe18d"

try {
    $serviceManager.AddService2($serviceID,7,"")
}
catch {
    Exit-WithError $_
}

Write-ScriptLog "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
