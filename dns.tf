# Add DNS zone
resource "azurerm_dns_zone" "this" {
  name                = var.domain
  resource_group_name = azurerm_resource_group.this.name
}

# Add A record for the domain pointing to the Application Gateway
resource "azurerm_dns_a_record" "app_gateway" {
  name                = "@" # Create a record for the root domain
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_public_ip.appgw.ip_address]
}