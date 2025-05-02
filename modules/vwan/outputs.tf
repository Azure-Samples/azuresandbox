output "client_cert_pem" {
  value = tls_locally_signed_cert.client_cert.cert_pem
}

output "resource_ids" {
  value = {
    virtual_wan     = azurerm_virtual_wan.this.id
    virtual_wan_hub = azurerm_virtual_hub.this.id
  }
}

output "resource_names" {
  value = {
    virtual_wan     = azurerm_virtual_wan.this.name
    virtual_wan_hub = azurerm_virtual_hub.this.name
  }
}

output "root_cert_pem" {
  description = "Self signed root certificate in PEM format for use with point-to-site VPN clients."
  value = tls_self_signed_cert.root_cert.cert_pem
}
