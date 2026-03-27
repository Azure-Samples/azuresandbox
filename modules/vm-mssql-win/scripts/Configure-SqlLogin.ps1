#region parameters
param (
    [Parameter(Mandatory = $true)]
    [String]$DomainAdminUser
)
#endregion

#region functions
function Write-ScriptLog {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}

function Exit-WithError {
    param( [string]$msg )
    Write-ScriptLog "There was an exception during the process, please review..."
    Write-ScriptLog $msg
    Exit 2
}

function Invoke-Sql {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlCommand
    )

    $cxnstring = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $cxnstring."Server" = 'localhost'
    $cxnstring."Database" = 'master'
    $cxnstring."Integrated Security" = $true
    $cxnstring."Encrypt" = $true
    $cxnstring."TrustServerCertificate" = $true

    $cxn = New-Object System.Data.SqlClient.SqlConnection($cxnstring.ConnectionString)

    $maxRetries = 10
    $retryCount = 0
    $retryDelay = 30

    while ($retryCount -lt $maxRetries) {
        try {
            $cxn.Open()
            break
        }
        catch {
            $retryCount++
            Write-ScriptLog "Invoke-Sql: Attempt $retryCount failed to connect. Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
        }
    }

    if ($retryCount -eq $maxRetries) {
        Exit-WithError "Invoke-Sql: Failed to open SQL connection after $maxRetries attempts."
    }

    $cmd = $cxn.CreateCommand()
    $cmd.CommandText = $SqlCommand

    try {
        $cmd.ExecuteNonQuery() | Out-Null
    }
    catch {
        Exit-WithError $_
    }

    $cxn.Close() | Out-Null
}
#endregion

#region main
Write-ScriptLog "Running '$PSCommandPath'..."

$sqlServiceName = 'MSSQLSERVER'

# Stop SQL Server
Write-ScriptLog "Stopping SQL Server service..."
Stop-Service -Name $sqlServiceName -Force
$stopped = (Get-Service -Name $sqlServiceName).Status -eq 'Stopped'

if (-not $stopped) {
    Exit-WithError "Failed to stop SQL Server service."
}

Write-ScriptLog "SQL Server service stopped."

# Managed run commands execute as 'NT AUTHORITY\SYSTEM' which does not have sysadmin privileges on SQL Server
# Sysadmin privileges are required to create logins and assign server roles
# Starting SQL Server in single-user mode allows the first connection to have sysadmin privileges

Write-ScriptLog "Starting SQL Server in single-user mode..."
net start $sqlServiceName /m | Out-Null

$svcStatus = (Get-Service -Name $sqlServiceName).Status

if ($svcStatus -ne 'Running') {
    Exit-WithError "Failed to start SQL Server in single-user mode."
}

Write-ScriptLog "SQL Server started in single-user mode."

try {
    # Configure SQL Server login and sysadmin role for domain admin
    Write-ScriptLog "Creating SQL Server login for '$DomainAdminUser'..."
    Invoke-Sql "CREATE LOGIN [$DomainAdminUser] FROM WINDOWS;"

    Write-ScriptLog "Adding '$DomainAdminUser' to sysadmin role..."
    Invoke-Sql "ALTER SERVER ROLE [sysadmin] ADD MEMBER [$DomainAdminUser];"
}
finally {
    # Stop SQL Server and restart in normal multi-user mode
    Write-ScriptLog "Stopping SQL Server to exit single-user mode..."
    Stop-Service -Name $sqlServiceName -Force

    Write-ScriptLog "Starting SQL Server in multi-user mode..."
    Start-Service -Name $sqlServiceName

    $svcStatus = (Get-Service -Name $sqlServiceName).Status

    if ($svcStatus -ne 'Running') {
        Exit-WithError "Failed to restart SQL Server in multi-user mode."
    }

    Write-ScriptLog "SQL Server restarted in multi-user mode."
}

Write-ScriptLog "'$PSCommandPath' completed successfully."
Exit 0
#endregion
