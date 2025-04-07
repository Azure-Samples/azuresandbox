variable "aad_tenant_id" {
  type        = string
  description = "The Microsoft Entra tenant id."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.aad_tenant_id))
    error_message = "The 'aad_tenant_id' must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "adds_domain_name" {
  type        = string
  description = "The AD DS domain name."

  validation {
    condition     = length(var.adds_domain_name) <= 255
    error_message = "The 'adds_domain_name' must be a valid domain name with a maximum length of 255 characters."
  }
}

variable "admin_password_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin password"
  default     = "adminpassword"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,127}$", var.admin_password_secret))
    error_message = "The 'admin_password_secret' must conform to Azure Key Vault secret naming requirements: it can only contain alphanumeric characters and hyphens, and must be between 1 and 127 characters long."
  }
}

variable "admin_username_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin username"
  default     = "adminuser"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,127}$", var.admin_username_secret))
    error_message = "The 'admin_username_secret' must conform to Azure Key Vault secret naming requirements: it can only contain alphanumeric characters and hyphens, and must be between 1 and 127 characters long."
  }
}

variable "arm_client_id" {
  type        = string
  description = "The AppId of the service principal used for authenticating with Azure. Must have a 'Contributor' role assignment."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.arm_client_id))
    error_message = "The 'arm_client_id' must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "arm_client_secret" {
  type        = string
  description = "The password for the service principal used for authenticating with Azure. Set interactively or using an environment variable 'TF_VAR_arm_client_secret'."
  sensitive   = true

  validation {
    condition     = length(var.arm_client_secret) >= 8
    error_message = "The 'arm_client_secret' must be at least 8 characters long."
  }
}

variable "dns_server" {
  type        = string
  description = "The IP address of the DNS server. This should be the first non-reserved IP address in the subnet where the AD DS domain controller is hosted."

  validation {
    condition     = can(regex("^(10\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3}))$|^(172\\.(1[6-9]|2[0-9]|3[0-1])\\.(\\d{1,3})\\.(\\d{1,3}))$|^(192\\.168\\.(\\d{1,3})\\.(\\d{1,3}))$", var.dns_server))
    error_message = "The 'dns_server' must be a valid RFC 1918 private IP address (e.g., 10.x.x.x, 172.16.x.x - 172.31.x.x, or 192.168.x.x)."
  }
}

variable "key_vault_id" {
  type        = string
  description = "The existing key vault where secrets are stored"

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[a-zA-Z0-9-_()]+/providers/Microsoft.KeyVault/vaults/[a-zA-Z0-9-]+$", var.key_vault_id))
    error_message = "The 'key_vault_id' must be a valid Azure Resource ID for a Key Vault. It should follow the format '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.KeyVault/vaults/{keyVaultName}'."
  }
}

variable "key_vault_name" {
  type        = string
  description = "The existing key vault where secrets are stored"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "The 'key_vault_name' must conform to Azure Key Vault naming requirements: it can only contain alphanumeric characters and hyphens, must start with a letter, and must be between 3 and 24 characters long."
  }
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.location))
    error_message = "The 'location' must be a valid Azure region name. It should only contain lowercase letters, numbers, and dashes (e.g., 'eastus', 'westus2', 'centralus')."
  }
}

variable "log_analytics_workspace_retention_days" {
  type        = string
  description = "The retention period for the new log analytics workspace."
  default     = "30"

  validation {
    condition     = can(regex("^(30|31|60|90|120|180|270|365|550|730)$", var.log_analytics_workspace_retention_days))
    error_message = "The 'log_analytics_workspace_retention_days' must be one of the valid retention periods: 30, 31, 60, 90, 120, 180, 270, 365, 550, or 730 days."
  }
}

variable "random_id" {
  type        = string
  description = "A random id used to create unique resource names."

  validation {
    condition     = can(regex("^[a-z0-9]{15}$", var.random_id))
    error_message = "The 'random_id' must be exactly 15 characters long and consist only of lowercase letters and digits (e.g., 'abc123xyz456def')."
  }
}

variable "resource_group_name" {
  type        = string
  description = "The name of the new resource group to be provisioned."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "The 'resource_group_name' must conform to Azure resource group naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), parentheses (()), and hyphens (-), and must be between 1 and 90 characters long."
  }
}

variable "storage_account_name" {
  type        = string
  description = "The name of the shared storage account."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "The 'storage_account_name' must conform to Azure storage account naming requirements: it can only contain lowercase letters and numbers, and must be between 3 and 24 characters long."
  }
}

