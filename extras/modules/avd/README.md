# Azure Virtual Desktop Module (avd)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![avd-diagram](./images/avd-diagram.drawio.svg)

## Overview

This module deploys Azure Virtual Desktop (AVD) with both personal desktop and RemoteApp configurations. It creates a single shared workspace with two host pools and application groups. The personal desktop host pool provides full Windows desktop access (max 2 sessions), while the RemoteApp host pool streams individual applications like Microsoft Edge (max 10 sessions).

## Smoke Testing

* From the client environment, launch the [Windows App](https://apps.microsoft.com/detail/9N1F85V9T8BN?hl=en-us&gl=US&ocid=pdpshare)
* Sign in as the Azure CLI signed in user
* Connect to the sample desktop, then disconnect
* Connect to the sample Microsoft Edge RemoteApp, then disconnect

## Documentation

Additional information about this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root
* vnet-shared
* vnet-app (subnets)

Additional requirements:

* Azure AD user/group object IDs for role assignments

### Module Structure

```plaintext
├── compute.tf      # Virtual machines and extensions for both host pools
├── locals.tf       # Local values (role IDs, RDP properties)
├── main.tf         # AVD control plane resources (workspaces, host pools, app groups)
├── network.tf      # Network interfaces for session hosts
├── outputs.tf      # Module outputs
├── terraform.tf    # Terraform configuration block
└── variables.tf    # Input variables
```

### Input Variables

Variable | Default | Description
--- | --- | ---
admin_password | | Administrator password for session host VMs (sensitive).
admin_username | | Administrator username for session host VMs.
configuration_zip_url | Microsoft Gallery URL | URL to DSC configuration ZIP file for AVD agent installation.
location | | Azure region where resources will be created.
resource_group_id | | Resource ID of the existing resource group.
resource_group_name | | Name of the existing resource group.
security_principal_object_ids | | Azure AD object IDs for role assignments.
subnet_id | | Resource ID of existing subnet for session hosts.
tags | | Map of resource tags.
unique_seed | | Seed value for Azure naming module.
vm_image_sku | win11-24h2-avd-m365 | Marketplace image SKU for session host VMs.
vm_name_personal | sessionhost1 | Name of the personal desktop session host virtual machine.
vm_name_remoteapp | sessionhost2 | Name of the RemoteApp session host virtual machine.
vm_size | Standard_D4ds_v4 | Azure VM size for session host VMs.

### Module Resources

Address | Name | Notes
--- | --- | ---
azurerm_network_interface.personal | nic-sand-dev-sessionhost1 | Nic for sessionhost1 VM
azurerm_network_interface.remoteapp | nic-sand-dev-sessionhost2 | Nic for sessionhost2 VM
azurerm_role_assignment.personal | | Grants access to personal app group
azurerm_role_assignment.remoteapp | | Grants access to remoteapp app group
azurerm_role_assignment.vm_users | | Grants sign in privileges to session host VMs
azurerm_virtual_desktop_application.edge | | Publishes Microsoft Edge for use with RemoteApp
azurerm_virtual_desktop_application_group.personal | vdag-sand-dev-u28d-personal | Application group for personal desktops
azurerm_virtual_desktop_application_group.remoteapp | vdag-sand-dev-u28d-remoteapp | Application group for remote apps
azurerm_virtual_desktop_host_pool.personal | vdpool-sand-dev-u28d-personal | Host pool for personal desktops
azurerm_virtual_desktop_host_pool.remoteapp | vdpool-sand-dev-u28d-remoteapp | Host pool for remote apps
azurerm_virtual_desktop_host_pool_registration_info.personal | | Registration token with 2 hour expiration
azurerm_virtual_desktop_host_pool_registration_info.remoteapp | | Registration token with 2 hour expiration
azurerm_virtual_desktop_workspace.this | vdws-sand-dev-u28d | Azure virtual desktop workspace
azurerm_virtual_desktop_workspace_application_group_association.personal | | Associates the personal desktop app group with the workspace
azurerm_virtual_desktop_workspace_application_group_association.remoteapp | | Associates the RemoteApp app group with the workspace
azurerm_virtual_machine_extension.aad_login_personal | | Joins personal desktop host pool VMs to Entra ID
azurerm_virtual_machine_extension.aad_login_remoteapp | | Joins RemoteApp host pool VMs to Entra ID
azurerm_virtual_machine_extension.dsc_personal | | Configures personal desktop host pool VMs
azurerm_virtual_machine_extension.dsc_remoteapp | | Configures RemoteApp host pool VMs
azurerm_virtual_machine_extension.guest_attestation_personal | | Enables trusted launch functionality for personal desktop host pool VMs
azurerm_virtual_machine_extension.guest_attestation_remoteapp | | Enables trusted launch functionality for RemoteApp host pool VMs
azurerm_windows_virtual_machine.personal | | Personal desktop host pool VM
azurerm_windows_virtual_machine.remoteapp | | RemoteApp host pool VM

### Output Variables

Name | Description
--- | ---
resource_ids | Map of AVD resource IDs including the shared workspace, personal and RemoteApp host pools, application groups, and both session host VMs.
resource_names | Map of AVD resource names including the shared workspace, personal and RemoteApp host pools, application groups, and both session host VMs.
