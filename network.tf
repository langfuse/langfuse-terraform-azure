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
