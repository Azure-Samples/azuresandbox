variable "admin_username" {
  type        = string
  description = "The administrator username for the virtual machine"
  default     = "devopsbootstrapadmin"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{1,64}$", var.admin_username))
    error_message = "Must conform to Azure VM admin username requirements: it can only contain alphanumeric characters and must be between 1 and 64 characters long."
  }
}

variable "admin_username_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin username"
  default     = "adminuser"
}

variable "data_collection_endpoint_id" {
  type        = string
  description = "The ID of the data collection endpoint (DCE) to associate with the virtual machine."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[a-zA-Z0-9._()-]+/providers/Microsoft.Insights/dataCollectionEndpoints/[a-zA-Z0-9-]+$", var.data_collection_endpoint_id))
    error_message = "Must be a valid Azure Data Collection Endpoint resource ID in the format '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Insights/dataCollectionEndpoints/{dceName}'."
  }
}

variable "data_collection_rule_linux_id" {
  type        = string
  description = "The ID of the Linux data collection rule (DCR) to associate with the virtual machine."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[a-zA-Z0-9._()-]+/providers/Microsoft.Insights/dataCollectionRules/[a-zA-Z0-9-]+$", var.data_collection_rule_linux_id))
    error_message = "Must be a valid Azure Data Collection Rule resource ID in the format '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Insights/dataCollectionRules/{dcrName}'."
  }
}

variable "enable_github_runner" {
  type        = bool
  description = "Set to true to install and register the GitHub Actions self-hosted runner agent on the VM, false to skip it."
  default     = false
}

variable "github_runner_labels" {
  type        = list(string)
  description = "Additional labels to apply to the GitHub Actions self-hosted runner. Only used when var.enable_github_runner is true."
  default     = ["azuresandbox"]

  validation {
    condition     = alltrue([for label in var.github_runner_labels : can(regex("^[a-zA-Z0-9._-]{1,64}$", label))])
    error_message = "Each label must be 1-64 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-)."
  }
}

variable "github_runner_token" {
  type        = string
  description = "The GitHub runner registration token used to register the self-hosted runner (expires after 1 hour). Ephemeral: delivered to the VM through a write-only Run Command protected parameter and never stored in Terraform state or the saved plan. Required only when the runner is registered (when the Run Command is created or var.github_runner_token_version changes)."
  sensitive   = true
  ephemeral   = true
  default     = ""
}

# Controls when the ephemeral github_runner_token is sent to the VM. Terraform can't store an ephemeral value
# to detect changes, so the Run Command's write-only sensitive_body_version tracks this number instead: the
# token is sent when the Run Command is created (including when the VM is replaced, which then needs a fresh
# token) and whenever this value changes, and is omitted otherwise. Leave it at 1 in normal use. Increment it
# only to retry a failed registration with a new token, e.g. after the token expired before the Run Command ran.
variable "github_runner_token_version" {
  type        = number
  description = "Increment to send a new var.github_runner_token to the VM and re-run runner registration, e.g. after a failed registration. The token is sent only when the Run Command is created or this value changes."
  default     = 1
}

variable "github_runner_url" {
  type        = string
  description = "The GitHub repository URL to register the self-hosted runner with, e.g. 'https://github.com/myorg/myrepo'. Required when var.enable_github_runner is true."
  default     = ""

  validation {
    condition     = var.github_runner_url == "" || can(regex("^https://github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_runner_url))
    error_message = "Must be empty or a GitHub repository URL, e.g. 'https://github.com/myorg/myrepo'."
  }
}

variable "github_runner_version" {
  type        = string
  description = "The version of the GitHub Actions runner agent to install, without the leading 'v'. Only used when var.enable_github_runner is true."
  default     = "2.338.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.github_runner_version))
    error_message = "Must be a semantic version in the format 'Major.Minor.Patch' (e.g., '2.338.0')."
  }
}

variable "key_vault_id" {
  type        = string
  description = "The existing key vault where secrets are stored"

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[a-zA-Z0-9-_()]+/providers/Microsoft.KeyVault/vaults/[a-zA-Z0-9-]+$", var.key_vault_id))
    error_message = "Must be a valid Azure Resource ID for a Key Vault. It should follow the format '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.KeyVault/vaults/{keyVaultName}'."
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

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "Must conform to Azure resource group naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), parentheses (()), and hyphens (-), and must be between 1 and 90 characters long."
  }
}

