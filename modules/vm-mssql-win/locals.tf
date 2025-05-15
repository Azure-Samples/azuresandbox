locals {
  local_scripts = {
    provisioner = {
      name = "Register-DscNode.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "Location = '${var.location}';",
        "AutomationAccountName = '${var.automation_account_name}';",
        "VirtualMachineName = '${var.vm_mssql_win_name}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${data.azurerm_key_vault_secret.arm_client_secret.value}';",
        "DscConfigurationName = 'MssqlVmConfiguration'"
      ]
    }
  }

  remote_scripts = {
    orchestrator = {
      name = "Invoke-MssqlConfiguration.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "KeyVaultName = '${var.key_vault_name}';",
        "Domain = '${var.adds_domain_name}';",
        "AdminUsernameSecret = '${var.admin_username_secret}';",
        "AdminPwdSecret = '${var.admin_password_secret}';",
        "TempDiskSizeMb = '${var.temp_disk_size_mb}'"
      ]
    }


    startup = {
      name       = "Set-MssqlStartupConfiguration.ps1"
      parameters = null
    }

    worker = {
      name       = "Set-MssqlConfiguration.ps1"
      parameters = null
    }
  }

  disks = {
    sqldata = {
      name         = "vol_sqldata_M",
      disk_size_gb = "128",
      lun          = "0",
      caching      = "ReadOnly"
    },
    sqllog = {
      name         = "vol_sqllog_L",
      disk_size_gb = "32",
      lun          = "1",
      caching      = "None"
    }
  }

  roles = {
    kv_secrets_user_vm_mssql_win = {
      principal_id         = azurerm_windows_virtual_machine.this.identity[0].principal_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Key Vault Secrets User"
      scope                = var.key_vault_id
    }
    st_blob_reader_vm_mssql_win = {
      principal_id         = azurerm_windows_virtual_machine.this.identity[0].principal_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Storage Blob Data Reader"
      scope                = var.storage_account_id
    }
  }
}
