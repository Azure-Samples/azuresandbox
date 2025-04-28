# Shared Services Virtual Network Module (`vnet-shared`)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Videos](#videos)

## Architecture

![vnet-shared-diagram](./images/vnet-shared-diagram.drawio.svg)

## Overview

This module implements a virtual network with shared services used by all the configurations including ([Step-By-Step Video](https://youtu.be/tYSnlPy-oJc)):

* An [automation account](https://learn.microsoft.com/azure/automation/automation-intro) for configuration management.
* A [virtual network](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm).
* A [bastion](https://learn.microsoft.com/azure/bastion/bastion-overview) for secure RDP and SSH access to virtual machines.
* A [firewall](https://learn.microsoft.com/en-us/azure/firewall/overview) for network security.
* A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) running [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) with a pre-configured domain and DNS server.

## Smoke testing

* Explore your newly provisioned resources in the Azure portal ([Step-By-Step Video](https://youtu.be/gxO9oKoitQ0)).
  * Key vault
    * Navigate to *portal.azure.com* > *Key vaults* > *kv-sand-dev-xxxxxxxx* > *Objects* > *Secrets* > *adminpassword* > *CURRENT VERSION* > *00000000-0000-0000-0000-000000000000* > *Show Secret Value*
    * Make a note of the *Secret value*. This is a strong password associated with the *adminuser* key vault secret. Together these credentials are used to set up initial administrative access to resources in Azure Sandbox.
  * Bastion host
    * Navigate to *portal.azure.com* > *Bastions* > *snap-sand-dev*.
    * Review the information in the *Overview* section.
* Verify *adds1* node configuration is compliant.
  * From the client environment, navigate to *portal.azure.com* > *Automation Accounts* > *aa-sand-dev* > *Configuration Management* > *State configuration (DSC)*.
  * Refresh the data on the *Nodes* tab and verify that all nodes are compliant.
  * Review the data in the *Configurations* and *Compiled configurations* tabs as well.

## Documentation

This section provides additional information on various aspects of this module.

* [Module Structure](#module-structure)
* [Variable Defaults](#variable-defaults)
* [Module Resources](#module-resources)

### Module Structure

The `vnet-shared` module is organized as follows:

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

### Variable Defaults

This section documents default values for module variables as defined in `variables.tf`.

Variable | Default | Description
--- | --- | ---
adds_domain_name | mysandbox.local | The AD DS domain name.
admin_password_secret | adminpassword | The name of the key vault secret containing the admin password.
admin_username | bootstrapadmin | The name of the key vault secret containing the admin username.
admin_username_secret | adminuser | The name of the key vault secret containing the admin username.
subnet_adds_address_prefix | `10.1.1.0/24` | The address prefix for the AD Domain Services subnet.
subnet_AzureBastionSubnet_address_prefix | `10.1.0.0/27` | The address prefix for the AzureBastionSubnet subnet.
subnet_AzureFirewallSubnet_address_prefix | `10.1.4.0/26` | The address prefix for the AzureFirewallSubnet subnet.
subnet_misc_address_prefix | `10.1.2.0/24` | The address prefix for the miscellaneous subnet.
subnet_misc_02_address_prefix | `10.1.3.0/24` | The address prefix for the miscellaneous 2 subnet.
vm_adds_image_offer | `WindowsServer` | The offer type of the virtual machine image used to create the VM.
vm_adds_image_publisher | `MicrosoftWindowsServer` | The publisher for the virtual machine image used to create the VM.
vm_adds_image_sku | `2025-datacenter-azure-edition-core` | The SKU of the virtual machine image used to create the VM.
vm_adds_image_version | `Latest` | The version of the virtual machine image used to create the VM.
vm_adds_name | adds1 | The name of the VM.
vm_adds_size | `Standard_B2ls_v2` | The size of the virtual machine.
vm_adds_storage_account_type | `Standard_LRS` | The storage type to be used for the VM's managed disks.
vnet_address_space | `10.1.0.0/16` | The address space in CIDR notation for the new virtual network.
vnet_name | shared | The name of the new virtual network to be provisioned.

### Module Resources

Address | Name | Notes
--- | --- | ---
module.vnet_shared.azurerm_automation_account.this | aa&#8209;sand&#8209;dev | The Azure Automation account used to configure VMs with PowerShell DSC. Configured by `./scripts/Set-AutomationAccountConfiguration.ps1`.
module.vnet_shared.azurerm_bastion_host.this | snap&#8209;sand&#8209;dev | The Bastion host used for secure RDP/SSH access to sandbox VMs.
module.vnet_shared.azurerm_firewall.this | fw&#8209;sand&#8209;dev | The Azure Firewall used for secure internet egress.
module.vnet_shared.azurerm_firewall_policy.this | awfp&#8209;sand&#8209;dev | Threat intelligence mode is set to `Deny`.
module.vnet_shared.azurerm_firewall_policy_rule_collection_group.this | | Allows all outbound traffic for ports `80`, `443` and `1688` (Windows Activation).
module.vnet_shared.azurerm_key_vault_secret.adminpassword | | Randomly generated admin password used for sandbox VMs and services.
module.vnet_shared.azurerm_key_vault_secret.adminusername | | Admin username used for sandbox VMs and services, default is `bootstrapadmin`.
module.vnet_shared.azurerm_network_interface.this | nic&#8209;sand&#8209;dev&#8209;adds1 | Nic for `adds1` VM.
module.vnet_shared.azurerm_network_security_group.groups[*] | | NSGs for each subnet except `AzureFirewallSubnet`.
module.vnet_shared.azurerm_network_security_rule.rules[*] | | NSG rules for each NSG. See `locals.tf` for rule definitions.
module.vnet_shared.azurerm_public_ip.bastion | pip&#8209;sand&#8209;dev&#8209;bastion | Public IP for Bastion host.
module.vnet_shared.azurerm_public_ip.firewall | pip&#8209;sand&#8209;dev&#8209;firewall | Public IP for Azure Firewall.
module.vnet_shared.azurerm_route_table.this | route&#8209;sand&#8209;dev | Configures next hop for default route to go to Azure Firewall for all sandbox subnets.
module.vnet_shared.azurerm_subnet.subnets["AzureBastionSubnet"] | | Dedicated subnet for Bastion host.
module.vnet_shared.azurerm_subnet.subnets["AzureFirewallSubnet"] | | Dedicated subnet for Azure Firewall.
module.vnet_shared.azurerm_subnet.subnets["snet-adds-01"] | | Dedicated subnet for `adds1` Domain Controller / DNS Server VM.
module.vnet_shared.azurerm_subnet.subnets["snet-misc-01"] | | Reserved for use by optional configurations.
module.vnet_shared.azurerm_subnet.subnets["snet-misc-02"] | | Reserved for use by optional configurations.
module.vnet_shared.azurerm_subnet_network_security_group_association.associations[*] | | NSGs are associated with all subnets except `AzureFirewallSubnet`.
module.vnet_shared.azurerm_subnet_route_table_association.associations[*] | | The `route-sand-dev` route table is associated with all subnets except `AzureFirewallSubnet` and `AzureBastionSubnet`.
module.vnet_shared.azurerm_virtual_network.this | vnet&#8209;sand&#8209;dev&#8209;shared   | The shared services virtual network.
module.vnet_shared.azurerm_windows_virtual_machine.this | adds1 | The AD DS Domain Controller / DNS Server VM. Registered with Azure Automation DSC by `./scripts/Register-DscNode.ps1` using DSC configuration `./scripts/DomainControllerConfiguration.ps1`.

## Videos

Video | Section
--- |---
[Shared services virtual network (Part 1)](https://youtu.be/tYSnlPy-oJc) | [Overview](#overview)
[Shared services virtual network (Part 4)](https://youtu.be/gxO9oKoitQ0) | [Smoke testing](#smoke-testing)
