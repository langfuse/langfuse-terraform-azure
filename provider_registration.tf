# Azure Resource Provider Registrations
# These ensure the required providers are registered before creating resources

resource "azurerm_resource_provider_registration" "app" {
  name = "Microsoft.App"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_resource_provider_registration" "storage" {
  name = "Microsoft.Storage"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_resource_provider_registration" "dbforpostgresql" {
  name = "Microsoft.DBforPostgreSQL"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_resource_provider_registration" "cache" {
  name = "Microsoft.Cache"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_resource_provider_registration" "network" {
  name = "Microsoft.Network"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_resource_provider_registration" "operationalinsights" {
  name = "Microsoft.OperationalInsights"

  lifecycle {
    prevent_destroy = true
  }
}
