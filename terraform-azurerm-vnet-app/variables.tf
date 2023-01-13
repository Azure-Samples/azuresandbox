variable "aad_tenant_id" {
  type        = string
  description = "The Azure Active Directory tenant id."
}

variable "adds_domain_name" {
  type        = string
  description = "The AD DS domain name."
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

variable "remote_virtual_network_id" {
  type        = string
  description = "The id of the existing shared services virtual network that the new spoke virtual network will be peered with."
}

variable "remote_virtual_network_name" {
  type        = string
  description = "The name of the existing shared services virtual network that the new spoke virtual network will be peered with."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."
}

variable "ssh_public_key" {
  type        = string
  description = "The SSH public key used for the admin account"
}

variable "storage_account_name" {
  type        = string
  description = "The name of the shared storage account."
}

variable "storage_share_name" {
  type        = string
  description = "The name of the Azure Files share to be provisioned."
}

variable "storage_share_quota_gb" {
  type        = string
  description = "The storage quota for the Azure Files share to be provisioned in GB."
  default     = "1024"
}

variable "subnet_application_address_prefix" {
  type        = string
  description = "The address prefix for the application subnet."
}

variable "subnet_database_address_prefix" {
  type        = string
  description = "The address prefix for the database subnet."
}

variable "subnet_mysql_address_prefix" {
  type        = string
  description = "The address prefix for the MySQL subnet."
}

variable "subnet_privatelink_address_prefix" {
  type        = string
  description = "The address prefix for the PrivateLink subnet."
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
}

variable "vm_jumpbox_linux_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the VM"
  default     = "0001-com-ubuntu-server-focal"
}

variable "vm_jumpbox_linux_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the VM"
  default     = "Canonical"
}

variable "vm_jumpbox_linux_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the VM"
  default     = "20_04-lts-gen2"
}

variable "vm_jumpbox_linux_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the VM"
  default     = "Latest"
}

variable "vm_jumpbox_linux_name" {
  type        = string
  description = "The name of the VM"
}

variable "vm_jumpbox_linux_size" {
  type        = string
  description = "The size of the virtual machine"
  default     = "Standard_B2s"
}

variable "vm_jumpbox_linux_storage_account_type" {
  type        = string
  description = "The storage replication type to be used for the VMs OS and data disks"
  default     = "Standard_LRS"
}

variable "vm_jumpbox_linux_userdata_file" {
  type        = string
  description = "The name of the cloud-init User-Data file for the virtual machine."
}

variable "vm_jumpbox_win_configure_storage_script" {
  type        = string
  description = "The name of the PowerShell script used to configure Azure Storage for kerberos authentication."
}

variable "vm_jumpbox_win_configure_storage_script_uri" {
  type        = string
  description = "The uri oof the PowerShell script used to configure Azure Storage for kerberos authentication."
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
  default     = "2022-datacenter-g2"
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

variable "vm_jumpbox_win_post_deploy_script" {
  type        = string
  description = "The name of the PowerShell script to be run post-deployment."
}

variable "vm_jumpbox_win_post_deploy_script_uri" {
  type        = string
  description = "The uri of the PowerShell script of the PowerShell script to be run post-deployment."
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
  description = "The address space in CIDR notation for the new application virtual network."
}

variable "vnet_name" {
  type        = string
  description = "The name of the application virtual network."
}
