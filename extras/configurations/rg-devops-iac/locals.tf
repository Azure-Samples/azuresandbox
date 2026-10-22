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

  # Allow-list of Azure RBAC roles the deployment identity may assign or remove using it's 
  # "Role Based Access Control Administrator" role assignment. Names must match built-in role names exactly. 
  # This set is specific to the Azure Sandbox configuration, grouped by the module that first needs each role. 
  # You can replace it with the roles your configuration assigns.
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

  # ABAC condition on the deployment identity's Role Based Access Control Administrator assignment. It restricts the
  # roles the identity can assign or remove to the allow-list above, so it can't grant privileged roles such as Owner.
  deployment_identity_rbac_condition = join(" AND ", [
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/write'}) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
  ])

  # Numeric ids of the GitHub repository and its owner, used in the OIDC subjects below.
  # Each id comes from its variable (var.github_repository_id, var.github_repository_owner_id) when set.
  # If either is empty, the missing id is looked up from the GitHub API on each plan, using the repository in var.github_runner_url.
  # The lookup is anonymous, so it works only for public repositories; set both variables for a private repository.
  github_repository_lookup   = var.deployment_identity == "oidc" && (var.github_repository_id == "" || var.github_repository_owner_id == "")
  github_repository          = local.github_repository_lookup ? jsondecode(data.http.github_repository[0].response_body) : null
  github_repository_id       = var.github_repository_id != "" ? var.github_repository_id : try(tostring(local.github_repository.id), "")
  github_repository_owner_id = var.github_repository_owner_id != "" ? var.github_repository_owner_id : try(tostring(local.github_repository.owner.id), "")

  # A GitHub OIDC subject identifies which repository and environment a GitHub Actions job runs in.
  # Each subject becomes a federated identity credential so matching jobs can sign in to Azure without a stored secret.
  # The repository must use the subject claim template {"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","context"]}.
  # The template can be set on the repository itself or inherited from its organization.
  # For a job in an environment, "context" is "environment:<name>", so each subject is this prefix followed by the environment name.
  github_oidc_subject_prefix = "repository_owner_id:${local.github_repository_owner_id}:repository_id:${local.github_repository_id}:environment:"

  # The oidc deployment identity accepts one subject for each environment in var.github_oidc_environments.
  github_oidc_subjects = var.deployment_identity == "oidc" ? {
    for environment in var.github_oidc_environments : environment => "${local.github_oidc_subject_prefix}${environment}"
  } : {}

  # The runner power state identity accepts one subject, for var.github_runner_power_state_environment.
  github_runner_power_state_subject = var.deployment_identity == "oidc" ? "${local.github_oidc_subject_prefix}${var.github_runner_power_state_environment}" : null

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
