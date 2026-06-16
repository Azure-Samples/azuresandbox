# Azure SQL VM Ephemeral NVMe Storage – Startup Automation

## Problem

On Azure v6, v7-series, and FXmdsv2 VMs, local NVMe temp disks arrive as **RAW unformatted disks** after every stop/deallocate event. If SQL Server has tempdb configured on the ephemeral drive, it fails to start because the tempdb folder no longer exists.

This is also a problem when tempdb is still on `C:\` (the OS disk) and needs to be moved to the ephemeral drive for optimal performance — the default SQL Server installation places tempdb on `C:\`, which has limited IOPS and is not suited for production tempdb workloads.

### Reference

- [SQL VM Fails to Deploy or SQL Server Instance Can't Come Online](https://learn.microsoft.com/en-us/troubleshoot/sql/azure-sql/sql-deployment-fails-drive-not-ready)
- [Ephemeral Storage Affected VMs - SQL VM Fails to Deploy](https://learn.microsoft.com/en-us/troubleshoot/sql/azure-sql/sql-deployment-fails-drive-not-ready#impacted-vms)

### This solution

1. Provides a one-time T-SQL script to move tempdb from `C:\` to the ephemeral drive
2. Automatically re-provisions the NVMe storage and starts SQL Server on every subsequent boot

## Files

| File | Purpose |
|------|---------|
| `Set-MssqlStartupConfiguration.ps1` | Startup script — pools/formats NVMe disks, creates SQLTEMP folder, starts SQL Server |
| `Register-MssqlStartupTask.cmd` | One-time setup — sets services to Manual, registers the scheduled task |
| `Register-MssqlStartupTask.ps1` | One-time setup helper — called by the .cmd file |
| `Move-TempdbToEphemeral.sql` | One-time T-SQL — moves all tempdb files from current location to `T:\SQLTEMP` |

## Prerequisites

- **OS:** Windows Server 2025
- **SQL Server:** SQL Server 2022 or 2025 (default instance)
- **VM Size:** Azure v6-series with local NVMe temp storage (also supports v5-series with SCSI temp disk)
- **Administrator access:** The .cmd setup script must be run as Administrator
- **sysadmin role:** The T-SQL script must be run as a sysadmin on the SQL Server instance

## Installation

### Step 1: Copy files to the VM

Copy the automation files to `C:\Scripts\` on the Azure VM:

```text
C:\Scripts\
├── Set-MssqlStartupConfiguration.ps1
├── Register-MssqlStartupTask.cmd
├── Register-MssqlStartupTask.ps1
└── Move-TempdbToEphemeral.sql
```

### Step 2: Register the scheduled task (once)

Open an **Administrator command prompt** and run:

```cmd
C:\Scripts\Register-MssqlStartupTask.cmd
```

This will:

1. Set `MSSQLSERVER` and `SQLSERVERAGENT` services to **Manual** startup
2. Register a Windows Scheduled Task named **"SQL Server Startup - Ephemeral Storage"** that runs at every boot as `NT AUTHORITY\SYSTEM`

You should see:

```text
=== Setting SQL Server services to Manual startup ===
[SC] ChangeServiceConfig SUCCESS
[SC] ChangeServiceConfig SUCCESS

=== Registering scheduled task: SQL Server Startup - Ephemeral Storage ===
=== SUCCESS: Scheduled task registered. ===
```

### Step 3: Move tempdb to the ephemeral drive (once)

If tempdb is currently on `C:\` or any other non-ephemeral location, you need to move it **once** to `T:\SQLTEMP`.

> **Important:** The `T:\` volume must already exist before running this step. If this is a fresh v6-series VM, either run `Set-MssqlStartupConfiguration.ps1` manually first to provision the drive, or trigger a stop/start cycle so the scheduled task provisions it.

Open **SQL Server Management Studio (SSMS)**, connect to the instance as sysadmin, and run `Move-TempdbToEphemeral.sql`:

```sql
-- Move all tempdb data and log files to T:\SQLTEMP
USE master;
GO

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + 
    N'ALTER DATABASE tempdb MODIFY FILE (NAME = ' + QUOTENAME(name, '''') + 
    N', FILENAME = ''T:\SQLTEMP\' + 
    REVERSE(LEFT(REVERSE(physical_name), CHARINDEX('\', REVERSE(physical_name)) - 1)) + 
    N''');' + CHAR(13) + CHAR(10)
