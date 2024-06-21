variable "aad_tenant_id" {
  type        = string
  description = "The Azure Active Directory tenant id."
}

variable "admin_password_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin password"
}

variable "admin_username_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin username"
}

variable "arm_client_id" {
  type        = string
  description = "The AppId of the service principal used for authenticating with Azure. Must have a 'Contributor' role assignment."
}

variable "arm_client_secret" {
  type        = string
  description = "The password for the service principal used for authenticating with Azure. Set interactively or using an environment variable 'TF_VAR_arm_client_secret'."
  sensitive   = true
}

variable "automation_account_id" {
  type        = string
  description = "The resource id of the Azure Automation Account used for state configuration (DSC)."
}

variable "key_vault_id" {
  type        = string
  description = "The existing key vault where secrets are stored"
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."
}

variable "storage_account_name" {
  type = string
  description = "The name of the storage account where scripts are stored."
}

variable "storage_container_name" {
  type = string
  description = "The name of the storage container where scripts are stored."
  
}
variable "subnet_id" {
  type        = string
  description = "The id of the subnet used for virtual machine nics."
}
variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
}

variable "vm_devops_win_config_script" {
  type        = string
  description = "The name of the configuration script for the devops agent VMs."
}

variable "vm_devops_win_dsc_config" {
  type        = string
  description = "The name of the DSC configuration to apply to the devops agent VMs"
}

variable "vm_devops_win_data_disk_size_gb" {
  type        = number
  description = "The size of the virtual machine data disk in GB"  
}

variable "vm_devops_win_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the database server VM"
  default     = "WindowsServer"
}

variable "vm_devops_win_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the database server VM"
  default     = "MicrosoftWindowsServer"
}

variable "vm_devops_win_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the database server VM"
  default     = "2022-datacenter-g2"
}

variable "vm_devops_win_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the database server VM"
  default     = "Latest"
}

variable "vm_devops_win_instances" {
  type        = number
  description = "The nunber of devops agent VMs to provision."
}

variable "vm_devops_win_instances_start" {
  type        = number
  description = "The first sequence nunber of devops agent VMs to provision."
}

variable "vm_devops_win_license_type" {
  type        = string
  description = "The license type for the virtual machine."
}

variable "vm_devops_win_name" {
  type        = string
  description = "The name of the devops agent VM."
}

variable "vm_devops_win_os_disk_size_gb" {
  type        = number
  description = "The size of the virtual machine OS disk in GB"
}

variable "vm_devops_win_patch_mode" {
  type        = string
  description = "The patch mode for the virtual machine"
}

variable "vm_devops_win_size" {
  type        = string
  description = "The size of the virtual machine"
  default     = "Standard_B2s"
}

variable "vm_devops_win_storage_account_type" {
  type        = string
  description = "The storage replication type to be used for the VMs OS disk"
  default     = "StandardSSD_LRS"
}
