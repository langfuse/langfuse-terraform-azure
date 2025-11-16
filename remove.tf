# This file is used to remove Azure Resource Provider Registrations
# when destroying the infrastructure.
#
# Usage:
# 1. Rename provider_registration.tf to provider_registration.tf.bak
# 2. Run: terraform apply (this will remove the prevent_destroy lifecycle)
# 3. Run: terraform destroy (to destroy all resources)
# 4. Run: terraform apply (to unregister providers)
# 5. Clean up: rm remove.tf and restore provider_registration.tf if needed
#
# Note: Provider unregistration is optional. Providers can remain registered
# in the Azure subscription without incurring costs.

# Import existing provider registrations without prevent_destroy lifecycle
# This allows them to be destroyed when running terraform destroy

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
