output "child_cert_pfx" {
  description = "Convert to pfx: openssl pkcs12 -export -out child_cert.pfx -inkey child_cert_key.pem -in child_cert.pem -certfile root_cert.pem"
  value       = base64encode(tls_locally_signed_cert.child_cert.cert_pem)
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
  value = tls_self_signed_cert.root_cert.cert_pem
}

output "debug" {
  value = local.public_cert_data
}
