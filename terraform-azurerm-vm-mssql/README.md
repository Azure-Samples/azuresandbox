# \#AzureSandbox - terraform-azurerm-vm-mssql

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)
* [Videos](#videos)

## Architecture

![vm-mssql-diagram](./vm-mssql-diagram.drawio.svg)

## Overview

This configuration implements an [IaaS](https://azure.microsoft.com/overview/what-is-iaas/) database server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) based on the [SQL Server virtual machines in Azure](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/sql-server-on-azure-vm-iaas-what-is-overview#payasyougo) offering ([Step-By-Step Video](https://youtu.be/2wkGPxqNm-M)).

Activity | Estimated time required
--- | ---
Pre-configuration | ~10 minutes
Provisioning | ~15 minutes
Smoke testing | ~10 minutes

## Before you start

[terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app) must be provisioned first before starting. This configuration is optional and can be skipped to reduce costs. Proceed with [terraform-azurerm-mssql](../terraform-azurerm-mssql) if you wish to skip it.

## Getting started

This section describes how to provision this configuration using default settings ([Step-By-Step Video](https://youtu.be/Qk8OIW-VgHs)).

* Change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-vm-mssql
  ```

* Add an environment variable containing the password for the service principal.

  ```bash
  export TF_VAR_arm_client_secret=YourServicePrincipalSecret
  ```

* Run [bootstrap.sh](./bootstrap.sh) using the default settings or custom settings.

  ```bash
  ./bootstrap.sh
  ```

* Apply the Terraform configuration.

  ```bash
  # Initialize terraform providers
  terraform init

  # Validate configuration files
  terraform validate

  # Review plan output
  terraform plan

  # Apply configuration
  terraform apply
  ```

* Monitor output. Upon completion, you should see a message similar to the following:

  `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

Perform the following tests to validate the configuration is provisioned correctly ([Step-By-Step Video](https://youtu.be/uedt5wKIrcY))

* Verify *mssqlwin1* node configuration is compliant.
  * Wait for 15 minutes to proceed to allow time for DSC configurations to complete.
  * From the client environment, navigate to *portal.azure.com* > *Automation Accounts* > *auto-xxxxxxxxxxxxxxxx-01* > *Configuration Management* > *State configuration (DSC)*.
  * Refresh the data on the *Nodes* tab and verify that all nodes are compliant.
  * Review the data in the *Configurations* and *Compiled configurations* tabs as well.
* From *jumpwin1*, test DNS queries for SQL Server (IaaS)
  * Execute the following command from PowerShell:

    ```powershell
    Resolve-DnsName mssqlwin1
    ```

  * Verify the IPAddress returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-db-01"]*, e.g. `10.2.1.*`.
* From *jumpwin1*, test SQL Server Connectivity with SQL Server Management Studio (SSMS)
  * Navigate to *Start* > *Microsoft SQL Server Tools 20* > *Microsoft SQL Server Management Studio 20*
  * Connect to the default instance of SQL Server installed on the database server virtual machine using the following settings:
    * Server
      * Server type: `Database Engine`
      * Server name: `mssqlwin1`
      * Authentication: `Windows Authentication` (this will default to *MYSANDBOX\bootstrapadmin*)
    * Connection security
      * Encryption: `Optional`
  * Create a new database named *testdb*.
    * Verify the data files were stored on the *M:* drive
    * Verify the log file were stored on the *L:* drive

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans ([Step-By-Step Video](https://youtu.be/Jzi58S7lBJ8)). For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* file associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared;) and [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app/) configurations, including:

Output variable | Sample value
--- | ---
aad_tenant_id | "00000000-0000-0000-0000-000000000000"
adds_domain_name | "mysandbox.local"
admin_password_secret | "adminpassword"
admin_username_secret | "adminuser"
arm_client_id | "00000000-0000-0000-0000-000000000000"
automation_account_name | "auto-9a633c2bba9351cc-01"
key_vault_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-XXXXXXXXXXXXXXX"
key_vault_name | "kv-XXXXXXXXXXXXXXX"
location | "eastus2"
resource_group_name | "rg-sandbox-01"
storage_account_name | "stXXXXXXXXXXXXXXX"
storage_container_name | "scripts"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
vnet_app_01_subnets | Contains all the subnet definitions including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.

Public internet access to the shared storage account is temporarily enabled so the following PowerShell scripts can be uploaded to the *scripts* container in the storage account using the access key stored in the key vault secret *storage_account_key*. These scripts are referenced by virtual machine extensions:

* [configure-vm-mssql.ps1](./configure-vm-mssql.ps1)
* [configure-mssql.ps1](./configure-mssql.ps1)
* [sql-startup.ps1](./sql-startup.ps1)

Public internet access to the shared storage account is disabled again.

Configuration of [Azure Automation State Configuration (DSC)](https://learn.microsoft.com/azure/automation/automation-dsc-overview) is performed by [configure-automation.ps1](./configure-automation.ps1) including the following:

* Configures [Azure Automation shared resources](https://learn.microsoft.com/azure/automation/automation-intro#shared-resources) including:
  * [Modules](https://learn.microsoft.com/azure/automation/shared-resources/modules)
    * Imports new modules including the following:
      * [NetworkingDsc](https://github.com/dsccommunity/NetworkingDsc)
      * [SqlServerDsc](https://github.com/dsccommunity/SqlServerDsc)
  * Imports [DSC Configuration](https://learn.microsoft.com/azure/automation/automation-dsc-getting-started#create-a-dsc-configuration) [MssqlVmConfig.ps1](./MssqlVmConfig.ps1).
  * [Compiles DSC Configuration](https://learn.microsoft.com/azure/automation/automation-dsc-compile) so it can be used later to [Register a VM to be managed by State Configuration](https://learn.microsoft.com/azure/automation/tutorial-configure-servers-desired-state#register-a-vm-to-be-managed-by-state-configuration).

### Terraform Resources

This section lists the resources included in this configuration.

#### Database server virtual machine

The configuration for these resources can be found in [020-vm-mssql-win.tf](./020-vm-mssql-win.tf) ([Step-By-Step Video](https://youtu.be/RXkPVOZZBwU)).

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine . vm_mssql_win (mssqlwin1) | By default, provisions a [Standard_B4s_v2](https://learn.microsoft.com/azure/virtual-machines/bsv2-series) virtual machine for use as a database server. See below for more information.
azurerm_network_interface . vm_mssql_win_nic_01 (nic&#x2011;mssqlwin1&#x2011;1) | The configured subnet is *azurerm_subnet.vnet_app_01_subnets["snet-db-01"]*.
azurerm_managed_disk . vm_mssql_win_data_disks ["sqldata"] (disk&#x2011;mssqlwin1&#x2011;vol_sqldata_M) | By default, provisions an E10 [Standard SSD](https://learn.microsoft.com/azure/virtual-machines/disks-types#standard-ssd) [managed disk](https://learn.microsoft.com/azure/virtual-machines/managed-disks-overview) for storing SQL Server data files. Caching is set to *ReadOnly* by default.
azurerm_managed_disk . vm_mssql_win_data_disks ["sqllog"] (disk&#x2011;mssqlwin1&#x2011;vol_sqllog_L) | By default, provisions an E4 [Standard SSD](https://learn.microsoft.com/azure/virtual-machines/disks-types#standard-ssd) [managed disk](https://learn.microsoft.com/azure/virtual-machines/managed-disks-overview) for storing SQL Server log files. Caching is set to *None* by default.
azurerm_virtual_machine_data_disk_attachment . vm_mssql_win_data_disk_attachments ["sqldata"] | Attaches *azurerm_managed_disk.vm_mssql_win_data_disks["sqldata"]* to *azurerm_windows_virtual_machine.vm_mssql_win*.
azurerm_virtual_machine_data_disk_attachment . vm_mssql_win_data_disk_attachments ["sqllog"] | Attaches *azurerm_managed_disk.vm_mssql_win_data_disks["sqllog"]* to *azurerm_windows_virtual_machine.vm_mssql_win*
azurerm_virtual_machine_extension . vm_mssql_win_postdeploy_script (vmext&#x2011;mssqlwin1&#x2011;postdeploy&#x2011;script) | Downloads [configure&#x2011;vm&#x2011;mssql.ps1](./configure-mssql.ps1) and [sql&#x2011;startup.ps1](./sql-startup.ps1) to *azurerm_windows_virtual_machine.vm_mssql_win* and executes [configure&#x2011;vm&#x2011;mssql.ps1](./configure-mssql.ps1) using the [Custom Script Extension for Windows](https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-windows).
azurerm_key_vault_access_policy . vm_mssql_win_secrets_get | Grants *azurerm_windows_virtual_machine.vm_mssql_win* access to the key vault secrets *adminuser* and *adminpassword*.

* Guest OS: Windows Server 2022 Datacenter.
* Database: Microsoft SQL Server 2022 Developer Edition
* By default the [patch assessment mode](https://learn.microsoft.com/en-us/azure/update-manager/assessment-options) is set to `AutomaticByPlatform` and `provision_vm_agent` is set to `true` to enable use of [Azure Update Manager Update or Patch Orchestration](https://learn.microsoft.com/en-us/azure/update-manager/updates-maintenance-schedules#update-or-patch-orchestration).
* *admin_username* and *admin_password* are configured using key vault secrets *adminuser* and *adminpassword*.
* This resource is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with *azurerm_automation_account.automation_account_01* and applies the configuration [MssqlVmConfig.ps1](../terraform-azurerm-vnet-shared/MssqlVmConfig.ps1). Retry logic is implemented to wait until the node registration is compliant as multiple attempts to apply the configuration are sometimes required.
  * The virtual machine is domain joined.
  * The [Windows Firewall](https://learn.microsoft.com/windows/security/threat-protection/windows-firewall/windows-firewall-with-advanced-security#overview-of-windows-defender-firewall-with-advanced-security) is [Configured to Allow SQL Server Access](https://learn.microsoft.com/sql/sql-server/install/configure-the-windows-firewall-to-allow-sql-server-access). A new firewall rule is created that allows inbound traffic over port 1433.
  * A SQL Server Windows login is added for the domain administrator and added to the SQL Server builtin `sysadmin` role.
* Post-deployment configuration is then implemented using a custom script extension that runs [configure-vm-mssql.ps1](./configure-vm-mssql.ps1) which registers [configure-mssql.ps1](./configure-mssql.ps1) as a scheduled task and executes it using domain administrator credentials.
* [configure-mssql.ps1](./configure-mssql.ps1) configures SQL Server following guidelines established in [Checklist: Best practices for SQL Server on Azure VMs](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/performance-guidelines-best-practices-checklist).
  * Data disk metadata is retrieved dynamically using the [Azure Instance Metadata Service (Windows)](https://learn.microsoft.com/azure/virtual-machines/windows/instance-metadata-service?tabs=windows) including:
    * Volume label and drive letter, e.g. *vol_sqldata_M*
    * Size
    * Lun
  * The metadata is then used to partition and format the raw data disks using the SQL Server recommended allocation unit size of 64K.
  * The *tempdb* database is moved from the OS disk to the Azure local temporary disk (D:) and special logic is implemented to avoid errors if the Azure virtual machine is stopped, deallocated and restarted on a different host. If this occurs the `D:\SQLTEMP` folder must be recreated with appropriate permissions in order to start the SQL Server.
    * The SQL Server is configured for manual startup
    * The scheduled task [sql-startup.ps1](./sql-startup.ps1) is created to recreate the `D:\SQLTEMP` folder then start SQL Server. The scheduled task is set to run automatically at startup using domain administrator credentials.
  * The data and log files for the *master*, *model* and *msdb* system databases are moved to the data and log disks respectively.
  * The SQL Server errorlog is moved to the data disk.
  * Windows Update is configured to enable first-party updates for SQL Server patching.

## Next steps

Move on to the next configuration [terraform-azurerm-mssql](../terraform-azurerm-mssql).

## Videos

Video | Section
--- | ---
[SQL Server VM (Part 1)](https://youtu.be/2wkGPxqNm-M) | [terraform-azurerm-vm-mssql \| Overview](#overview)
[SQL Server VM (Part 2)](https://youtu.be/Qk8OIW-VgHs) | [terraform-azurerm-vm-mssql \| Getting started](#getting-started)
[SQL Server VM (Part 3)](https://youtu.be/uedt5wKIrcY) | [terraform-azurerm-vm-mssql \| Smoke testing](#smoke-testing)
[SQL Server VM (Part 4)](https://youtu.be/Jzi58S7lBJ8) | [terraform-azurerm-vm-mssql \| Documentation \| Bootstrap script](#bootstrap-script)
[SQL Server VM (Part 5)](https://youtu.be/RXkPVOZZBwU) | [terraform-azurerm-vm-mssql \| Documentation \| Terraform resources](#terraform-resources)
