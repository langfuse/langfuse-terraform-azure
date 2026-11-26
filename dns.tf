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

# Add A record for the AI gateway domain pointing to the Application Gateway
resource "azurerm_dns_a_record" "gateway" {
  count               = var.enable_ai_gateway ? 1 : 0
  name                = local.gateway_dns_record_name
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_public_ip.appgw.ip_address]

  lifecycle {
    precondition {
      condition     = endswith(lower(local.gateway_domain), ".${lower(var.domain)}") && local.gateway_dns_record_name != ""
      error_message = "gateway_domain must be a subdomain of domain, because the module creates DNS records in the Azure DNS zone for domain."
    }
  }
}