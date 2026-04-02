# SQL Server Virtual Machine Module (vm-mssql-win)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vm-mssql-diagram](./images/vm-mssql-diagram.drawio.svg)

## Overview

This configuration implements a SQL Server virtual machine. The VM is pre-configured with the following capabilities:

* Domain joined to the *mysandbox.local* Active Directory domain.
* Pre-configured SQL Server data and log disks.
* Pre-configured SQL Server instance.

The estimated provisioning time for this module is 31 minutes.

## Smoke testing

This section describes how to test the module after deployment.

* From *jumpwin1*, test DNS queries for SQL Server (IaaS)
  * Execute the following command from PowerShell:

    ```powershell
    Resolve-DnsName mssqlwin1
    ```

  * Verify the IPAddress returned is within the subnet IP address prefix for *vnet_app[0].subnets["snet-db-01"]*, e.g. `10.2.1.*`.
* From *jumpwin1*, test SQL Server Connectivity with SQL Server Management Studio (SSMS)
  * Navigate to *Start* > *Microsoft SQL Server Tools 22* > *Microsoft SQL Server Management Studio 22*
  * Connect to the default instance of SQL Server installed on the SQL Server virtual machine using the following connection properties:
    * Server name: *mssqlwin1*
    * Authentication: *Windows Authentication*
    * User Name: *MYSANDBOX\bootstrapadmin*
    * Database Name *default*
    * Encryption: *Mandatory*
    * Trust Server Certificate: *enabled*
      * Note: In a production environment it is recommended to disable this and use certificate validation when connecting to SQL Server.
  * Create a new database named *testdb*.
    * Verify the data files were stored on the *M:* drive
    * Verify the log file were stored on the *L:* drive

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root module
* vnet-shared module
* vnet-app module

### Module Structure

The module is organized as follows:

```plaintext
├── images/
|   └── vm-mssql-diagram.drawio.svg       # Architecture diagram
├── scripts/
|   ├── Configure-FirewallRules.ps1       # Configures Windows firewall rules for SQL Server
|   ├── Configure-SqlLogin.ps1            # Creates SQL Server login for domain admin and adds it to sysadmin server role
|   ├── Invoke-MssqlConfiguration.ps1     # Runs Set-MssqlConfiguration.ps1 as domain admin and reboots the VM
|   ├── Set-MssqlConfiguration.ps1        # Prepares data and log disks and configures SQL Server instance
|   ├── Set-MssqlStartupConfiguration.ps1 # Re-configures SQL Server tempdb folder after VM stop/deallocate event
|   └── Test-VmMssqlWin.ps1               # Unit test script
├── compute.tf                            # Compute resource configurations
├── locals.tf                             # Local variables
├── main.tf                               # Resource configurations
├── network.tf                            # Network resource configurations
├── outputs.tf                            # Output variables
├── storage.tf                            # Storage resource configurations
├── terraform.tf                          # Terraform configuration block
└── variables.tf                          # Input variables
```

### Input Variables

