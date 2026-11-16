locals {
  # Private DNS zones used by the Azure Monitor Private Link Scope (AMPLS) private endpoint.
  ampls_private_dns_zones = [
    "privatelink.agentsvc.azure-automation.net", # Legacy agent service channel
    "privatelink.monitor.azure.com",             # Global endpoints, AMA configuration (DCE) and ingestion
    "privatelink.ods.opinsights.azure.com",      # Log Analytics data ingestion
    "privatelink.oms.opinsights.azure.com",      # Log Analytics agent onboarding
  ]

  # All private DNS zones in this configuration.
  private_dns_zones = concat(
    local.ampls_private_dns_zones,
    [
      "privatelink.blob.core.windows.net", # Azure Blob Storage (Terraform state)
      "privatelink.vaultcore.azure.net",   # Azure Key Vault
    ]
  )

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

  # The AzureBastionSubnet rules are the complete set required by Azure Bastion.
  # See https://learn.microsoft.com/azure/bastion/bastion-nsg
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

    AllowBastionSshInbound = {
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["22"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = var.subnet_bastion_address_prefix
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

    AllowGetSessionInformationOutbound = {
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["80"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
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

    # Lets the Azure VM Image Builder container reach the build VM over SSH (Linux) and WinRM over HTTPS (Windows).
    AllowImageBuilderInbound = {
      access                     = "Allow"
      destination_address_prefix = var.subnet_image_build_address_prefix
      destination_port_ranges    = ["22", "5986"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = var.subnet_image_build_aci_address_prefix
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

    # Overrides the default AllowVnetInBound rule, so nothing else in the VNet can reach the image build subnets.
    DenyVirtualNetworkInbound = {
      access                     = "Deny"
      destination_address_prefix = "*"
      destination_port_ranges    = ["*"]
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }
  }

  # Each subnet must be inside the VNet and must not overlap another subnet. Two CIDRs overlap when their network
  # addresses match under the shorter of their two prefix lengths.
  subnet_prefixes_valid = {
    for key, subnet in local.subnets : key => (
      tonumber(split("/", subnet.address_prefix)[1]) >= tonumber(split("/", var.vnet_address_space)[1]) &&
      cidrhost("${cidrhost(subnet.address_prefix, 0)}/${split("/", var.vnet_address_space)[1]}", 0) == cidrhost(var.vnet_address_space, 0) &&
      alltrue([
        for other_key, other in local.subnets : (
          cidrhost("${cidrhost(subnet.address_prefix, 0)}/${min(tonumber(split("/", subnet.address_prefix)[1]), tonumber(split("/", other.address_prefix)[1]))}", 0) !=
          cidrhost("${cidrhost(other.address_prefix, 0)}/${min(tonumber(split("/", subnet.address_prefix)[1]), tonumber(split("/", other.address_prefix)[1]))}", 0)
        ) if other_key != key
      ])
    )
  }

  subnets = {
    AzureBastionSubnet = {
      address_prefix                    = var.subnet_bastion_address_prefix
      delegation                        = ""
      nat_gateway                       = false
      private_endpoint_network_policies = "Disabled" # Default

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
    }

    (var.subnet_devops_name) = {
      address_prefix                    = var.subnet_devops_address_prefix
      delegation                        = ""
      nat_gateway                       = true
      private_endpoint_network_policies = "Disabled" # Default

      nsg_rules = [
        "AllowBastionSshInbound"
      ]
    }

    (var.subnet_privatelink_name) = {
      address_prefix                    = var.subnet_privatelink_address_prefix
      delegation                        = ""
      nat_gateway                       = false
      private_endpoint_network_policies = "Disabled" # Do not enforce NSGs for private endpoints.
      nsg_rules                         = []
    }

    # The image build subnets are used by the optional image-gallery module (var.enable_image_gallery). Azure VM Image
    # Builder puts its temporary build VM in the build subnet, and a container in the Container Instances subnet that
    # connects to the build VM. Both reach the internet only through the NAT gateway.
    # See https://learn.microsoft.com/azure/virtual-machines/security-isolated-image-builds-image-builder
    (var.subnet_image_build_name) = {
      address_prefix                    = var.subnet_image_build_address_prefix
      delegation                        = ""
      nat_gateway                       = true
      private_endpoint_network_policies = "Disabled" # Default

      nsg_rules = [
        "AllowImageBuilderInbound",
        "DenyVirtualNetworkInbound"
      ]
    }

    (var.subnet_image_build_aci_name) = {
      address_prefix                    = var.subnet_image_build_aci_address_prefix
      delegation                        = "Microsoft.ContainerInstance/containerGroups"
      nat_gateway                       = true
      private_endpoint_network_policies = "Disabled" # Default

      # The default outbound rules let the container reach the build subnet on 22 and 5986, and the internet through
      # the NAT gateway. Nothing needs to connect to the container.
      nsg_rules = [
        "DenyVirtualNetworkInbound"
      ]
    }
  }
}
