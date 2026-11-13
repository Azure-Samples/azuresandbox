#region image-gallery
# Optional Azure Compute Gallery for pre-built Azure Sandbox VM images. Image versions are published by the Azure VM
# Image Builder templates below, not by Terraform, so Terraform doesn't track them. Delete every image version before
# removing this module, because a gallery or image definition that still has versions can't be deleted.
resource "azurerm_shared_image_gallery" "this" {
  name                = module.naming_unique.names["gallery"].name
  location            = var.location
  resource_group_name = var.resource_group_name
  description         = "Pre-built Azure Sandbox VM images."
}

# The definition names (adds, jumpwin, jumplinux, mssqlwin) are the contract with the Azure Sandbox configuration.
# Every definition supports both disk controllers and both security types, so the images run on the NVMe-only v6
# sizes the sandbox VMs use, as Standard or Trusted Launch VMs.
resource "azurerm_shared_image" "images" {
  for_each = local.images

  name                                = each.key
  gallery_name                        = azurerm_shared_image_gallery.this.name
  resource_group_name                 = var.resource_group_name
  location                            = var.location
  description                         = each.value.description
  os_type                             = each.value.os_type
  hyper_v_generation                  = "V2"
  accelerated_network_support_enabled = true
  disk_controller_type_nvme_enabled   = true
  trusted_launch_supported            = true

  identifier {
    publisher = "AzureSandbox"
    offer     = each.key
    sku       = "gen2"
  }
}
#endregion

#region image-templates
# One Azure VM Image Builder template per image definition. Builds run only when started (see
# scripts/invoke-image-build.sh). AIB creates a staging resource group (IT_<resource group>_<template>_<id>) for each
# template, and gives the template's identity Contributor on it.
resource "azapi_resource" "image_templates" {
  for_each = local.images

  type      = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  name      = "${module.naming.names["image_template"].name}-${each.key}"
  parent_id = var.resource_group_id
  location  = var.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.image_builder.id]
  }

  body = {
    properties = {
      buildTimeoutInMinutes = each.value.os_type == "Windows" ? 360 : 120
      customize             = each.value.customize

      # Tags the staging resource group and the build resources in it, so tag-based Azure Policy exemptions in var.tags
      # also apply to them.
      managedResourceTags = var.tags

      source = {
        type      = "PlatformImage"
        publisher = each.value.source.publisher
        offer     = each.value.source.offer
        sku       = each.value.source.sku
        version   = "latest"
      }

      validate = {
        continueDistributeOnFailure = false
        sourceValidationOnly        = false
        inVMValidations             = local.image_validations[each.key]
      }

      distribute = [
        {
          type           = "SharedImage"
          galleryImageId = azurerm_shared_image.images[each.key].id
          runOutputName  = each.key

          # The resolved source image version and the build time are added by scripts/invoke-image-build.sh after
          # each build, because they aren't known when the template is defined.
          artifactTags = {
            source_image = "${each.value.source.publisher}:${each.value.source.offer}:${each.value.source.sku}"
          }

          targetRegions = [
            {
              name               = var.location
              replicaCount       = 1
              storageAccountType = "Standard_LRS"
            }
          ]

          versioning = {
            scheme = "Latest"
          }
        }
      ]

      vmProfile = {
        vmSize = var.image_build_vm_size

        vnetConfig = {
          subnetId                  = var.subnet_image_build_id
          containerInstanceSubnetId = var.subnet_image_build_aci_id
        }
      }
    }
  }

  # Image templates can't be updated, so any change to the template, including a change to a script it runs,
  # replaces it.
  replace_triggers_refs = ["properties"]

  depends_on = [time_sleep.wait_for_image_builder_roles]
}
#endregion
