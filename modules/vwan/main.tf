#region resources

# Generate a private key for the root certificate
resource "tls_private_key" "root_cert_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate a self-signed root certificate
resource "tls_self_signed_cert" "root_cert" {
  private_key_pem = tls_private_key.root_cert_key.private_key_pem
  subject {
    common_name  = "MyP2SVPNRootCert"
    organization = "AzureSandbox"
  }
  validity_period_hours = 8760 # 1 year
  is_ca_certificate     = true
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature"
  ]
}

# Generate a private key for the client certificate
resource "tls_private_key" "client_cert_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Store the private key in key vault so it can be used later to create a pfx file
resource "azurerm_key_vault_secret" "this" {
  name         = "p2svpn-client-private-key-pem"
  value        = tls_private_key.client_cert_key.private_key_pem
  key_vault_id = var.key_vault_id
}

# Generate a client certificate signed by the root certificate
resource "tls_cert_request" "client_cert_request" {
  private_key_pem = tls_private_key.client_cert_key.private_key_pem
  subject {
    common_name  = "MyP2SVPNClientCert"
    organization = "AzureSandbox"
  }
  dns_names = ["MyP2SVPNClientCert"]
}

resource "tls_locally_signed_cert" "client_cert" {
  cert_request_pem      = tls_cert_request.client_cert_request.cert_request_pem
  ca_private_key_pem    = tls_private_key.root_cert_key.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.root_cert.cert_pem
  validity_period_hours = 8760 # 1 year
  allowed_uses = [
    "client_auth",
    "digital_signature",
    "key_encipherment"
  ]
}
#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.2"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion
