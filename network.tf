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

# Add non-zonal NAT Gateway
resource "azurerm_public_ip" "nat_gateway" {
  name                = "${module.naming.public_ip.name}-nat-gw"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "this" {
  name                = module.naming.nat_gateway.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}
