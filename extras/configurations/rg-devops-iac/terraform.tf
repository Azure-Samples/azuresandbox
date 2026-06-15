terraform {
  required_version = "~> 1.15.6"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.10.0"
    }    
    
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.76.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3.0"
    }
  }
}
