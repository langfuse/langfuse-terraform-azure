resource "azurerm_virtual_network" "this" {
  name                = module.naming.virtual_network.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.virtual_network_address_prefix]
  dynamic "ddos_protection_plan" {
    for_each = var.use_ddos_protection ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.this[0].id
      enable = true
    }
  }
}

# Add DDoS Protection Plan
resource "azurerm_network_ddos_protection_plan" "this" {
  count = var.use_ddos_protection ? 1 : 0

  name                = module.naming.network_ddos_protection_plan.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

# Container Apps subnet
resource "azurerm_subnet" "container_apps" {
  name                 = "${module.naming.subnet.name}-container-apps"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.container_apps_subnet_address_prefix]

  # Service endpoints for Storage Account access
  service_endpoints = ["Microsoft.Storage"]

  # Note: Do NOT add delegation here - Container App Environment will manage it automatically
}

# Private Endpoint subnet (for PostgreSQL and Redis)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "${module.naming.subnet.name}-private-endpoints"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoints_subnet_address_prefix]
}
