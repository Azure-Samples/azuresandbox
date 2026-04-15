locals {
  local_scripts = {
    configure_automation = {
      name = "Set-AutomationAccountConfiguration.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "AutomationAccountName = '${var.automation_account_name}';",
        "VmDevopsWinName = '${var.vm_devops_win_name}';",
        "VmDevopsWinInstanceCount = '${var.vm_devops_win_instances}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${var.arm_client_secret}';"
      ]
    }

    vm_provisioner = {
      name = "Register-DscNode.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "Location = '${var.location}';",
        "AutomationAccountName = '${var.automation_account_name}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${var.arm_client_secret}';",
        "DscConfigurationName = 'VmDevopsWinConfiguration';"
      ]
    }
  }

  remote_scripts = {
    configuration = {
      name       = "Set-VmDevopsWinConfiguration.ps1"
      parameters = []
    }
  }

  vm_devops_win_data_disk_count = var.vm_devops_win_data_disk_size_gb == 0 ? 0 : 1

  vm_devops_win_names = formatlist("${var.vm_devops_win_name}%03d", range(1, (1 + var.vm_devops_win_instances)))
}
