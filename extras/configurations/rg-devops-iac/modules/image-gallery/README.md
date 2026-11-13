# Image Gallery Module (image-gallery)

## Contents

* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Overview

This optional module creates an [Azure Compute Gallery](https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery) and [Azure VM Image Builder](https://learn.microsoft.com/azure/virtual-machines/image-builder-overview) (AIB) templates that pre-build fully patched images for the Azure Sandbox VMs, so sandbox deployments spend less time installing software and updates. The root module creates it when `enable_image_gallery` is true. Builds run in the root module's image build subnets with no public IP addresses, and reach the internet through the root module's NAT gateway. Like the other root subnets, the image build subnets exist whether or not this module is enabled. Deploying sandbox VMs from these images is a separate change to the Azure Sandbox configuration.

The module creates:

* A compute gallery with four image definitions: `adds`, `jumpwin`, `jumplinux` and `mssqlwin`.
* One AIB image template per image definition, with in-VM validation that stops a build before anything is published.
* A user-assigned managed identity for AIB with two built-in role assignments.

## Smoke Testing

See [Building Images](#building-images) for how to run builds.

Use this checklist to validate changes to the image gallery or templates:

1. With `enable_image_gallery = false`, `terraform apply` creates the image build subnets but no `module.image_gallery` resources.
2. With `enable_image_gallery = true`, `terraform apply` succeeds.
3. `./modules/image-gallery/scripts/invoke-image-build.sh` builds all four images, validation passes, and each image definition has a new version tagged with `source_image`, `source_image_version` and `build_time`.
4. No public IP address is created in the staging resource groups during a build.
5. A test VM deployed from each image on a v6 size (Standard and, for `mssqlwin`, Trusted Launch) has the expected software and patches.

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)
* [Image Design](#image-design)
* [Image Build Networking](#image-build-networking)
* [Image Builder Identity](#image-builder-identity)
* [Image Build Prerequisites](#image-build-prerequisites)
* [Image Build Costs](#image-build-costs)
* [Building Images](#building-images)
* [Disabling the Image Gallery](#disabling-the-image-gallery)
* [Deleting the rg-devops-iac Resource Group](#deleting-the-rg-devops-iac-resource-group)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root module (rg-devops-iac): resource group, VNet, and the image build subnets with their NSGs and NAT gateway associations.

The root module also registers the `Microsoft.VirtualMachineImages` resource provider when `enable_image_gallery` is true, because a module can't configure its provider.

### Module Structure

This module is organized as follows:

```plaintext
├── scripts/                              # Build VM and operator scripts
│   ├── Enable-MicrosoftUpdate.ps1        # PowerShell: opts the mssqlwin build VM into Microsoft Update
│   ├── invoke-image-build.sh             # Bash (operator): runs image builds and tags new image versions
│   ├── Set-AutomaticUpdates.ps1          # PowerShell: sets Configure Automatic Updates to 4 (jumpwin and mssqlwin)
│   ├── Test-ImageWindows.ps1             # PowerShell: validates the adds, jumpwin and mssqlwin images
│   └── test-image-jumplinux.sh           # Bash: validates the jumplinux image
├── compute.tf                            # Compute gallery, image definitions and image templates
├── locals.tf                             # Local values, including the image definitions and customization steps
├── main.tf                               # Naming, image builder identity and role assignments
├── outputs.tf                            # Output variables
├── terraform.tf                          # Terraform configuration block
└── variables.tf                          # Input variables
```

The image templates run the PowerShell and `test-image-jumplinux.sh` scripts on the build VM. Run the operator script from the rg-devops-iac directory, e.g. `./modules/image-gallery/scripts/invoke-image-build.sh`. It reads the root module's outputs.

The image templates also run the install scripts the Azure Sandbox modules run at deploy time, so both stay identical: [Install-WindowsFeatures.ps1](../../../../../modules/vnet-app/scripts/Install-WindowsFeatures.ps1), [Install-Software.ps1](../../../../../modules/vnet-app/scripts/Install-Software.ps1) and [install-vm-jumpbox-linux-packages.sh](../../../../../modules/vm-jumpbox-linux/scripts/install-vm-jumpbox-linux-packages.sh).

### Input Variables

This section lists the input variables used in this module. All of them are set by the root module.

Variable | Default | Description
--- | --- | ---
image_build_vm_size | | The size of the temporary build VM AIB uses for every build. See [Image Design](#image-design).
location | | The Azure region where the resources will be created.
resource_group_id | | The id of the resource group. The parent of the image templates.
resource_group_name | | The name of the resource group.
subnet_image_build_aci_id | | The id of the root module's image build Container Instances subnet.
subnet_image_build_id | | The id of the root module's image build VM subnet.
tags | | The tags from the root module.
unique_seed | | A seed from the root module's naming module, used for the gallery name.
virtual_network_id | | The id of the VNet. The scope of the image builder Network Contributor role assignment.

### Module Resources

Address | Name | Notes
--- | --- | ---
module.image_gallery[0].azapi_resource.image_templates[*] | itdevopsdev-adds, itdevopsdev-jumpwin, itdevopsdev-jumplinux, itdevopsdev-mssqlwin | One AIB image template per image definition. See [Image Design](#image-design).
module.image_gallery[0].azurerm_role_assignment.image_builder | | Assigns `Compute Gallery Artifacts Publisher` on the gallery to the image builder identity. See [Image Builder Identity](#image-builder-identity).
module.image_gallery[0].azurerm_role_assignment.image_builder_network | | Assigns `Network Contributor` on the virtual network to the image builder identity.
module.image_gallery[0].azurerm_shared_image.images[*] | adds, jumpwin, jumplinux, mssqlwin | Image definitions. These names are the contract with the Azure Sandbox configuration.
module.image_gallery[0].azurerm_shared_image_gallery.this | galdevopsdevxxxxxxxx | Azure Compute Gallery.
module.image_gallery[0].azurerm_user_assigned_identity.image_builder | id-devops-dev-image-builder | Identity the image templates run as.
module.image_gallery[0].time_sleep.wait_for_image_builder_roles | | Waits for the image builder role assignments to propagate before the image templates are created.

### Output Variables

Name | Description
--- | ---
resource_ids | A map of resource ids for key resources in the module, including `image_definition_<image>` and `image_template_<image>` for each image.
resource_names | A map of resource names for key resources in the module, including `image_definition_<image>` and `image_template_<image>` for each image.

### Image Design

Image | Sandbox VM | Source platform image | Customization
--- | --- | --- | ---
`adds` | `adds1` | `MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition-core` | Patching only. AD DS is installed at deploy time, because [Sysprep doesn't support the AD DS role](https://learn.microsoft.com/windows-hardware/manufacture/desktop/sysprep-support-for-server-roles).
`jumpwin` | `jumpwin1` | `MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition` | RSAT, VS Code, SSMS and MySQL Workbench, then patching and Configure Automatic Updates.
`jumplinux` | `jumplinux1` | `Canonical:ubuntu-24_04-lts:server` | The jumpbox packages and a full `dist-upgrade`.
`mssqlwin` | `mssqlwin1` | `MicrosoftSQLServer:sql2025-ws2025:entdev-gen2` | Microsoft Update opt-in, so SQL Server is patched too, then patching and Configure Automatic Updates.

* **Image definitions:** Generation 2, generalized, with accelerated networking. Every definition supports the SCSI and NVMe disk controllers and the Standard and Trusted Launch security types, so the images run on the NVMe-only v6 sizes the sandbox VMs use, as Standard or Trusted Launch VMs.
* **Source images:** The templates use the `latest` source image version when a build runs. The template tags each image version with `source_image` (publisher:offer:sku), and `scripts/invoke-image-build.sh` adds `source_image_version` and `build_time` after the build.
* **Windows patching:** Two passes of Windows Update (Critical and Security updates, excluding previews), each followed by a restart. Patching runs after software installs, so updates also cover what was installed.
* **Configure Automatic Updates:** `jumpwin` and `mssqlwin` set `AUOptions = 4` (auto download and schedule the install) as their last step, because VMs deployed from custom images use `patch_mode = "AutomaticByOS"`, since [automatic VM guest patching doesn't support custom images](https://learn.microsoft.com/azure/update-manager/manage-updates-customized-images). `adds` leaves it alone; `adds1` sets it at deploy time.
* **Linux restart:** AIB has no Linux restart customizer, so `jumplinux` isn't restarted during the build. A kernel installed by the upgrade takes effect when a VM is first deployed from the image.
* **Validation:** Each template runs a validation script on the build VM after customization. A failed check stops the build before anything is published (`continueDistributeOnFailure = false`).
  * Windows: no pending Critical or Security updates; for `adds`, AD-Domain-Services isn't installed; for `jumpwin`, RSAT-ADDS and RSAT-DNS-Server are installed and VS Code, SSMS and MySQL Workbench are present; for `mssqlwin`, the SQL Server service and binaries are present; for `jumpwin` and `mssqlwin`, Configure Automatic Updates is 4.
  * Linux: every package from the install script is installed, `az`, `docker`, `helm`, `pwsh` and `terraform` are on the PATH, and no security upgrades are pending.
* **Distribution:** One replica in `location` on `Standard_LRS`, with automatic version numbering.
* **Build VM size:** `image_build_vm_size` defaults to `Standard_D4s_v6`, the same generation as the sandbox VMs. If AIB can't build on a v6 size in your region or subscription, set it to an older generation, e.g. `Standard_D4s_v5`. The build VM size doesn't affect the image or the sizes VMs deployed from it can use.
* **Template updates:** AIB image templates can't be updated, so any change to a template, including a change to a script it runs, makes Terraform replace it.

### Image Build Networking

Builds run in the root module's virtual network with no public IP addresses. The root module creates these subnets, their NSGs and their NAT gateway associations, whether or not this module is enabled. See [Virtual Network Design](../../README.md#virtual-network-design). AIB puts the build VM in the image build VM subnet, and an [Azure Container Instance](https://learn.microsoft.com/azure/virtual-machines/linux/image-builder-vnet) in the Container Instances subnet that reaches the build VM over the private network. Both subnets reach the internet through the NAT gateway, for platform images, Windows Update, package repositories and AIB.

### Image Builder Identity

The image templates run as a user-assigned managed identity with two built-in roles. Each covers the [permissions AIB needs](https://learn.microsoft.com/azure/virtual-machines/linux/image-builder-permissions-cli) but grants more, so each is scoped to a single resource:

Role | Scope | Used for
--- | --- | ---
[Compute Gallery Artifacts Publisher](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/compute#compute-gallery-artifacts-publisher) | Compute gallery | Publishing image versions to the image definitions.
[Network Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/networking#network-contributor) | Virtual network | Putting the build VM and its Container Instance in the image build subnets.

AIB creates a staging resource group (`IT_<resource group>_<template>_<id>`) for each template, and gives the identity `Contributor` on it for the temporary build resources. The staging resource group is deleted with its template. See [Configure Azure VM Image Builder permissions](https://learn.microsoft.com/azure/virtual-machines/linux/image-builder-permissions-cli).

### Image Build Prerequisites

* **Container Instances quota:** Each build runs one Container Instance in the subscription. Check the Container Instances quota in `location` if you run several builds at once.
* **Build VM quota:** Each build runs one `image_build_vm_size` VM. Check the vCPU quota for its family in `location`.
* **Azure Policy:** Policies that apply to the staging resource groups, e.g. required tags or denied public IPs, can block builds. Builds don't create public IPs. The templates apply `tags` to the staging resource groups and the build resources in them, so add any tags your policies use for exemptions to `tags`.
* **Resource providers:** The configuration registers `Microsoft.VirtualMachineImages`, and the azurerm provider's `extended` registration set covers the others builds need, including `Microsoft.ContainerInstance`.

### Image Build Costs

The gallery, image definitions and templates cost nothing while idle. Each build pays for its build VM, Container Instance and staging storage while it runs, and each image version pays for its replica storage. Delete older versions to keep storage costs down.

### Building Images

Terraform creates the templates but doesn't run builds. Run them as the operator with Azure CLI from the root module directory after `terraform apply`, using [invoke-image-build.sh](./scripts/invoke-image-build.sh). It reads the `image_template_<image>` names from the root `resource_names` output.

```bash
./modules/image-gallery/scripts/invoke-image-build.sh                     # all four images
./modules/image-gallery/scripts/invoke-image-build.sh jumplinux mssqlwin  # selected images
```

The script starts the builds in parallel, reports their status until they finish, then tags each new image version with `source_image_version` and `build_time`. Builds take from about 30 minutes (`jumplinux`) to a few hours (Windows images with several Windows Update passes). If a build fails, check `customization.log` in the template's staging resource group.

Automating builds and deleting old image versions are outside this configuration.

### Disabling the Image Gallery

A gallery or image definition that still has image versions can't be deleted. Before setting `enable_image_gallery` to false, delete every image version from the root module directory:

```bash
RG=$(terraform output -json resource_names | jq -r .resource_group)
GALLERY=$(terraform output -json resource_names | jq -r .image_gallery)
for image in adds jumpwin jumplinux mssqlwin; do
  for version in $(az sig image-version list -g "$RG" -r "$GALLERY" -i "$image" --query "[].name" -o tsv); do
    az sig image-version delete -g "$RG" -r "$GALLERY" -i "$image" -e "$version"
  done
done
```

Then apply with `enable_image_gallery = false`. Deleting each image template also deletes its `IT_*` staging resource group.

### Deleting the rg-devops-iac Resource Group

If you deprovision rg-devops-iac by deleting its resource group (`az group delete`) instead of `terraform destroy`, the image templates' `IT_*` staging resource groups are left behind. They're outside the rg-devops-iac resource group and are only cleaned up when their template is deleted. Delete them too:

```bash
RG=<rg-devops-iac resource group>
az group list --query "[?starts_with(name, 'IT_${RG}_')].name" -o tsv |
  xargs -r -n1 az group delete --yes --no-wait -n
```

Don't delete a staging resource group while its template still exists. The template keeps its build artifacts there, and AIB doesn't recreate it, so later builds of that image can fail. To recover, recreate the template from the root module directory, e.g. `terraform apply -replace='module.image_gallery[0].azapi_resource.image_templates["jumpwin"]'`.
