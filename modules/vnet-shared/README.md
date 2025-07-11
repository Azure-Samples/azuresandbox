# Shared Services Virtual Network Module (vnet-shared)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-shared-diagram](./images/vnet-shared-diagram.drawio.svg)

## Overview

This module implements a virtual network with shared services used by all the configurations including:

* An Azure Automation account for PowerShell DSC configuration of Windows VMs.
* A virtual network for hosting virtual machines, bastion hosts and firewalls..
* An Azure Bastion for secure RDP and SSH access to virtual machines in the sandbox environment.
* An Azure Firewall for network security.
* A network isolated Azure Key Vault for storing secrets.
* A Log Analytics workspace for collecting logs and metrics from Azure resources.
* A Windows virtual machine configured as an Active Directory Domain Services domain controller and DNS server.

## Smoke testing

* Explore your newly provisioned resources in the Azure portal:
  * Key vault
    * Temporarily enable public access to the key vault by navigating to *portal.azure.com* > *Key vaults* > *kv-sand-dev-xxxxxxxx* > *Networking* > *Firewalls and virtual networks* > *Allow access from:* > *Allow public access from all networks*.
    * Navigate to *portal.azure.com* > *Key vaults* > *kv-sand-dev-xxxxxxxx* > *Objects* > *Secrets* > *adminpassword* > *CURRENT VERSION* > *00000000-0000-0000-0000-000000000000* > *Show Secret Value*
    * Make a note of the *Secret value*. This is a strong password associated with the *adminuser* key vault secret. Together these credentials are used to set up initial administrative access to resources in Azure Sandbox.
    * Disable public access to the key vault by navigating to *portal.azure.com* > *Key vaults* > *kv-sand-dev-xxxxxxxx* > *Networking* > *Firewalls and virtual networks* > *Allow access from:* > *Disable public access*.
  * Bastion host
    * Navigate to *portal.azure.com* > *Bastions* > *snap-sand-dev*.
    * Review the information in the *Overview* section.
  * Firewall
    * Navigate to *portal.azure.com* > *Firewalls* > *fw-sand-dev*.
    * Review the information in the *Overview* section.
* Verify *adds1* node configuration is compliant.
  * From the client environment, navigate to *portal.azure.com* > *Automation Accounts* > *aa-sand-dev* > *Configuration Management* > *State configuration (DSC)*.
  * Refresh the data on the *Nodes* tab and verify that all nodes are compliant.
  * Review the data in the *Configurations* and *Compiled configurations* tabs as well.

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)

### Dependencies

This module depends upon resources provisioned in the root module.

### Module Structure

The module is organized as follows:

```plaintext
vnet-shared/
├── images/                        
│   └── vnet-shared-diagram.drawio.svg          # Architecture diagram
├── scripts/                                    
│   ├── DomainControllerConfiguration.ps1       # DSC configuration for the AD DS Domain Controller VM
│   ├── Register-DscNode.ps1                    # Script to register VM with Azure Automation DSC
│   └── Set-AutomationAccountConfiguration.ps1  # Script to configure Azure Automation settings
├── compute.tf                                  # Compute resource configurations
├── locals.tf                                   # Local variables
├── main.tf                                     # Resource configurations
├── network.tf                                  # Network resource configurations 
├── outputs.tf                                  # Output variables
├── terraform.tf                                # Terraform configuration block
└── variables.tf                                # Input variables
```

### Input Variables

This section documents default values for module variables as defined in `variables.tf`. Defaults can be overridden by passing values to the module when it is called.

