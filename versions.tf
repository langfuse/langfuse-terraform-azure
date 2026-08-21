terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # azurerm 5.x removed arguments this module still uses
      # (e.g. azurerm_subnet.service_endpoints, private_dns_zone_name on
      # azurerm_private_dns_zone_virtual_network_link)
      version = ">= 3.0.0, < 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0"
    }
  }
}

data "azurerm_client_config" "current" {}
