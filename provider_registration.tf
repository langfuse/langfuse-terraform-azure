# Explicitly manage Azure resource provider registrations
# provider.tf has resource_provider_registrations = "none" to disable auto-registration

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

# Import blocks for already-registered providers
# These allow Terraform to manage existing provider registrations

import {
  to = azurerm_resource_provider_registration.app
  id = "/subscriptions/72ea3f25-9c69-4d2e-a35c-d3f0cafa963b/providers/Microsoft.App"
}

import {
  to = azurerm_resource_provider_registration.storage
  id = "/subscriptions/72ea3f25-9c69-4d2e-a35c-d3f0cafa963b/providers/Microsoft.Storage"
}

import {
  to = azurerm_resource_provider_registration.dbforpostgresql
  id = "/subscriptions/72ea3f25-9c69-4d2e-a35c-d3f0cafa963b/providers/Microsoft.DBforPostgreSQL"
}

import {
  to = azurerm_resource_provider_registration.cache
  id = "/subscriptions/72ea3f25-9c69-4d2e-a35c-d3f0cafa963b/providers/Microsoft.Cache"
}

import {
  to = azurerm_resource_provider_registration.network
  id = "/subscriptions/72ea3f25-9c69-4d2e-a35c-d3f0cafa963b/providers/Microsoft.Network"
}

import {
  to = azurerm_resource_provider_registration.operationalinsights
  id = "/subscriptions/72ea3f25-9c69-4d2e-a35c-d3f0cafa963b/providers/Microsoft.OperationalInsights"
}