Variable | Default | Description
--- | --- | ---
adds_domain_name | mysandbox.local | The AD DS domain name.
admin_password_secret | adminpassword | The name of the key vault secret containing the admin password.
admin_username | bootstrapadmin | The default admin username used when configuring services.
admin_username_secret | adminuser | The name of the key vault secret containing the admin username.
arm_client_secret |  | The password for the service principal used for authenticating with Azure. Set interactively or using an environment variable 'TF_VAR_arm_client_secret'.
location |  | The Azure region defined in the root module.
log_analytics_workspace_retention_days | 30 | The retention period for the new log analytics workspace.
resource_group_name |  | The resource group defined in the root module.
subnet_adds_address_prefix | 10.1.1.0/24 | The address prefix for the AD Domain Services subnet.
subnet_AzureBastionSubnet_address_prefix | 10.1.0.0/27 | The address prefix for the AzureBastionSubnet subnet.
subnet_AzureFirewallSubnet_address_prefix | 10.1.4.0/26 | The address prefix for the AzureFirewallSubnet subnet.
subnet_misc_address_prefix | 10.1.2.0/24 | The address prefix for the miscellaneous subnet.
subnet_misc_02_address_prefix | 10.1.3.0/24 | The address prefix for the miscellaneous 2 subnet.
subnet_privatelink_address_prefix | 10.1.5.0/24 | The address prefix for the PrivateLink subnet.
tags |  | The tags defined in the root module.
user_object_id |  | The object id of the interactive user in Microsoft Entra ID.
vm_adds_image_offer | WindowsServer | The offer type of the virtual machine image used to create the VM.
vm_adds_image_publisher | MicrosoftWindowsServer | The publisher for the virtual machine image used to create the VM.
vm_adds_image_sku | 2025-datacenter-azure-edition-core | The SKU of the virtual machine image used to create the VM.
vm_adds_image_version | Latest | The version of the virtual machine image used to create the VM.
vm_adds_name | adds1 | The name of the VM.
vm_adds_size | Standard_B2ls_v2 | The size of the virtual machine.
vm_adds_storage_account_type | Standard_LRS | The storage type to be used for the VM's managed disks.
vnet_address_space | 10.1.0.0/16 | The address range for the virtual network.
vnet_name | shared | The name of the new virtual network.

### Module Resources

