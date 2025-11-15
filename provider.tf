provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # Disable automatic provider registration - we manage them explicitly
  resource_provider_registrations = "none"
}
