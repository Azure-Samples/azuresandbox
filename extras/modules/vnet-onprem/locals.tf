locals {
  subnets = {
    GatewaySubnet = {
      address_prefix = var.subnet_GatewaySubnet_address_prefix
    }

    snet-adds-02 = {
      address_prefix = var.subnet_adds_address_prefix
    }

    snet-misc-04 = {
      address_prefix = var.subnet_misc_address_prefix
    }
  }

  local_scripts = {
    provisioner_vm_adds = {
      name = "Register-DscNode.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "Location = '${var.location}';",
        "AutomationAccountName = '${var.automation_account_name}';",
        "VmAddsName = '${var.vm_adds_name}';",
        "VmJumpboxWinName = '${var.vm_jumpbox_win_name}';",
        "AdminUsername = '${data.azurerm_key_vault_secret.adminuser.value}';",
        "AdminPwd = '${data.azurerm_key_vault_secret.adminpassword.value}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${data.azurerm_key_vault_secret.arm_client_secret.value}';",
        "DscConfigurationName = 'DomainControllerConfiguration2';",
        "Domain = '${var.adds_domain_name}';",
        "DnsResolverCloud = '${cidrhost(var.subnets_cloud["snet-misc-01"].address_prefixes[0], 4)}';",
        "SkipAzureAutomationConfiguration = $false"
      ]
    }

    provisioner_vm_jumpbox_win = {
      name = "Register-DscNode.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "Location = '${var.location}';",
        "AutomationAccountName = '${var.automation_account_name}';",
        "VmAddsName = '${var.vm_adds_name}';",
        "VmJumpboxWinName = '${var.vm_jumpbox_win_name}';",
        "AdminUsername = '${data.azurerm_key_vault_secret.adminuser.value}';",
        "AdminPwd = '${data.azurerm_key_vault_secret.adminpassword.value}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${data.azurerm_key_vault_secret.arm_client_secret.value}';",
        "DscConfigurationName = 'JumpBoxConfiguration2';",
        "Domain = '${var.adds_domain_name}';",
        "DnsResolverCloud = '${cidrhost(var.subnets_cloud["snet-misc-01"].address_prefixes[0], 4)}';",
        "SkipAzureAutomationConfiguration = $true"
      ]
    }
  }
}