variable "ssh_private_key_version" {
  type        = number
  description = "Increment to create new ssh_private_key."
  default     = 1
}

variable "storage_account_id" {
  type        = string
  description = "The ID of the existing storage account with the blob storage container to be used for Terraform state files."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[a-zA-Z0-9-_()]+/providers/Microsoft.Storage/storageAccounts/[a-zA-Z0-9]{3,24}$", var.storage_account_id))
    error_message = "Must be a valid Azure Resource ID for a storage account. It should follow the format '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Storage/storageAccounts/{storageAccountName}'."
  }
}

variable "subnet_id" {
  type        = string
  description = "The ID of the existing subnet where the nic will be provisioned."

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[a-zA-Z0-9-_()]+/providers/Microsoft.Network/virtualNetworks/[a-zA-Z0-9-_()]+/subnets/[a-zA-Z0-9-_()]+$", var.subnet_id))
    error_message = "Must be a valid Azure Resource ID for a subnet. It should follow the format '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/virtualNetworks/{vnetName}/subnets/{subnetName}'."
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

variable "user_assigned_identity_ids" {
  type        = list(string)
  description = "The resource ids of user-assigned managed identities to attach to the virtual machine in addition to its system-assigned identity, which remains the default identity on the VM."
  default     = []
}

variable "vm_jumpbox_linux_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the VM"
  default     = "ubuntu-24_04-lts"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_jumpbox_linux_image_offer))
    error_message = "Must conform to Azure Marketplace image offer naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_jumpbox_linux_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the VM"
  default     = "Canonical"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_jumpbox_linux_image_publisher))
    error_message = "Must conform to Azure Marketplace image publisher naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_jumpbox_linux_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the VM"
  default     = "server"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_jumpbox_linux_image_sku))
    error_message = "Must conform to Azure Marketplace image SKU naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_jumpbox_linux_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the VM"
  default     = "Latest"

  validation {
    condition     = can(regex("^(Latest|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.vm_jumpbox_linux_image_version))
    error_message = "Must conform to Azure Marketplace image version naming requirements: it must be 'Latest' or in the format 'Major.Minor.Patch' (e.g., '1.0.0')."
  }
}

variable "vm_jumpbox_linux_name" {
  type        = string
  description = "The name of the VM"
  default     = "jumplinux2"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,15}$", var.vm_jumpbox_linux_name))
    error_message = "Must conform to Azure virtual machine naming conventions: it can only contain alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 1 and 15 characters long."
  }
}

variable "vm_jumpbox_linux_size" {
  type        = string
  description = "The size of the virtual machine"
  # default     = "Standard_B2ls_v2"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.vm_jumpbox_linux_size))
    error_message = "The 'vm_jumpbox_linux_size' must conform to Azure virtual machine size naming conventions: it can only contain alphanumeric characters and underscores (_). Examples include 'Standard_DS1_v2' or 'Standard_B2ms'."
  }
}

variable "vm_jumpbox_linux_storage_account_type" {
  type        = string
  description = "The storage type to be used for the VM's OS disk. Standard HDD (Standard_LRS) is not permitted because Azure is retiring Standard HDD OS disks on September 8, 2028."
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Premium_LRS", "StandardSSD_LRS", "Premium_ZRS", "StandardSSD_ZRS"], var.vm_jumpbox_linux_storage_account_type)
    error_message = "The 'vm_jumpbox_linux_storage_account_type' must be one of the valid Azure storage SKUs for OS disks: 'Premium_LRS', 'StandardSSD_LRS', 'Premium_ZRS', or 'StandardSSD_ZRS'. Standard HDD (Standard_LRS) is not permitted for OS disks."
  }
}
