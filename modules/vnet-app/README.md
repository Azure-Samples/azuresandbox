# Application Virtual Network Module (vnet-app)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-app-diagram](./images/vnet-app-diagram.drawio.svg)

## Overview

This configuration implements a virtual network for applications including:

* A virtual network with pre-configured subnets for hosting various application workloads, including virtual machines and private endpoints implemented using PrivateLink.
  * Pre-configured virtual network peering with the `vnet-shared` virtual network.
* A network isolated Azure Files share to enable secure SMB file sharing between resources in the sandbox environment.
* A Windows Server virtual machine for use as a jumpbox with the following capabilities:
  * Secure RDP access via Bastion using a password stored in Azure Key Vault.
  * Domain joined to the `mysandbox.local` Active Directory domain.
  * Secure AD integrated access to network isolated Azure Files share.
  * Pre-installed software packages and features, including:
    * Remote Server Administration Tools (RSAT)
    * Chocolatey
    * Visual Studio Code
    * SQL Server Management Studio (SSMS)
    * MySQL Workbench

## Smoke testing

The steps in this section verify that the Windows jumpbox VM (jumpwin1) is configured correctly.

* Verify *jumpwin1* node configuration is compliant.
  * From the execution environment, navigate to *portal.azure.com* > *Automation Accounts* > *aa-sand-dev* > *Configuration Management* > *State configuration (DSC)*.
  * Refresh the *Nodes* tab until *jumpwin1* reports a status of `Compliant`.
    * When *jumpwin1* node status is `Compliant`, click the *jumpwin1* node to view details.
    * Click on the most recent *Consistency* report with the status `Compliant` to view details.
    * Look for the *Resources* section. If no resources are listed, wait 15 minutes and refresh again until the latest *Consistency* report includes data in *Resources*.
    * Verify that the *Resources* section includes the following:

      Resource | Status
      --- | ---
      WindowsFeature | Compliant
      cChocoInstaller | Compliant
      cChocoPackageInstaller | Compliant
      xDSCDomainjoin | Compliant
      ADGroup | Compliant

* From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumpwin1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose `Password from Azure Key Vault`
  * For *username* enter the UPN of the domain admin, which by default is `bootstrapadmin@mysandbox.local`
  * For *Azure Key Vault Secret* specify the following values:
    * For *Subscription* choose the same Azure subscription used to provision the sandbox environment.
    * For *Azure Key Vault* choose the key vault associated with the sandbox environment, e.g. *kv-sand-dev-xxxxxxxx*.
    * For *Azure Key Vault Secret* choose `adminpassword`
  * Click *Connect*

* From *jumpwin1*, disable Server Manager
  * Navigate to *Server Manager* > *Manage* > *Server Manager Properties* and enable *Do not start Server Manager automatically at logon*
  * Close Server Manager

* From *jumpwin1*, inspect the *mysandbox.local* Active Directory domain
  * Navigate to *Start* > *Windows Tools* > *Active Directory Users and Computers*.
  * Navigate to *mysandbox.local* and verify that a computer account exists in the root for the storage account, e.g. *stsanddevxxxxxxxx*.
  * Navigate to *mysandbox.local* > *Computers* and verify that *jumpwin1* is listed.
  * Navigate to *mysandbox.local* > *Domain Controllers* and verify that *adds1* is listed.

* From *jumpwin1*, inspect the *mysandbox.local* DNS zone
  * Navigate to *Start* > *Windows Tools* > *DNS*
  * Connect to the DNS Server on *adds1*.
  * Click on *adds1* in the left pane
    * Double-click on *Forwarders* in the right pane.
    * Verify that [168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) is listed. This ensures that the DNS server will forward any DNS queries it cannot resolve to the Azure Recursive DNS resolver.
    * Click *Cancel*.
    * Navigate to *adds1* > *Forward Lookup Zones* > *mysandbox.local* and verify that there are *Host (A)* records for *adds1* and *jumpwin1*.

