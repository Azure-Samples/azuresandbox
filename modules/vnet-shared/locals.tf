locals {
  admin_password = "${random_string.adminpassword_first_char.result}${random_password.adminpassword_middle_chars.result}${random_string.adminpassword_last_char.result}"

  # Private DNS zones for the entire sandbox environment are created here in the hub virtual
  # network and linked to the hub virtual network only. Spoke virtual networks use the domain
  # controller / DNS server *adds1* in this virtual network as their DNS server, so the
  # recursive lookup is always performed from the hub and a single link per zone is sufficient.
  # See https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/private-link-and-dns-integration-at-scale
  # This list is the authoritative source for the sandbox. When adding a private endpoint in any
  # module, add its zone here rather than creating a zone in the consuming module.
  ampls_private_dns_zones = [
    "privatelink.monitor.azure.com",            # App Insights ingestion + Live Metrics + API; AMA config pull
    "privatelink.oms.opinsights.azure.com",     # Log Analytics agent onboarding / registration
    "privatelink.ods.opinsights.azure.com",     # Log Analytics data ingestion (log writes)
    "privatelink.agentsvc.azure-automation.net" # Legacy agent service channel
  ]

  private_dns_zones = concat(
    local.ampls_private_dns_zones,
    [
      "privatelink.vaultcore.azure.net",                  # Key Vault, vnet-shared module
      "privatelink.azurecr.io",                           # Azure Container Registry, vnet-app module
      "privatelink.blob.core.windows.net",                # Azure Blob Storage, vnet-app module
      "privatelink.file.core.windows.net",                # Azure Files, vnet-app module
      "privatelink.database.windows.net",                 # Azure SQL Database, mssql module
      "privatelink.mysql.database.azure.com",             # Azure Database for MySQL, mysql module
      "privatelink.${var.location}.azurecontainerapps.io" # Azure Container Apps, petstore configuration
    ]
  )
  key_vault_roles = {
    kv_secrets_officer_spn = {
      principal_id         = data.azurerm_client_config.current.object_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Key Vault Secrets Officer"
    }
    kv_secrets_officer_user = {
      principal_id         = var.user_object_id
      principal_type       = "User"
      role_definition_name = "Key Vault Secrets Officer"
    }
  }

  network_security_group_rules = flatten([
    for subnet_key, subnet in local.subnets : [
      for nsg_rule_key in subnet.nsg_rules : {
        subnet_name                = subnet_key
        nsg_rule_name              = nsg_rule_key
        access                     = local.nsg_rules[nsg_rule_key].access
        destination_address_prefix = local.nsg_rules[nsg_rule_key].destination_address_prefix
        destination_port_ranges    = local.nsg_rules[nsg_rule_key].destination_port_ranges
        direction                  = local.nsg_rules[nsg_rule_key].direction
        priority                   = 100 + (index(subnet.nsg_rules, nsg_rule_key) * 10)
        protocol                   = local.nsg_rules[nsg_rule_key].protocol
        source_address_prefix      = local.nsg_rules[nsg_rule_key].source_address_prefix
        source_port_ranges         = local.nsg_rules[nsg_rule_key].source_port_ranges
      }
    ]
  ])

  nsg_rules = {
    AllowAzureCloudOutbound = {
      access                     = "Allow"
      destination_address_prefix = "AzureCloud"
      destination_port_ranges    = ["443"]
      direction                  = "Outbound"
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowAzureLoadBalancerInbound = {
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["443"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = "AzureLoadBalancer"
      source_port_ranges         = ["*"]
    }

    AllowBastionCommunicationInbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["8080", "5701"]
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }

    AllowBastionCommunicationOutbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["8080", "5701"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }

    AllowGetSessionInformationOutbound = {
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["80"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowGatewayManagerInbound = {
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["443"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = "GatewayManager"
      source_port_ranges         = ["*"]
    }

    AllowHttpsInbound = {
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["443"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = "Internet"
      source_port_ranges         = ["*"]
    }

    AllowInternetOutbound = {
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["*"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowSshRdpOutbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["22", "3389"]
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

  subnets = {
    AzureBastionSubnet = {
      address_prefix                    = var.subnet_AzureBastionSubnet_address_prefix
      private_endpoint_network_policies = "Disabled"

      nsg_rules = [
        "AllowHttpsInbound",
        "AllowGatewayManagerInbound",
        "AllowAzureLoadBalancerInbound",
        "AllowBastionCommunicationInbound",
        "AllowSshRdpOutbound",
        "AllowAzureCloudOutbound",
        "AllowBastionCommunicationOutbound",
        "AllowGetSessionInformationOutbound"
      ]

      route_table = null
    }

    snet-adds-01 = {
      address_prefix                    = var.subnet_adds_address_prefix
      private_endpoint_network_policies = "Disabled"

      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]

      route_table = "firewall"
    }

    snet-misc-01 = {
      address_prefix                    = var.subnet_misc_address_prefix
      private_endpoint_network_policies = "Disabled"

      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]

      route_table = "firewall"
    }

    snet-misc-02 = {
      address_prefix                    = var.subnet_misc_02_address_prefix
      private_endpoint_network_policies = "Disabled"

      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]

      route_table = "firewall"
    }

    AzureFirewallSubnet = {
      address_prefix                    = var.subnet_AzureFirewallSubnet_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsg_rules                         = []
      route_table                       = null
    }

    snet-privatelink-01 = {
      address_prefix                    = var.subnet_privatelink_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsg_rules                         = []
      route_table                       = null
    }
  }
}