variable "storage_container_name" {
  type        = string
  description = "The name of the blob storage container where scripts are stored."

  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.storage_container_name))
    error_message = "The 'storage_container_name' must conform to Azure blob storage container naming requirements: it can only contain lowercase letters, numbers, and hyphens, must start and end with a letter or number, and must be between 3 and 63 characters long."
  }
}

variable "subnet_adds_address_prefix" {
  type        = string
  description = "The address prefix for the AD Domain Services subnet."

  validation {
    condition     = can(cidrhost(var.subnet_adds_address_prefix, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "subnet_AzureBastionSubnet_address_prefix" {
  type        = string
  description = "The address prefix for the AzureBastionSubnet subnet."

  validation {
    condition     = can(cidrhost(var.subnet_AzureBastionSubnet_address_prefix, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "subnet_AzureFirewallSubnet_address_prefix" {
  type        = string
  description = "The address prefix for the AzureFirewallSubnet subnet."

  validation {
    condition     = can(cidrhost(var.subnet_AzureFirewallSubnet_address_prefix, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "subnet_misc_address_prefix" {
  type        = string
  description = "The address prefix for the miscellaneous subnet."

  validation {
    condition     = can(cidrhost(var.subnet_misc_address_prefix, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "subnet_misc_02_address_prefix" {
  type        = string
  description = "The address prefix for the miscellaneous 2 subnet."

  validation {
    condition     = can(cidrhost(var.subnet_misc_02_address_prefix, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "The 'subscription_id' must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."

  default = { costcenter = "MyCostCenter", division = "MyDivision", group = "MyGroup" }

  validation {
    condition = alltrue([
      for key, value in var.tags :
      can(regex("^[a-zA-Z0-9._-]{1,512}$", key)) &&
      can(regex("^[a-zA-Z0-9._ -]{0,256}$", value))
    ])
    error_message = "Each tag key must be 1-512 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-). Each tag value must be 0-256 characters long and consist of alphanumeric characters, periods (.), underscores (_), spaces, or hyphens (-)."
  }
}

variable "vm_adds_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the VM"
  default     = "WindowsServer"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_adds_image_offer))
    error_message = "The 'vm_adds_image_offer' must conform to Azure Marketplace image offer naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_adds_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the VM"
  default     = "MicrosoftWindowsServer"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_adds_image_publisher))
    error_message = "The 'vm_adds_image_publisher' must conform to Azure Marketplace image publisher naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_adds_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the VM"
  default     = "2025-datacenter-azure-edition-core"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_adds_image_sku))
    error_message = "The 'vm_adds_image_sku' must conform to Azure Marketplace image SKU naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_adds_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the VM"
  default     = "Latest"

  validation {
    condition     = can(regex("^(Latest|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.vm_adds_image_version))
    error_message = "The 'vm_adds_image_version' must conform to Azure Marketplace image version naming requirements: it must be 'Latest' or in the format 'Major.Minor.Patch' (e.g., '1.0.0')."
  }
}

variable "vm_adds_name" {
  type        = string
  description = "The name of the VM"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,15}$", var.vm_adds_name))
    error_message = "The 'vm_adds_name' must conform to Azure virtual machine naming conventions: it can only contain alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 1 and 15 characters long."
  }
}

variable "vm_adds_size" {
  type        = string
  description = "The size of the virtual machine."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.vm_adds_size))
    error_message = "The 'vm_adds_size' must conform to Azure virtual machine size naming conventions: it can only contain alphanumeric characters and underscores (_). Examples include 'Standard_DS1_v2' or 'Standard_B2ms'."
  }
}

variable "vm_adds_storage_account_type" {
  type        = string
  description = "The storage type to be used for the VM's managed disks."
  default     = "Standard_LRS"

  validation {
    condition = contains(["Standard_LRS", "Premium_LRS", "StandardSSD_LRS", "Premium_ZRS", "StandardSSD_ZRS"], var.vm_adds_storage_account_type)
    error_message = "The 'vm_adds_storage_account_type' must be one of the valid Azure storage SKUs for managed disks: 'Standard_LRS', 'Premium_LRS', 'StandardSSD_LRS', 'Premium_ZRS', or 'StandardSSD_ZRS'."
  }
}

variable "vnet_address_space" {
  type        = string
  description = "The address space in CIDR notation for the new virtual network."

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "vnet_name" {
  type        = string
  description = "The name of the new virtual network to be provisioned."
  default     = "vnet-shared-01"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.vnet_name))
    error_message = "The 'vnet_name' must conform to Azure virtual network naming standards: it can only contain alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 1 and 64 characters long."
  }
}
