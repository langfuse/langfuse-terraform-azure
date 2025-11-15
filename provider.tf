provider "azurerm" {
  features {}

  # Disable automatic provider registration
  # We manage all provider registrations explicitly via azurerm_resource_provider_registration
  resource_provider_registrations = "none"
}