* Test DNS queries for Azure Files private endpoint
  * From the execution environment, navigate to *portal.azure.com* > *Storage accounts* > *stsanddevxxxxxxxx* > *File shares* > *myfileshare* and copy the the FQDN portion of the `Share URL`, e.g. *stsanddevxxxxxxxx.file.core.windows.net*.
  * From *jumpwin1*, execute the following command from PowerShell:
  
    ```powershell
    Resolve-DnsName stsanddevxxxxxxxx.file.core.windows.net
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.

* From *jumpwin1*, test SMB connectivity with integrated Windows Authentication to Azure Files private endpoint (PaaS)
  * Execute the following command from PowerShell:
  
    ```powershell
    # Note: replace stxxxxxxxxxxxxx with the name of your storage account
    net use z: \\stsanddevxxxxxxxx.file.core.windows.net\myfileshare
    ```

  * Create some test files and folders on the newly mapped Z: drive.

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

### Module Structure

This module is organized as follows:

```plaintext
├── images/
|   └── vnet-app-diagram.drawio.svg             # Architecture diagram
├── scripts/
|   ├── Invoke-AzureFilesConfiguration.ps1      # Starts Azure Files configuration task
|   ├── JumpBoxConfiguration.ps1                # DSC configuration for Windows jumpbox VM    
|   ├── Register-DscNode.ps1                    # Registers a VM with Azure Automation DSC
|   ├── Set-AutomationAccountConfiguration.ps1  # Configures Azure Automation settings
|   └── Set-AzureFilesConfiguration.ps1         # Configures Azure Files Kerberos authentication with local AD domain
├── compute.tf                                  # Compute resource configurations   
├── locals.tf                                   # Local variables
├── main.tf                                     # Resource configurations  
├── network.tf                                  # Network resource configurations  
├── outputs.tf                                  # Output variables
├── storage.tf                                  # Storage resource configurations
├── terraform.tf                                # Terraform configuration block
└── variables.tf                                # Input variables
```

### Input Variables

This section lists the default values for the input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
adds_domain_name | mysandbox.local | The domain name defined in the vnet-shared module.
admin_password_secret | adminpassword | The name of the key vault secret that contains the password for the admin account. Defined in the vnet-shared module.
admin username_secret | adminuser | The name of the key vault secret that contains the user name for the admin account. Defined in the vnet-shared module.
automation_account_name | aa-sand-dev | The name of the Azure Automation account used for DSC. Defined in the vnet-shared module.
dns_server | `10.1.1.4` | The IP address of the DNS server used for the virtual network. Defined in the vnet-shared module.
firewall_route_table_id | | The ID of the route table used for the firewall. Defined in the vnet-shared module.
key_vault_id | | The ID of the key vault defined in the root module.
key_vault_name | | The name of the key vault defined in the root module.
location | | The Azure region defined in the root module.
resource_group_name | | The name of the resource group defined in the root module.
storage_container_name | scripts | The name of the storage container used to store scripts.
storage_share_name | myfileshare | The name of the Azure Files share.
storage_share_quota_gb | 1024 | The quota for the Azure Files share in GB.
subnet_application_address_prefix | `10.2.0.0/24` | The address prefix for the application subnet.
subnet_appservice_address_prefix | `10.2.4.0/24` | The address prefix for the app service subnet.
subnet_database_address_prefix | `10.2.1.0/24` | The address prefix for the database subnet.
subnet_misc_address_prefix | `10.2.3.0/24` | The address prefix for the miscellaneous subnet.
subnet_privatelink_address_prefix | `10.2.2.0/24` | The address prefix for the private link subnet.
tags | | The tags defined in the root module.
unique_seed | | The unique seed used to generate unique names for resources. Defined in the root module.
user_object_id | | The object ID of the interactive user. Defined in the root module.
virtual_network_shared_id | | The resource ID of the shared services virtual network (vnet-shared). Defined in the root module.
virtual_network_shared_name | | The name of the shared services virtual network (vnet-shared). Defined in the root module.
vm_jumpbox_win_image_offer | `WindowsServer` | The offer type of the virtual machine image used to create the Windows Jumpbox VM.
vm_jumpbox_win_image_publisher | `MicrosoftWindowsServer` | The publisher for the virtual machine image used to create the Windows Jumpbox VM.
vm_jumpbox_win_image_sku | `2025-datacenter-azure-edition` | The SKU for the virtual machine image used to create the Windows Jumpbox VM.
vm_jumpbox_win_image_version | `Latest` | The version of the virtual machine image used to create the Windows Jumpbox VM.
vm_jumpbox_win_name | jumpwin1 | The name of the Windows jumpbox VM.
vm_jumpbox_win_size | `Standard_B2ls_v2` | The size of the Windows jumpbox VM.
vm_jumpbox_win_storage_account_type | `Standard_LRS` | The storage account type used for the managed disks attached to the Windows jumpbox VM.
vnet_address_space | `10.2.0.0/16` | The address space for the application virtual network.
vnet_name | app | The name of the application virtual network.

### Module Resources

This section lists the resources included in this configuration.

Address | Name | Notes
--- | --- | ---
module.vnet_app[0].azurerm_network_interface.this | nic&#8209;sand&#8209;dev&#8209;jumpwin1 | Network interface for the Windows jumpbox VM.
module.vnet_app[0].azurerm_network_security_group.groups[*] | | NSGs for each subnet.
module.vnet_app[0].azurerm_network_security_rule.rules[*] | | NSG rules for each NSG. See locals.tf for rule definitions.
module.vnet_app[0].azurerm_private_dns_a_record.storage_blob | | A record for the blob storage private endpoint.
module.vnet_app[0].azurerm_private_dns_a_record.storage_file | | A record for the file storage private endpoint.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.api.azureml.ms"] | | Private DNS zone for use with AI Foundry.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.azurecr.io"] | | Private DNS zone for Azure Container Registry.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.blob.core.windows.net"] | | Private DNS zone for Azure Blob storage.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.cognitiveservices.azure.com"] | | Private DNS zone for use with AI Foundry.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.database.windows.net"] | | Private DNS zone for Azure SQL Database.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.documents.azure.com"] | | Private DNS zone for Azure Cosmos DB.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.file.core.windows.net"] | | Private DNS zone for Azure Files.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.mysql.database.azure.com"] | | Private DNS zone for Azure MySQL Database.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.notebooks.azure.net"] | | Private DNS zone for use with AI Foundry.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.openai.azure.com"] | | Private DNS zone for use with AI Foundry.
module.vnet_app[0].azurerm_private_dns_zone.zones["privatelink.search.windows.net"] | | Private DNS zone for use with AI Foundry.
module.vnet_app[0].azurerm_private_dns_zone_virtual_network_link.vnet_app_links[*] | | Private DNS zone virtual network links for the application virtual network.
module.vnet_app[0].azurerm_private_dns_zone_virtual_network_link.vnet_shared_links[*] | | Private DNS zone virtual network links for the shared services virtual network.
module.vnet_app[0].azurerm_private_endpoint.storage_blob | pe&#8209;sand&#8209;dev&#8209;storage&#8209;blob | Private endpoint for the blob storage endpoint.
module.vnet_app[0].azurerm_private_endpoint.storage_file | pe&#8209;sand&#8209;dev&#8209;storage&#8209;file | Private endpoint for the file storage endpoint.
module.vnet_app[0].azurerm_role_assignment.assignments_storage[*] | | Role assignments for the storage account as defined in locals.tf.
module.vnet_app[0].azurerm_role_assignment.assignments_vm_win[*] | | Role assignments for the Windows jumpbox VM as defined in locals.tf.
module.vnet_app[0].azurerm_storage_account.this | stsanddevxxxxxxxx | Storage account for the blob and file storage.
module.vnet_app[0].azurerm_storage_blob.remote_scripts["orchestrator"] | Invoke-AzureFilesConfiguration.ps1 | Orchestration script run by custom script extension on the Windows jumpbox VM to launch Set-AzureFilesConfiguration.ps1 as a task.
module.vnet_app[0].azurerm_storage_blob.remote_scripts["worker"] | Set-AzureFilesConfiguration.ps1 | Worker script run by Invoke-AzureFilesConfiguration.ps1 on the Windows jumpbox VM to configure Azure Files Kerberos authentication with local AD domain.
module.vnet_app[0].azurerm_storage_container.this | scripts | Storage container for scripts.
module.vnet_app[0].azurerm_storage_share.this | myfileshare | Azure Files share for the sandbox environment.
module.vnet_app[0].azurerm_subnet.subnets["snet-app-01"] | | Dedicated subnet for jumbox VMs, application servers and web front ends.
module.vnet_app[0].azurerm_subnet.subnets["snet-appservice-01"] | | Dedicated subnet for Azure App Service.
module.vnet_app[0].azurerm_subnet.subnets["snet-db-01"] | | Dedicated subnet for database server VMs.
module.vnet_app[0].azurerm_subnet.subnets["snet-misc-03"] | | Reserved for future use by optional configurations.
module.vnet_app[0].azurerm_subnet.subnets["snet-privatelink-01"] | | Dedicated subnet for PrivateLink endpoints.
module.vnet_app[0].azurerm_subnet_network_security_group_association.associations[*] | | Associates the NSGs with the subnets.
module.vnet_app[0].azurerm_subnet_route_table_association.associations[*] | | Associates the route table with the subnets.
module.vnet_app[0].azurerm_virtual_machine_extension.this | | Custom script extension for the Windows jumpbox VM.
module.vnet_app[0].azurerm_virtual_network.this | vnet&#8209;sand&#8209;dev&#8209;app | Virtual network for application workloads in the sandbox environment.
module.vnet_app[0].azurerm_virtual_network_peering.app_to_shared | | Virtual network peering from the application virtual network to the shared services virtual network (vnet-shared).
module.vnet_app[0].azurerm_virtual_network_peering.shared_to_app | | Virtual network peering from the shared services virtual network (vnet-shared) to the application virtual network.
module.vnet_app[0].azurerm_windows_virtual_machine.this | jumpwin1 | Domain joined Windows jumpbox VM. Required to establish Azure Files AD integration.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Default | Comments
--- | --- | ---
azure_files_config_vm_extension_id | | Dependent modules can reference this output to determine if Azure Files configuration is complete.
private_dns_zones | | A map of private DNS zones provisioned in the module.
resource_ids | | A map of resource IDs for key resources in the module.
resource_names | | A map of resource names for key resources in the module.
storage_container_name | scripts | The name of the storage container used to store scripts.
storage_endpoints | | A map of storage endpoints for blob and file storage.
storage_share_name | myfileshare | The name of the Azure Files share.
subnets | | A list of subnets provisioned in the application virtual network.
