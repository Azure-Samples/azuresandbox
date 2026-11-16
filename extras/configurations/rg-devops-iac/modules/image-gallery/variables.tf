variable "image_build_vm_size" {
  type        = string
  description = "The size of the temporary build VM that Azure VM Image Builder uses for every image build. This is independent of the size of the VMs later deployed from the images."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.image_build_vm_size))
    error_message = "Must conform to Azure virtual machine size naming conventions: it can only contain alphanumeric characters and underscores (_), e.g. 'Standard_D4s_v6'."
  }
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.location))
    error_message = "Must be a valid Azure region name. It should only contain lowercase letters, numbers, and dashes."
  }
}

variable "resource_group_id" {
  type        = string
  description = "The id of the existing resource group for provisioning resources. Used as the parent of the image templates."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "Must be a valid Azure resource id."
  }
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "Must conform to Azure resource group naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), parentheses (()), and hyphens (-), and must be between 1 and 90 characters long."
  }
}

variable "subnet_image_build_aci_id" {
  type        = string
  description = "The id of the subnet for the Azure VM Image Builder container, delegated to Microsoft.ContainerInstance/containerGroups."

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_image_build_aci_id))
    error_message = "Must be a valid Azure subnet resource id."
  }
}

variable "subnet_image_build_id" {
  type        = string
  description = "The id of the subnet for the temporary Azure VM Image Builder build VMs."

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_image_build_id))
    error_message = "Must be a valid Azure subnet resource id."
  }
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."

  validation {
    condition = alltrue([
      for key, value in var.tags :
      can(regex("^[a-zA-Z0-9._-]{1,512}$", key)) &&
      can(regex("^[a-zA-Z0-9._ -]{0,256}$", value))
    ])
    error_message = "Each tag key must be 1-512 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-). Each tag value must be 0-256 characters long and consist of alphanumeric characters, periods (.), underscores (_), spaces, or hyphens (-)."
  }
}

variable "unique_seed" {
  type        = string
  description = "A unique seed to be used for generating unique names for resources. This should be a string that is unique to the environment or deployment."

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.unique_seed))
    error_message = "Must only contain alphanumeric characters and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "virtual_network_id" {
  type        = string
  description = "The id of the existing VNet for the image build subnets. Used as the scope of the image builder Network Contributor role assignment."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+$", var.virtual_network_id))
    error_message = "Must be a valid Azure resource id."
  }
}
