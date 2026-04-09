locals {
  # Built-in Azure role definition IDs
  desktop_virtualization_user_role = "1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63"
  vm_user_login_role               = "fb879df8-f326-4884-b1cf-06f3ad86be52"

  # Host pool configuration
  rdp_properties = "drivestoredirect:s:*;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:1;redirectprinters:i:1;devicestoredirect:s:*;redirectcomports:i:1;redirectsmartcards:i:1;usbdevicestoredirect:s:*;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;enablerdsaadauth:i:1;"

  # Role assignments for session host VMs (follows vm_win_roles pattern from vnet-app)
  session_host_roles = {
    kv_secrets_user_personal = {
      principal_id         = azurerm_windows_virtual_machine.personal.identity[0].principal_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Key Vault Secrets User"
      scope                = var.key_vault_id
    }
  }
}