This section lists input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
adds_domain_name | mysandbox.local | The domain name defined in the vnet-shared module.
admin_password | | The password used when provisioning administrator accounts. This should conform to Windows password requirements (uppercase, lowercase, number, special character, 8 characters minimum). Defined in the vnet-shared module.
admin_password_secret | adminpassword | The name of the key vault secret that contains the password for the admin account. Defined in the vnet-shared module.
admin_username | bootstrapadmin | The user name used when provisioning administrator accounts. This should conform to Windows username requirements (alphanumeric characters, periods, underscores, and hyphens, 1-20 characters). Defined in the vnet-shared module.
admin_username_secret | adminuser | The name of the key vault secret that contains the user name for the admin account. Defined in the vnet-shared module.
key_vault_id | | The ID of the key vault defined in the root module.
key_vault_name | | The name of the key vault defined in the root module.
location | | The name of the Azure Region where resources will be provisioned.
resource_group_name | | The name of the resource group defined in the root module.
storage_account_id | | The ID of the storage account defined in the vnet-app module.
storage_account_name | | The name of the storage account defined in the vnet-app module.
storage_container_name | scripts | The name of the storage container defined in the vnet-app module.
storage_blob_endpoint | | The blob endpoint for the storage account defined in the vnet-app module.
subnet_id | | The subnet ID defined in the vnet-app module.
tags | | The tags from the root module.
vm_mssql_win_image_offer | `sql2025-ws2025` | The offer type of the virtual machine image used to create the SQL Server VM.
vm_mssql_win_image_publisher | `MicrosoftSQLServer` | The publisher for the virtual machine image used to create the SQL Server VM.
vm_mssql_win_image_sku | `entdev-gen2` | The SKU of the virtual machine image used to create the SQL Server VM.
vm_mssql_win_image_version | `Latest` | The version of the virtual machine image used to create the SQL Server VM.
vm_mssql_win_name | mssqlwin1 | The name of the SQL Server VM.
vm_mssql_win_size | `Standard_D4ds_v6` | The size of the virtual machine. Tempdb will be configured to use the local temp disk disk for "diskful" sizes, or moved to the data disk for sizes that are not "diskful".
vm_mssql_win_storage_account_type_data_disks | `PremiumV2_LRS` | The storage type to be used for the VM's data disks.
vm_mssql_win_storage_account_type_os_disk | `Premium_LRS` | The storage type to be used for the VM's OS disk.
vm_mssql_win_zone | 2 | The availability zone to to provision the VM.

### Module Resources

This section lists the resources included in this module.

Address | Name | Notes
--- | --- | ---
module.vm_mssql_win[0].azurerm_managed_disk.disks["sqldata"] | disk&#8209;sand&#8209;dev&#8209;vol_sqldata_M | The managed disk for SQL Server data. The format of the *vol_* portion is used by automation to locate SQL Server data files vs. log files and set the drive letter mapping.
module.vm_mssql_win[0].azurerm_managed_disk.disks["sqllog"] | disk&#8209;sand&#8209;dev&#8209;vol_sqllog_L | The managed disk for SQL Server logs. The format of the *vol_* portion is used by automation to locate SQL Server data files vs. log files and set the drive letter mapping.
module.vm_mssql_win[0].azurerm_network_interface.this | nic&#8209;sand&#8209;dev&#8209;mssqlwin1 | The network interface associated with the SQL Server VM. Configured with accelerated networking enabled for improved performance.
module.vm_mssql_win[0].azurerm_role_assignment.assignments[*] | | Key vault and storage role assignments for the SQL Server VM. See *locals.tf* for definitions.
module.vm_mssql_win[0].azurerm_storage_blob.remote_scripts["orchestrator"] | Invoke&#8209;MssqlConfiguration.ps1 | The script that starts the SQL Server configuration task.
module.vm_mssql_win[0].azurerm_storage_blob.remote_scripts["startup"] | Set&#8209;MssqlStartupConfiguration.ps1 | The script that re-configures SQL Server tempdb folder for VM sizes with temporary disks.
module.vm_mssql_win[0].azurerm_storage_blob.remote_scripts["worker"] | Set&#8209;MssqlConfiguration.ps1 | The script that prepares data and log disks and configures SQL Server instance.
module.vm_mssql_win[0].azurerm_virtual_machine_data_disk_attachment.attachments[*] | | The data and log disk attachments for the SQL Server VM.
module.vm_mssql_win[0].azurerm_windows_virtual_machine.this | mssqlwin1 | The SQL Server VM resource. Configured with NVMe disk controller, encryption at host, secure boot, vTPM, and automatic patch assessment for enhanced security and performance.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Description
--- | ---
resource_ids | A map of resource IDs for key resources in the module.
resource_names | A map of resource names for key resources in the module.