FROM sys.master_files
WHERE database_id = DB_ID('tempdb');

PRINT @sql;
EXEC sp_executesql @sql;
GO
```

The output will confirm the ALTER statements for each tempdb file. These changes take effect on the **next SQL Server restart**.

### Step 4: Restart SQL Server

After moving tempdb, restart SQL Server to apply the changes:

```powershell
Restart-Service MSSQLSERVER -Force
Start-Service SQLSERVERAGENT
```

Verify tempdb is now on the ephemeral drive:

```sql
SELECT name, physical_name, type_desc
FROM sys.master_files
WHERE database_id = DB_ID('tempdb');
```

All files should show `T:\SQLTEMP\` as the path.

### Step 5: Test the full deallocation cycle

1. **Stop/deallocate** the VM from the Azure portal
2. **Start** the VM
3. After boot, verify:
   - `T:` drive exists and is formatted NTFS
   - `T:\SQLTEMP` folder exists
   - SQL Server and SQL Agent services are running
   - Check the log: `C:\Scripts\Set-MssqlStartupConfiguration.log`

## How It Works

On every VM start, the scheduled task executes `Set-MssqlStartupConfiguration.ps1` which:

1. **Detects the temp drive** — checks for existing D: (v5) or T: (v6)
2. **If volume is missing** — finds RAW NVMe Direct Disks, pools them via Storage Spaces (Simple/RAID-0), formats NTFS with 64KB allocation unit, assigns drive letter T:
3. **Creates SQLTEMP folder** — with correct ACLs for the SQL Server service account
4. **Starts SQL Server** — then starts SQL Agent

If the volume already exists (soft reboot, no deallocation), it skips provisioning and just ensures the folder and services are ready.

## Customization

| Setting | Location | Default |
|---------|----------|---------|
| Drive letter | `$NVMeDriveLetter` in .ps1 | `T` |
| Temp folder name | `$TempFolderName` in .ps1 | `SQLTEMP` |
| Allocation unit size | `$AllocationUnit` in .ps1 | `65536` (64KB) |
| SQL instance name | `$SQLServiceName` in .ps1 | `MSSQLSERVER` |
| Script path | `-File` argument in Register .ps1 | `C:\Scripts\Set-MssqlStartupConfiguration.ps1` |

For a **named instance**, change:

```powershell
$SQLServiceName = "MSSQL$MYINSTANCE"
$SQLAgentName   = "SQLAgent$MYINSTANCE"
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| SQL Server not starting after dealloc | Review `C:\Scripts\Set-MssqlStartupConfiguration.log` |
| Task not running | Task Scheduler → check "SQL Server Startup - Ephemeral Storage" last run result |
| NVMe disks not detected | Run `Get-PhysicalDisk \| where FriendlyName -like '*NVMe Direct*'` |
| Drive letter conflict | Ensure no other disk/DVD uses T: |
| Permission denied on SQLTEMP | Check ACL: `Get-Acl T:\SQLTEMP \| Format-List` |
| tempdb still on C:\ after restart | Re-run `Move-TempdbToEphemeral.sql` and verify with `SELECT physical_name FROM sys.master_files WHERE database_id = 2` |
| T:\ drive doesn't exist before moving tempdb | Run `Set-MssqlStartupConfiguration.ps1` manually first, or stop/start the VM to trigger the scheduled task |

## Complete Setup Order

For clarity, here is the full sequence for a new VM:

1. Deploy VM and install SQL Server (tempdb defaults to `C:\`)
2. Copy all scripts to `C:\Scripts\`
3. Run `Register-MssqlStartupTask.cmd` as Administrator (one-time)
4. Stop/start the VM (or run `Set-MssqlStartupConfiguration.ps1` manually) to provision `T:\`
5. Run `Move-TempdbToEphemeral.sql` in SSMS (one-time)
6. Restart SQL Server — tempdb is now on `T:\SQLTEMP`
7. Future stop/deallocate cycles are handled automatically by the scheduled task

## References

- [Place tempdb on ephemeral storage (Microsoft Learn)](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/tempdb-ephemeral-storage)
- [FAQ for Temp NVMe disks](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-temp-faqs)
- [Storage best practices for SQL Server on Azure VMs](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/performance-guidelines-best-practices-storage)
