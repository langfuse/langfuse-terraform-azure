terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.0 is the floor because rbac_authorization_enabled replaced
      # enable_rbac_authorization there. azurerm 5.x removed arguments this module still uses
      # (e.g. azurerm_subnet.service_endpoints, private_dns_zone_name on
      # azurerm_private_dns_zone_virtual_network_link)
      version = ">= 4.0.0, < 5.0.0"
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
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

data "azurerm_client_config" "current" {}
