variable "admin_password_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin password"
}

variable "admin_username_secret" {
  type        = string
  description = "The name of the key vault secret containing the admin username"
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
  description = "The Azure region where the VM will be provisioned"
}

variable "resource_group_name" {
  type        = string
  description = "The existing resource group where the VM will be provisioned"
}

variable "ssh_public_key" {
  type        = string
  description = "The SSH public key used for the admin account"
}

variable "storage_access_tier" {
  type        = string
  description = "The acccess tier for the new storage account."
  default     = "Hot"
}

variable "storage_replication_type" {
  type        = string
  description = "The type of replication for the new storage account."
  default     = "LRS"
}

variable "subnet_id" {
  type        = string
  description = "The existing subnet which will be used by the VM"
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."
}

variable "tags" {
  type        = map(any)
  description = "The ARM tags to be applied to all new resources created."
}

variable "vm_image_offer" {
  type        = string
  description = "The offer type of the virtual machine image used to create the VM"
  default     = "0001-com-ubuntu-server-focal"
}

variable "vm_image_publisher" {
  type        = string
  description = "The publisher for the virtual machine image used to create the VM"
  default     = "Canonical"
}

variable "vm_image_sku" {
  type        = string
  description = "The sku of the virtual machine image used to create the VM"
  default     = "20_04-lts-gen2"
}

variable "vm_image_version" {
  type        = string
  description = "The version of the virtual machine image used to create the VM"
  default     = "Latest"
}

variable "vm_name" {
  type        = string
  description = "The name of the VM"
}

variable "vm_size" {
  type        = string
  description = "The size of the virtual machine"
  default     = "Standard_B2s"
}

variable "vm_storage_account_type" {
  type        = string
  description = "The storage replication type to be used for the VMs OS and data disks"
  default     = "Standard_LRS"
}
