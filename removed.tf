# Remove provider registration resources from state
# These resources should not be managed by Terraform
# Azure will keep the provider registrations active

removed {
  from = azurerm_resource_provider_registration.app

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_resource_provider_registration.storage

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_resource_provider_registration.dbforpostgresql

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_resource_provider_registration.cache

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_resource_provider_registration.network

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_resource_provider_registration.operationalinsights

  lifecycle {
    destroy = false
  }
}