Address | Name | Notes
--- | --- | ---
module.vnet_shared.azurerm_automation_account.this | aa&#8209;sand&#8209;dev | The Azure Automation account used to configure VMs with PowerShell DSC. Configured by */scripts/Set-AutomationAccountConfiguration.ps1*.
module.vnet_shared.azurerm_bastion_host.this | snap&#8209;sand&#8209;dev | The Azure Bastion used for secure RDP/SSH access to sandbox VMs.
module.vnet_shared.azurerm_firewall.this | fw&#8209;sand&#8209;dev | The Azure Firewall used for network security.
module.vnet_shared.azurerm_firewall_policy.this | awfp&#8209;sand&#8209;dev | The firewall policy. Threat intelligence mode is set to `Deny`.
module.vnet_shared.azurerm_firewall_policy_rule_collection_group.this | | The firewall rules. Allows all outbound traffic for ports `80`, `443` and `1688` (Windows Activation).
module.vnet_shared.azurerm_key_vault.this | kv&#8209;sand&#8209;dev | The Azure Key Vault used to store secrets.
module.vnet_shared.azurerm_key_vault_secret.adminpassword | adminpassword | Randomly generated admin password used for sandbox VMs and services.
module.vnet_shared.azurerm_key_vault_secret.adminusername | adminuser | Admin username used for sandbox VMs and services, default is *bootstrapadmin*.
module.vnet_shared.azurerm_key_vault_secret.log_primary_shared_key || The primary shared key for the Log Analytics workspace, used to configure diagnostic settings. The secret name is the same as the workspace id.
module.vnet_shared.azurerm_key_vault_secret.spn_password | | The password for the service principal used for authenticating with Azure. The secret name is the same as the AppID / object id.
module.vnet_shared.azurerm_log_analytics_workspace.this |  log&#8209;sand&#8209;dev&#8209;xxx | The Log Analytics workspace used to collect logs and metrics from Azure resources.
module.vnet_shared.azurerm_monitor_diagnostic_setting.this |  | The Azure Monitor diagnostic setting used to send key vault logs and metrics to the Log Analytics workspace.
module.vnet_shared.azurerm_network_interface.this | nic&#8209;sand&#8209;dev&#8209;adds1 | Nic for *adds1* VM.
module.vnet_shared.azurerm_network_security_group.groups[*] | | NSGs for each subnet except *AzureFirewallSubnet*.
module.vnet_shared.azurerm_network_security_rule.rules[*] | | NSG rules for each NSG. See *locals.tf* for rule definitions.
module.vnet_shared.azurerm_private_dns_a_record.this | | The A record associated with the private endpoint for the key vault.
module.vnet_shared.azurerm_private_dns_zone.this | privatelink.vaultcore.azure.net | The private DNS zone for the key vault.
module.vnet_shared.azurerm_private_dns_zone_virtual_network_link.this | | Links the private DNS zone for key vault to the virtual network.
module.vnet_shared.azurerm_private_endpoint.this | | The private endpoint for the key vault.
module.vnet_shared.azurerm_public_ip.bastion | pip&#8209;sand&#8209;dev&#8209;bastion | Public IP for Azure Bastion.
module.vnet_shared.azurerm_public_ip.firewall | pip&#8209;sand&#8209;dev&#8209;firewall | Public IP for Azure Firewall.
module.vnet_shared.azurerm_role_assignment.roles[*] | | Assigns `Key Vault Secrets Officer` role to the service principal and user for managing key vault secrets.
module.vnet_shared.azurerm_route_table.this | route&#8209;sand&#8209;dev | Configures next hop for default route to go to Azure Firewall for all sandbox subnets.
module.vnet_shared.azurerm_subnet.subnets["AzureBastionSubnet"] | | Dedicated subnet Azure Bastion.
module.vnet_shared.azurerm_subnet.subnets["AzureFirewallSubnet"] | | Dedicated subnet for Azure Firewall.
module.vnet_shared.azurerm_subnet.subnets["snet-adds-01"] | | Dedicated subnet for *adds1* Domain Controller / DNS Server VM.
module.vnet_shared.azurerm_subnet.subnets["snet-misc-01"] | | Reserved for use by optional configurations.
module.vnet_shared.azurerm_subnet.subnets["snet-misc-02"] | | Reserved for use by optional configurations.
module.vnet_shared.azurerm_subnet.subnets["snet-privatelink-02"] | | Dedicated subnet for Private Link.
module.vnet_shared.azurerm_subnet_network_security_group_association.associations[*] | | NSGs are associated with all subnets except *AzureFirewallSubnet*.
module.vnet_shared.azurerm_subnet_route_table_association.associations[*] | | The *route-sand-dev* route table is associated with all subnets except *AzureFirewallSubnet* and *AzureBastionSubnet*.
module.vnet_shared.azurerm_virtual_network.this | vnet&#8209;sand&#8209;dev&#8209;shared   | The shared services virtual network.
module.vnet_shared.azurerm_windows_virtual_machine.this | adds1 | The AD DS Domain Controller / DNS Server VM. Registered with Azure Automation DSC by */scripts/Register-DscNode.ps1* using DSC configuration */scripts/DomainControllerConfiguration.ps1*.

### Output Variables

This section lists the output variables returned by the module.

Output Variable | Default | Description
--- | --- | ---
adds_domain_name | mysandbox.local | The Active Directory Domain Services (AD DS) domain name.
admin_password | | The strong password used for provisioning administrator accounts. Marked sensitive to prevent accidental exposure.
admin_password_secret | adminpassword | The name of the key vault secret where the admin password is stored.
admin_username | bootstrapadmin | The user name for provisioning administrator accounts.
admin_username_secret | adminuser | The name of the key vault secret containing the admin username.
dns_server | 10.1.1.4 | The primary DNS server IP address for the virtual network.
private_dns_zones | | A map of private DNS zones used in the module.
resource_ids | | A map of resource IDs for key resources in the module.
resource_names | | A map of resource names for key resources in the module.
subnets | | A list of subnets in the shared virtual network.
