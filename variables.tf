variable "aad_tenant_id" {
  type        = string
  description = "The Microsoft Entra tenant id."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.aad_tenant_id))
    error_message = "Must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged over the base tags map."
  default     = {}
}

variable "arm_client_id" {
  type        = string
  description = "The AppId of the service principal used for authenticating with Azure. Must have an 'Owner' role assignment."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.arm_client_id))
    error_message = "Must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "arm_client_secret" {
  type        = string
  description = "The password for the service principal used for authenticating with Azure. Set interactively or using an environment variable 'TF_VAR_arm_client_secret'."
  sensitive   = true

  validation {
    condition     = length(var.arm_client_secret) >= 8
    error_message = "Must be at least 8 characters long."
  }
}

variable "enable_module_avd" {
  type        = bool
  description = "Set to true to enable the Azure Virtual Desktop (AVD) module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_avd || var.enable_module_vnet_app
    error_message = "enable_module_vnet_app must be true when enable_module_avd is true because the avd module references resources from the vnet_app module."
  }
}


variable "enable_module_mssql" {
  type        = bool
  description = "Set to true to enable the Azure SQL Database (mssql) module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_mssql || var.enable_module_vnet_app
    error_message = "enable_module_vnet_app must be true when enable_module_mssql is true because the mssql module references resources from the vnet_app module."
  }
}

variable "enable_module_mysql" {
  type        = bool
  description = "Set to true to enable the Azure Database for MySQL (mysql) module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_mysql || var.enable_module_vnet_app
    error_message = "enable_module_vnet_app must be true when enable_module_mysql is true because the mysql module references resources from the vnet_app module."
  }
}

variable "enable_module_petstore" {
  type        = bool
  description = "Set to true to enable the petstore module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_petstore || var.enable_module_vnet_app
    error_message = "enable_module_vnet_app must be true when enable_module_petstore is true because the petstore module references resources from the vnet_app module."
  }
}

variable "enable_module_vm_jumpbox_linux" {
  type        = bool
  description = "Set to true to enable the vm_jumpbox_linux module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_vm_jumpbox_linux || var.enable_module_vnet_app
    error_message = "enable_module_vnet_app must be true when enable_module_vm_jumpbox_linux is true because the vm_jumpbox_linux module references resources from the vnet_app module."
  }
}

variable "enable_module_vm_mssql_win" {
  type        = bool
  description = "Set to true to enable the vm_mssql_win module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_vm_mssql_win || var.enable_module_vnet_app
    error_message = "enable_module_vnet_app must be true when enable_module_vm_mssql_win is true because the vm_mssql_win module references resources from the vnet_app module."
  }
}

variable "enable_module_vnet_app" {
  type        = bool
  description = "Set to true to enable the vnet_app module, false to skip it."
  default     = false
}

variable "enable_module_vnet_onprem" {
  type        = bool
  description = "Set to true to enable the vnet_onprem module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_vnet_onprem || (var.enable_module_vnet_app && var.enable_module_vwan)
    error_message = "enable_module_vnet_app and enable_module_vwan must both be true when enable_module_vnet_onprem is true because the vnet_onprem module references resources from both."
  }
}

variable "enable_module_vwan" {
  type        = bool
  description = "Set to true to enable the vwan module, false to skip it."
  default     = false

  validation {
    condition     = !var.enable_module_vwan || var.enable_module_vnet_app
    error_message = "enable_module_vnet_app must be true when enable_module_vwan is true because the vwan module references resources from the vnet_app module."
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

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
  default     = { costcenter = "mycostcenter", environment = "dev", project = "sand" }

  validation {
    condition = alltrue([
      for key, value in var.tags :
      can(regex("^[a-zA-Z0-9._-]{1,512}$", key)) &&
      can(regex("^[a-zA-Z0-9._ -]{0,256}$", value))
    ])
    error_message = "Each tag key must be 1-512 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-). Each tag value must be 0-256 characters long and consist of alphanumeric characters, periods (.), underscores (_), spaces, or hyphens (-)."
  }
}

# tflint-ignore: terraform_unused_declarations # Public input consumed by bootstrap tooling and validated here; not referenced by a resource.
variable "user_name" {
  type        = string
  description = "The user name of the user in Microsoft Entra ID."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*[a-zA-Z0-9]@[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.user_name))
    error_message = "Must be a valid User Principal Name (UPN) format like 'user@domain.com'. The username part must start and end with alphanumeric characters and can contain periods (.), underscores (_), or hyphens (-). The domain must be a valid domain name."
  }
}

variable "user_object_id" {
  type        = string
  description = "The object id of the user in Microsoft Entra ID."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.user_object_id))
    error_message = "Must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "vm_jumpbox_size" {
  type        = string
  description = "The size of the jumpbox and domain controller virtual machines: 'jumpwin1', 'jumplinux1', and 'adds1'."
  default     = "Standard_D2ls_v6"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.vm_jumpbox_size))
    error_message = "The 'vm_jumpbox_size' must conform to Azure virtual machine size naming conventions: it can only contain alphanumeric characters and underscores (_). Examples include 'Standard_DS1_v2' or 'Standard_B2ms'."
  }
}

variable "vm_mssql_win_size" {
  type        = string
  description = "The size of the database server virtual machine 'mssqlwin1'. Must be a Diskful Ddsv6 (general purpose) or Edsv6 (memory optimized) size with local NVMe temp disks and a minimum of 4 vCPUs."
  default     = "Standard_D4ds_v6" # use az-vm list-skus to determine if this size is available in your region

  validation {
    condition     = can(regex("^Standard_(D|E)[0-9]+ds_v6$", var.vm_mssql_win_size))
    error_message = "The 'vm_mssql_win_size' must be a Ddsv6 or Edsv6 Diskful size matching the pattern 'Standard_(D|E)<vCPU>ds_v6' (e.g. 'Standard_D4ds_v6', 'Standard_D8ds_v6', 'Standard_E4ds_v6', 'Standard_E16ds_v6'). Other Azure VM sizes are not currently supported by this module."
  }
}
