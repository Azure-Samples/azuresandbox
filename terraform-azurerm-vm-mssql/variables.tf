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

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,127}$", var.admin_password_secret))
    error_message = "The 'admin_password_secret' must conform to Azure Key Vault secret naming requirements: it can only contain alphanumeric characters and hyphens, and must be between 1 and 127 characters long."
  }
}

variable "admin_username_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin username"

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

variable "automation_account_name" {
  type        = string
  description = "The name of the Azure Automation Account used for state configuration (DSC)."

  validation {
    condition     = length(var.automation_account_name) <= 90
    error_message = "The 'automation_account_name' must not exceed 90 characters, which is the maximum length for an Azure resource name."
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

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."

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

  validation {
    condition = alltrue([
      for key, value in var.tags :
      can(regex("^[a-zA-Z0-9._-]{1,512}$", key)) &&
      can(regex("^[a-zA-Z0-9._ -]{0,256}$", value))
    ])
    error_message = "Each tag key must be 1-512 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-). Each tag value must be 0-256 characters long and consist of alphanumeric characters, periods (.), underscores (_), spaces, or hyphens (-)."
  }
}

variable "temp_disk_size_mb" {
  type        = number
  description = "The size of the temporary disk in MB."

  validation {
    condition     = var.temp_disk_size_mb >= 0
    error_message = "The 'temp_disk_size_mb' must be greater than or equal to 0."
  }
}

variable "vm_mssql_win_configure_mssql_script_uri" {
  type        = string
  description = "The uri of the PowerShell script used to configure SQL Server."

  validation {
    condition     = can(regex("^(https?|ftp)://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$", var.vm_mssql_win_configure_mssql_script_uri))
    error_message = "The 'vm_mssql_win_configure_mssql_script_uri' must be a valid URI starting with 'http', 'https', or 'ftp'."
  }
}

variable "vm_mssql_win_data_disk_config" {
  type        = map(any)
  description = "Data disk configuration for SQL Server virtual machine."
  default = {
    sqldata = {
      name         = "vol_sqldata_M",
      disk_size_gb = "128",
      lun          = "0",
      caching      = "ReadOnly"
    },
    sqllog = {
      name         = "vol_sqllog_L",
      disk_size_gb = "32",
      lun          = "1",
      caching      = "None"
    }
  }

  validation {
    condition = alltrue([
      for key, value in var.vm_mssql_win_data_disk_config :
      contains(keys(var.vm_mssql_win_data_disk_config), key) &&
      value.name != "" &&
      tonumber(value.disk_size_gb) > 0 &&
      value.lun >= 0 &&
      contains(["ReadOnly", "None"], value.caching)
    ])
    error_message = "The 'vm_mssql_win_data_disk_config' must be similar to the default configuration. Each disk must have a valid name, a positive disk size, a non-negative LUN, and a valid caching mode ('ReadOnly', 'None', or 'ReadWrite')."
  }
}

variable "vm_mssql_win_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the database server VM"
  default     = "sql2022-ws2022"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_mssql_win_image_offer))
    error_message = "The 'vm_mssql_win_image_offer' must conform to Azure Marketplace image offer naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_mssql_win_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the database server VM"
  default     = "MicrosoftSQLServer"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_mssql_win_image_publisher))
    error_message = "The 'vm_mssql_win_image_publisher' must conform to Azure Marketplace image publisher naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_mssql_win_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the database server VM"
  default     = "sqldev-gen2"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,64}$", var.vm_mssql_win_image_sku))
    error_message = "The 'vm_mssql_win_image_sku' must conform to Azure Marketplace image SKU naming requirements: it can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must be between 1 and 64 characters long."
  }
}

variable "vm_mssql_win_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the database server VM"
  default     = "Latest"

  validation {
    condition     = can(regex("^(Latest|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.vm_mssql_win_image_version))
    error_message = "The 'vm_mssql_win_image_version' must conform to Azure Marketplace image version naming requirements: it must be 'Latest' or in the format 'Major.Minor.Patch' (e.g., '1.0.0')."
  }
}

variable "vm_mssql_win_name" {
  type        = string
  description = "The name of the database server VM"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,15}$", var.vm_mssql_win_name))
    error_message = "The 'vm_mssql_win_name' must conform to Azure virtual machine naming conventions: it can only contain alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 1 and 15 characters long."
  }
}

variable "vm_mssql_win_post_deploy_script" {
  type        = string
  description = "The name of the PowerShell script to be run post-deployment."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+\\.ps1$", var.vm_mssql_win_post_deploy_script))
    error_message = "The 'vm_mssql_win_post_deploy_script' must be a valid PowerShell script file name. It can only contain alphanumeric characters, periods (.), underscores (_), and hyphens (-), and must end with the '.ps1' extension."
  }
}

variable "vm_mssql_win_post_deploy_script_uri" {
  type        = string
  description = "The uri of the PowerShell script to be run post-deployment."

  validation {
    condition     = can(regex("^(https?|ftp)://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$", var.vm_mssql_win_post_deploy_script_uri))
    error_message = "The 'vm_mssql_win_post_deploy_script_uri' must be a valid URI starting with 'http', 'https', or 'ftp'."
  }
}

variable "vm_mssql_win_size" {
  type        = string
  description = "The size of the virtual machine"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.vm_mssql_win_size))
    error_message = "The 'vm_mssql_win_size' must conform to Azure virtual machine size naming conventions: it can only contain alphanumeric characters and underscores (_). Examples include 'Standard_DS1_v2' or 'Standard_B2ms'."
  }
}

variable "vm_mssql_win_storage_account_type" {
  type        = string
  description = "The storage type to be used for the VMs OS disk"
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Standard_LRS", "Premium_LRS", "StandardSSD_LRS", "Premium_ZRS", "StandardSSD_ZRS"], var.vm_mssql_win_storage_account_type)
    error_message = "The 'vm_mssql_win_storage_account_type' must be one of the valid Azure storage SKUs for managed disks: 'Standard_LRS', 'Premium_LRS', 'StandardSSD_LRS', 'Premium_ZRS', or 'StandardSSD_ZRS'."
  }
}

variable "vm_mssql_win_sql_startup_script_uri" {
  type        = string
  description = "The URI for the SQL Startup Powershell script."

  validation {
    condition     = can(regex("^(https?|ftp)://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$", var.vm_mssql_win_sql_startup_script_uri))
    error_message = "The 'vm_mssql_win_sql_startup_script_uri' must be a valid URI starting with 'http', 'https', or 'ftp'."
  }
}

variable "vnet_app_01_subnets" {
  type        = map(any)
  description = "The existing subnets defined in the application virtual network."
}
