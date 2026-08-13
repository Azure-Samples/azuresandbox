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

# Application name the single-user-mode instance is restricted to (via the -m"<app>" startup option) and
# that this script's connections identify themselves with. When SQL Server is started in single-user mode
# without an application-name restriction, ANY process (SQL Agent, the Azure Monitor Agent, anti-malware,
# etc.) can grab the single reserved connection first. If that happens, this script's connection either
# fails to open or opens without sysadmin rights, producing the "User does not have permission to perform
# this action" error seen on CREATE LOGIN. Restricting single-user mode to this application name reserves
# the connection for this script. The value is case-sensitive and must match the -m"<app>" argument.
$SingleUserAppName = 'ConfigureSqlLogin'

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
    $cxnstring."Application Name" = $SingleUserAppName

    $maxRetries = 10
    $retryCount = 0
    $retryDelay = 30

    # The retry loop wraps the ENTIRE connect + execute cycle (with a fresh connection each attempt), not
    # just Open(). The single-user-mode race can also surface as a permission error on ExecuteNonQuery (the
    # connection opens but isn't the privileged single-user session yet), so retrying only the open is not
    # enough - the whole operation must be retried until it succeeds or the attempts are exhausted.
    while ($true) {
        $retryCount++
        $cxn = New-Object System.Data.SqlClient.SqlConnection($cxnstring.ConnectionString)

        try {
            $cxn.Open()
            $cmd = $cxn.CreateCommand()
            $cmd.CommandText = $SqlCommand
            $cmd.ExecuteNonQuery() | Out-Null
            return
        }
        catch {
            if ($retryCount -ge $maxRetries) {
                Exit-WithError "Invoke-Sql: Failed to execute SQL command after $maxRetries attempts. Last error: $($_.Exception.Message)"
            }

            Write-ScriptLog "Invoke-Sql: Attempt $retryCount failed ($($_.Exception.Message)). Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
        }
        finally {
            if ($cxn.State -ne [System.Data.ConnectionState]::Closed) {
                $cxn.Close()
            }

            $cxn.Dispose()
        }
    }
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

Write-ScriptLog "Starting SQL Server in single-user mode (restricted to application '$SingleUserAppName')..."
net start $sqlServiceName "/m$SingleUserAppName" | Out-Null

$svcStatus = (Get-Service -Name $sqlServiceName).Status

if ($svcStatus -ne 'Running') {
    Exit-WithError "Failed to start SQL Server in single-user mode."
}

Write-ScriptLog "SQL Server started in single-user mode."

try {
    # Configure SQL Server login and sysadmin role for domain admin
    Write-ScriptLog "Creating SQL Server login for '$DomainAdminUser'..."
    Invoke-Sql "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$DomainAdminUser') CREATE LOGIN [$DomainAdminUser] FROM WINDOWS;"

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
