locals {
  subnets = {
    GatewaySubnet = {
      address_prefix        = var.subnet_GatewaySubnet_address_prefix
      associate_nat_gateway = false
    }

    snet-adds-02 = {
      address_prefix        = var.subnet_adds_address_prefix
      associate_nat_gateway = true
    }

    snet-misc-04 = {
      address_prefix        = var.subnet_misc_address_prefix
      associate_nat_gateway = true
    }
  }
}
