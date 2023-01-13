variable "aad_tenant_id" {
  type        = string
  description = "The Azure Active Directory tenant id."
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

variable "client_address_pool" {
  type        = string
  description = "The client address pool for the point to site VPN gateway."
}

variable "dns_server" {
  type        = string
  description = "The IP address for the DNS server."
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group."
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."

  # default = { costcenter = "MyCostCenter", division = "MyDivision", group = "MyGroup" }
}

variable "virtual_networks" {
  type        = map(any)
  description = "The virtual networks to be connected to the vwan hub."

  # default = { MyHubVNetId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroupName/providers/Microsoft.Network/virtualNetworks/MyHubVNetName", MySpokeVnetId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroupName/providers/Microsoft.Network/virtualNetworks/MySpokeVNetName" } 
}

variable "vwan_hub_address_prefix" {
  type        = string
  description = "The address prefix in CIDR notation for the new spoke virtual wan hub."
}
