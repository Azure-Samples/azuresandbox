locals {
  # Private DNS zones used by the Azure Monitor Private Link Scope (AMPLS) private endpoint.
  ampls_private_dns_zones = [
    "privatelink.agentsvc.azure-automation.net", # Legacy agent service channel
    "privatelink.monitor.azure.com",             # Global endpoints, AMA configuration (DCE) and ingestion
    "privatelink.ods.opinsights.azure.com",      # Log Analytics data ingestion
    "privatelink.oms.opinsights.azure.com",      # Log Analytics agent onboarding
  ]

  # All private DNS zones in this configuration, each linked to the devops virtual network. When adding a private
  # endpoint, add its zone here.
  private_dns_zones = concat(
    local.ampls_private_dns_zones,
    [
      "privatelink.blob.core.windows.net", # Azure Blob Storage (Terraform state)
      "privatelink.vaultcore.azure.net",   # Azure Key Vault
    ]
  )

  # Roles the sandbox assigns, grouped by module. Each role is listed once, under the first module that needs it.
  # Keep in sync with the ROLES list in the Azure Sandbox README's Service Principal commands.
  deployment_identity_assignable_roles = [
    # vnet_shared
    "Key Vault Secrets Officer",

    # vnet_app
    "Key Vault Secrets User",
    "Monitoring Reader",
    "Storage Account Contributor",
    "Storage Blob Data Contributor",
    "Storage Blob Data Reader",
    "Storage File Data Privileged Contributor",

    # vm_jumpbox_linux, vm_mssql_win, mssql, mysql, vwan: no additional roles

    # avd (extra module)
    "Desktop Virtualization User",
    "Virtual Machine User Login",

    # petstore (extra module)
    "AcrPull",
    "AcrPush",
    "Monitoring Metrics Publisher",

    # vnet_onprem (extra module): no additional roles
  ]

  deployment_identity_role_ids = join(", ", [
    for role in local.deployment_identity_assignable_roles : data.azurerm_role_definition.deployment_identity_assignable[role].role_definition_id
  ])

  # The identity can create (write) or remove (delete) a role assignment only if the role is in the list above.
  # This prevents it from assigning highly privileged roles such as Owner, User Access Administrator or
  # Role Based Access Control Administrator. Keep in sync with the CONDITION in the Azure Sandbox README's Service Principal commands.
  deployment_identity_rbac_condition = join(" AND ", [
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/write'}) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
  ])

  # GitHub OIDC subjects accepted by the oidc deployment identity, keyed by environment. They match the subject claim
  # template {"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","context"]}, which the
  # repository gets from its organization's template or its own. For a job in an environment, "context" is
  # "environment:<name>". The ids come from the variables when set, otherwise from the GitHub API.
  github_repository_lookup   = var.deployment_identity == "oidc" && (var.github_repository_id == "" || var.github_repository_owner_id == "")
  github_repository          = local.github_repository_lookup ? jsondecode(data.http.github_repository[0].response_body) : null
  github_repository_id       = var.github_repository_id != "" ? var.github_repository_id : try(tostring(local.github_repository.id), "")
  github_repository_owner_id = var.github_repository_owner_id != "" ? var.github_repository_owner_id : try(tostring(local.github_repository.owner.id), "")

  github_oidc_subjects = var.deployment_identity == "oidc" ? {
    for environment in var.github_oidc_environments :
    environment => "repository_owner_id:${local.github_repository_owner_id}:repository_id:${local.github_repository_id}:environment:${environment}"
  } : {}

  # GitHub OIDC subject accepted by the runner power state identity, in the same format.
  github_runner_power_state_subject = var.deployment_identity == "oidc" ? "repository_owner_id:${local.github_repository_owner_id}:repository_id:${local.github_repository_id}:environment:${var.github_runner_power_state_environment}" : null

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

    AllowSshRdpOutbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["22", "3389"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }
  }

  subnets = {
    AzureBastionSubnet = {
      address_prefix                    = var.subnet_bastion_address_prefix
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
    }

    (var.subnet_devops_name) = {
      address_prefix                    = var.subnet_address_prefix
      private_endpoint_network_policies = "Disabled"

      nsg_rules = [
        "AllowBastionSshInbound"
      ]
    }

    (var.subnet_privatelink_name) = {
      address_prefix                    = var.subnet_privatelink_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsg_rules                         = []
    }
  }
}
