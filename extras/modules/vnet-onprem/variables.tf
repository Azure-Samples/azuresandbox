variable "aad_tenant_id" {
  type        = string
  description = "The Microsoft Entra tenant id."
}

variable "adds_domain_name" {
  type        = string
  description = "The AD DS domain name."
}

variable "adds_domain_name_cloud" {
  type        = string
  description = "The AD DS domain name for the cloud network."
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

variable "automation_account_name" {
  type        = string
  description = "The name of the Azure Automation Account use for state configuration (DSC)."
}

variable "dns_server" {
  type        = string
  description = "The IP address of the DNS server. This should be the first non-reserved IP address in the subnet where the AD DS domain controller is hosted."
}

variable "dns_server_cloud" {
  type = string
  description = "The IP address of the cloud DNS server."
}

variable "key_vault_id" {
  type        = string
  description = "The existing key vault where secrets are stored"
}

variable "key_vault_name" {
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

variable "subnet_adds_address_prefix" {
  type        = string
  description = "The address prefix for the AD Domain Services subnet."
}

variable "subnet_GatewaySubnet_address_prefix" {
  type        = string
  description = "The address prefix for the GatewaySubnet subnet."
}

variable "subnet_misc_address_prefix" {
  type        = string
  description = "The address prefix for the miscellaneous subnet."
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
}

variable "vm_adds_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the VM"
  default     = "WindowsServer"
}

variable "vm_adds_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the VM"
  default     = "MicrosoftWindowsServer"
}

variable "vm_adds_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the VM"
  default     = "2025-datacenter-azure-edition-core"
}

variable "vm_adds_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the VM"
  default     = "Latest"
}

variable "vm_adds_name" {
  type        = string
  description = "The name of the VM"
}

variable "vm_adds_size" {
  type        = string
  description = "The size of the virtual machine."
  default     = "Standard_B2s"
}

variable "vm_adds_storage_account_type" {
  type        = string
  description = "The storage replication type to be used for the VMs OS and data disks."
  default     = "Standard_LRS"
}

variable "vm_jumpbox_win_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the VM"
  default     = "WindowsServer"
}

variable "vm_jumpbox_win_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the VM"
  default     = "MicrosoftWindowsServer"
}

variable "vm_jumpbox_win_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the VM"
  default     = "2025-datacenter-azure-edition"
}

variable "vm_jumpbox_win_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the VM"
  default     = "Latest"
}

variable "vm_jumpbox_win_name" {
  type        = string
  description = "The name of the VM"
}

variable "vm_jumpbox_win_size" {
  type        = string
  description = "The size of the virtual machine."
  default     = "Standard_B2s"
}

variable "vm_jumpbox_win_storage_account_type" {
  type        = string
  description = "The storage replication type to be used for the VMs OS and data disks."
  default     = "Standard_LRS"
}

variable "vnet_address_space" {
  type        = string
  description = "The address space in CIDR notation for the new virtual network."
}

variable "vnet_asn" {
  type        = string
  description = "The ASN for the on premises network."
  default     = "65123"
}

variable "vnet_name" {
  type        = string
  description = "The name of the new virtual network to be provisioned."
  default     = "vnet-onprem-01"
}

variable "vnet_app_01_id" {
  type        = string
  description = "The id of the application virtual network."
}

variable "vnet_app_01_name" {
  type        = string
  description = "The name of the application virtual network."
}

variable "vnet_shared_01_id" {
  type        = string
  description = "The id of the shared services virtual network."
}

variable "vnet_shared_01_name" {
  type        = string
  description = "The name of the shared services virtual network."
}

variable "vnet_shared_01_subnets" {
  type        = map(any)
  description = "The existing subnets defined in the shared services virtual network."
}

variable "vwan_01_hub_01_id" {
  type        = string
  description = "The id of the virtual wan hub."
}

variable "vwan_01_id" {
  type        = string
  description = "The id of the virtual wan."
}
