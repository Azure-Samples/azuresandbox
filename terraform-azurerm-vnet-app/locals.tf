locals {
  commandParamParts = [
    "$params = @{",
    "TenantId = '${var.aad_tenant_id}'; ",
    "SubscriptionId = '${var.subscription_id}'; ",
    "AppId = '${var.arm_client_id}'; ",
    "ResourceGroupName = '${var.resource_group_name}'; ",
    "KeyVaultName = '${var.key_vault_name}'; ",
    "StorageAccountName = '${var.storage_account_name}'; ",
    "Domain = '${var.adds_domain_name}'; ",
    "AdminUsernameSecret = '${var.admin_username_secret}'; ",
    "AdminPwdSecret = '${var.admin_password_secret}' ",
    "}"
  ]

  network_security_group_rules = flatten([
    for subnet_key, subnet in local.subnets : [
      for nsgrule_key in subnet.nsgrules : {
        subnet_name                = subnet_key
        nsgrule_name               = nsgrule_key
        access                     = local.nsgrules[nsgrule_key].access
        destination_address_prefix = local.nsgrules[nsgrule_key].destination_address_prefix
        destination_port_ranges    = local.nsgrules[nsgrule_key].destination_port_ranges
        direction                  = local.nsgrules[nsgrule_key].direction
        priority                   = 100 + (index(subnet.nsgrules, nsgrule_key) * 10)
        protocol                   = local.nsgrules[nsgrule_key].protocol
        source_address_prefix      = local.nsgrules[nsgrule_key].source_address_prefix
        source_port_ranges         = local.nsgrules[nsgrule_key].source_port_ranges
      }
    ]
  ])

  nsgrules = {
    AllowInternetOutbound = {
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["*"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowVirtualNetworkInbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["*"]
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }

    AllowVirtualNetworkOutbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["*"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }
  }

  private_dns_zones = [
    "privatelink.api.azureml.ms",
    "privatelink.azurecr.io",
    "privatelink.blob.core.windows.net",
    "privatelink.cognitiveservices.azure.com",
    "privatelink.database.windows.net",
    "privatelink.documents.azure.com",
    "privatelink.file.core.windows.net",
    "privatelink.mysql.database.azure.com",
    "privatelink.notebooks.azure.net",
    "privatelink.openai.azure.com",
    "privatelink.search.windows.net"
  ]

  storage_account_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${var.storage_account_name}"

  subnets = {
    snet-app-01 = {
      address_prefix                    = var.subnet_application_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall_01"
    }

    snet-appservice-01 = {
      address_prefix                    = var.subnet_appservice_address_prefix
      delegation                        = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall_01"
    }

    snet-db-01 = {
      address_prefix                    = var.subnet_database_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall_01"
    }

    snet-misc-03 = {
      address_prefix                    = var.subnet_misc_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall_01"
    }

    snet-privatelink-01 = {
      address_prefix                    = var.subnet_privatelink_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Enabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound"
      ]
      route_table = "firewall_01"
    }
  }
}

