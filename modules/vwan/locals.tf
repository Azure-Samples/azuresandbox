locals {
  public_cert_data = join("\n", slice(split("\n", tls_self_signed_cert.root_cert.cert_pem), 1, length(split("\n", tls_self_signed_cert.root_cert.cert_pem)) - 2))
}
