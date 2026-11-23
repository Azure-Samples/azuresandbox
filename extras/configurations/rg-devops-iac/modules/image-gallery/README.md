# Image Gallery Module (image-gallery)

## Contents

* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Overview

This optional module creates an [Azure Compute Gallery](https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery) and [Azure VM Image Builder](https://learn.microsoft.com/azure/virtual-machines/image-builder-overview) (AIB) templates that build patched **custom images** for the Azure Sandbox VMs, so sandbox deployments spend less time installing software and updates. Set the `enable_image_gallery` variable in `rg-devops-iac` to enable this module.

Builds for **custom images** run in pre-configured subnets in `rg-devop-iac`. There are no public IP addresses, and egress is through the NAT gateway. To deploy sandbox VMs from these images, set `vm_image_gallery_id` in the Azure Sandbox `terraform.tfvars` to the gallery's resource ID. See [Custom Images](../../../../../README.md#custom-images).

The module creates:

* A compute gallery with four image definitions: `adds`, `jumpwin`, `jumplinux` and `mssqlwin`.
* One AIB image template per image definition, with in-VM validation that stops a build before anything is published.
* A user-assigned managed identity for AIB with two built-in role assignments.

## Smoke Testing

In the Azure portal, open the `rg-devops-iac` resource group and verify:

* The Azure Compute Gallery has an image definition for each image.
* Each image definition has a matching Azure VM Image Builder template.
* The image builder user-assigned managed identity exists.

After running a build (see [Building Images](#building-images)), verify that each image definition has a new image version.

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Outputs](#outputs)
* [Image Design](#image-design)
* [Image Build Networking](#image-build-networking)
* [Image Builder Identity](#image-builder-identity)
* [Image Build Prerequisites](#image-build-prerequisites)
* [Image Build Costs](#image-build-costs)
* [Building Images](#building-images)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root module (rg-devops-iac): resource group, VNet, and the image build subnets with their NSGs and NAT gateway associations.

The root module also registers the `Microsoft.VirtualMachineImages` resource provider when `enable_image_gallery` is true, because a module can't configure its provider. The azurerm provider's `extended` registration set covers the other providers builds need, including `Microsoft.ContainerInstance`.

### Module Structure

This module is organized as follows:

```plaintext
├── scripts/                              # Build VM and administrator scripts
│   ├── Enable-MicrosoftUpdate.ps1        # PowerShell: opts Windows build VMs into Microsoft Update
│   ├── invoke-image-build.sh             # Bash (administrator): runs image builds and tags new image versions
│   ├── Test-ImageWindows.ps1             # PowerShell: validates the adds, jumpwin and mssqlwin images
│   └── test-image-jumplinux.sh           # Bash: validates the jumplinux image
├── compute.tf                            # Compute gallery, image definitions and image templates
├── locals.tf                             # Local values, including the image definitions and customization steps
├── main.tf                               # Naming, image builder identity and role assignments
├── outputs.tf                            # Output values
├── terraform.tf                          # Terraform configuration block
└── variables.tf                          # Input variables
```

The image templates run the PowerShell and `test-image-jumplinux.sh` scripts on the build VM. Run the administrator script from the rg-devops-iac directory, e.g. `./modules/image-gallery/scripts/invoke-image-build.sh`. It reads the root module's outputs.

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

### Outputs

Name | Description
--- | ---
resource_ids | A map of resource ids for key resources in the module, including `image_definition_<image>` and `image_template_<image>` for each image.
resource_names | A map of resource names for key resources in the module, including `image_definition_<image>` and `image_template_<image>` for each image.

### Image Design

Image | Sandbox VM | Source platform image | Customization
--- | --- | --- | ---
`adds` | `adds1` | `MicrosoftWindowsServer:WindowsServer:2025-datacenter-core-g2` | Microsoft Update opt-in and patching only. AD DS is installed at deploy time, because [Sysprep doesn't support the AD DS role](https://learn.microsoft.com/windows-hardware/manufacture/desktop/sysprep-support-for-server-roles).
`jumpwin` | `jumpwin1` | `MicrosoftWindowsServer:WindowsServer:2025-datacenter-g2` | RSAT, VS Code, SSMS and MySQL Workbench, then Microsoft Update opt-in and patching.
`jumplinux` | `jumplinux1` | `Canonical:ubuntu-24_04-lts:server` | The jumpbox packages and a full `dist-upgrade`.
`mssqlwin` | `mssqlwin1` | `MicrosoftSQLServer:sql2025-ws2025:entdev-gen2` | Microsoft Update opt-in, so SQL Server is patched too, then patching.

* **Image definitions:** Generation 2, generalized, with accelerated networking. Every definition supports the SCSI and NVMe disk controllers and the Standard and Trusted Launch security types, so the images run on the NVMe-only v6 sizes the sandbox VMs use, as Standard or Trusted Launch VMs.
* **Source images:** The templates use the `latest` source platform image version when a build runs. The template tags each image version with `source_image` (publisher:offer:sku), and `scripts/invoke-image-build.sh` adds `source_image_version` and `build_time` after the build.
* **Windows patching:** Every Windows image opts into Microsoft Update, then runs two passes of Windows Update (Critical and Security updates, excluding previews), each followed by a restart. Patching runs after software installs, so updates also cover what was installed.
* **Linux patching:** `jumplinux` installs the jumpbox packages, then runs a full `apt-get dist-upgrade`, so updates also cover what was installed. AIB has no Linux restart customizer, so the build VM isn't restarted. A kernel installed by the upgrade takes effect when a VM is first deployed from the image.
* **Patching after deployment:** Sandbox VMs deployed from these images are patched by the sandbox's Azure Update Manager schedule, the same as VMs from platform images. The images leave Windows automatic updates and Linux `unattended-upgrades` at their defaults, so Azure can turn them off and Update Manager is the only source of updates. See [Patching](../../../../../README.md#patching).
* **Validation:** After AIB captures the image from the build VM, it deploys a validation VM from the captured image and runs the template's validation script on it. AIB publishes the image only if every check passes (`continueDistributeOnFailure = false`).
  * **Windows:**
    * All images: Microsoft Update is registered and all Critical and Security updates are installed.
    * `adds`: the image is patch-only, leaving AD-Domain-Services for installation at deploy time.
    * `jumpwin`: RSAT-ADDS, RSAT-DNS-Server, VS Code, SSMS and MySQL Workbench are installed.
    * `mssqlwin`: SQL Server, pre-installed on the source platform image, is present.
    * The Windows Update policy key is skipped, because Azure sets it from each VM's patch mode at provisioning.
  * **Linux:**
    * All images: all security upgrades are installed.
    * `jumplinux`: the packages in [install-vm-jumpbox-linux-packages.sh](../../../../../modules/vm-jumpbox-linux/scripts/install-vm-jumpbox-linux-packages.sh) are installed, including:
      * DevOps tools: `azure-cli`, `helm`, `jp`, `powershell`, `python3-pip` and `terraform`.
      * Containers: `containerd.io`, `docker-buildx-plugin`, `docker-ce`, `docker-ce-cli`, `docker-compose-plugin` and `notary`.
      * Active Directory integration: `krb5-config`, `krb5-user`, `libnss-winbind`, `libpam-winbind`, `ntp`, `samba` and `winbind`.
      * File shares: `autofs`, `cifs-utils` and `keyutils`.
* **Distribution:** One replica in `location` on `Standard_LRS`, with automatic version numbering.
* **Build VM size:** `image_build_vm_size` defaults to `Standard_D4s_v6`, the same generation as the sandbox VMs.
* **Template updates:** AIB image templates are immutable, so Terraform replaces a template whenever it or a script it runs changes.

### Image Build Networking

Builds use private networking in the `rg-devops-iac` virtual network, with no public IP addresses. AIB puts the build and validation VMs in the image build VM subnet and a Container Instance in the image build Container Instances subnet, which reaches the build VM over the private network. Outbound traffic, such as Windows Update, package repositories and software downloads, uses the NAT gateway. See [Virtual Network Design](../../README.md#virtual-network-design) and [Azure VM Image Builder networking options](https://learn.microsoft.com/azure/virtual-machines/linux/image-builder-vnet).

### Image Builder Identity

The image gallery adds no human personas to the rg-devops-iac [Personas and Role Assignments](../../README.md#personas-and-role-assignments). The **devops administrator** applies the configuration and runs `invoke-image-build.sh`, which `Contributor` covers. The image builder identity is created by this configuration and used only by AIB.

The image templates run as a user-assigned managed identity with the roles below. Each role includes the [permissions AIB needs](https://learn.microsoft.com/azure/virtual-machines/linux/image-builder-permissions-cli) plus some extra permissions, so each is scoped narrowly to limit its reach:

Role | Scope | Used for
--- | --- | ---
[Compute Gallery Artifacts Publisher](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/compute#compute-gallery-artifacts-publisher) | Compute gallery | Publishing image versions to the image definitions.
[Network Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/networking#network-contributor) | Virtual network | Putting the build VM and its Container Instance in the image build subnets.
[Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/privileged#contributor) | Staging resource groups (`IT_<resource group>_*`) \* | Creating the temporary build resources.

\* AIB creates a staging resource group for each template, assigns this role itself and deletes the group with its template. See [Configure Azure VM Image Builder permissions](https://learn.microsoft.com/azure/virtual-machines/linux/image-builder-permissions-cli).

### Image Build Prerequisites

* **Quota:** `scripts/invoke-image-build.sh` starts all four builds at once. Each build runs one Container Instance and up to two `image_build_vm_size` VMs, a build VM and a validation VM. Before building, check that `location` has quota for four Container Instances and eight VMs: 32 vCPUs at the default `Standard_D4s_v6`, in both the VM family's vCPU quota and the Total Regional vCPUs quota. This is burst usage while builds run, not steady state: AIB deletes the build resources when each build finishes.
* **Azure Policy:** See the Azure Policy note in [Other Prerequisites](../../../../../README.md#other-prerequisites). The templates apply `tags` to the staging resource groups and their build resources, so tags you add for policy exemptions also apply to builds.

### Image Build Costs

The gallery, image definitions and templates cost nothing while idle. Each build pays for its build VM, Container Instance and staging storage while it runs, and each image version pays for its replica storage. Delete older versions to keep storage costs down.

### Building Images

Terraform creates the templates but doesn't run builds. Run them as the **devops administrator** (see [Personas and Role Assignments](../../README.md#personas-and-role-assignments)) with Azure CLI from the root module directory after `terraform apply`, using [invoke-image-build.sh](./scripts/invoke-image-build.sh). It reads the `image_template_<image>` names from the root `resource_names` output.

```bash
./modules/image-gallery/scripts/invoke-image-build.sh                     # all four images
./modules/image-gallery/scripts/invoke-image-build.sh jumplinux mssqlwin  # selected images
```

The script starts the builds in parallel, reports their status until they finish, then tags each new image version with `source_image_version` and `build_time`. Builds take from about 30 minutes (`jumplinux`) to a few hours (Windows images with several Windows Update passes). If a build fails, check `customization.log` in the template's staging resource group.

Automating builds and deleting old image versions are outside this configuration.
