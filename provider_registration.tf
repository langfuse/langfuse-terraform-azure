# Auto-register required Azure resource providers
# This eliminates the need to manually run 'az provider register' commands

resource "azurerm_resource_provider_registration" "app" {
  name = "Microsoft.App"
}

resource "azurerm_resource_provider_registration" "storage" {
  name = "Microsoft.Storage"
}

resource "azurerm_resource_provider_registration" "dbforpostgresql" {
  name = "Microsoft.DBforPostgreSQL"
}

resource "azurerm_resource_provider_registration" "cache" {
  name = "Microsoft.Cache"
}

resource "azurerm_resource_provider_registration" "network" {
  name = "Microsoft.Network"
}

resource "azurerm_resource_provider_registration" "operationalinsights" {
  name = "Microsoft.OperationalInsights"
}
