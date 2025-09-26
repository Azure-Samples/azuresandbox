locals {
  local_scripts = {
    configure_automation = {
      name = "Set-AutomationAccountConfiguration.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "AutomationAccountName = '${var.automation_account_name}';",
        "VmJumpboxWinName = '${var.vm_jumpbox_win_name}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${var.arm_client_secret}';"
      ]
    }

    provisioner_vm_windows = {
      name = "Register-DscNode.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "Location = '${var.location}';",
        "AutomationAccountName = '${var.automation_account_name}';",
        "VirtualMachineName = '${var.vm_jumpbox_win_name}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${var.arm_client_secret}';",
        "DscConfigurationName = 'JumpBoxConfiguration'"
      ]
    }
  }

  remote_scripts = {
    orchestrator = {
      name = "Invoke-AzureFilesConfiguration.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "KeyVaultName = '${var.key_vault_name}';",
        "StorageAccountName = '${azurerm_storage_account.this.name}';",
        "Domain = '${var.adds_domain_name}';",
        "AdminUsernameSecret = '${var.admin_username_secret}';",
        "AdminPwdSecret = '${var.admin_password_secret}'"
      ]
    }
    worker = {
      name       = "Set-AzureFilesConfiguration.ps1"
      parameters = null
    }
  }

  storage_roles = {
    blob_contributor_spn = {
      principal_id         = data.azurerm_client_config.current.object_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Storage Blob Data Contributor"
    }
    blob_contributor_user = {
      principal_id         = var.user_object_id
      principal_type       = "User"
      role_definition_name = "Storage Blob Data Contributor"
    }
    file_contributor_spn = {
      principal_id         = data.azurerm_client_config.current.object_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Storage File Data Privileged Contributor"
    }
    file_contributor_user = {
      principal_id         = var.user_object_id
      principal_type       = "User"
      role_definition_name = "Storage File Data Privileged Contributor"
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
    "privatelink.search.windows.net",
    "privatelink.services.ai.azure.com"
  ]

  subnets = {
    snet-app-01 = {
      address_prefix                    = var.subnet_application_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall"
    }

    snet-appservice-01 = {
      address_prefix                    = var.subnet_appservice_address_prefix
      delegation                        = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Disabled"
      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall"
    }

    snet-containerapps-01 = {
      address_prefix                    = var.subnet_containerapps_address_prefix
      delegation                        = "Microsoft.App/environments"
      private_endpoint_network_policies = "Disabled"
      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall"
    }

    snet-db-01 = {
      address_prefix                    = var.subnet_database_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall"
    }

    snet-misc-03 = {
      address_prefix                    = var.subnet_misc_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsg_rules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall"
    }

    snet-privatelink-01 = {
      address_prefix                    = var.subnet_privatelink_address_prefix
      delegation                        = ""
      private_endpoint_network_policies = "Disabled"
      nsg_rules                         = []
      route_table                       = null
    }
  }

  vm_win_roles = {
    kv_secrets_user_vm_win = {
      principal_id         = azurerm_windows_virtual_machine.this.identity[0].principal_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Key Vault Secrets User"
      scope                = var.key_vault_id
    }
    st_blob_reader_vm_win = {
      principal_id         = azurerm_windows_virtual_machine.this.identity[0].principal_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Storage Blob Data Reader"
      scope                = azurerm_storage_account.this.id
    }
  }
}
