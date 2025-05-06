# Redis subnet configuration
resource "azurerm_subnet" "redis" {
  name                 = "redis"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.redis_subnet_address_prefix]
}

# Add Private Endpoint for Redis
resource "azurerm_private_endpoint" "redis" {
  name                = "${var.name}-redis"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.aks.id

  private_service_connection {
    name                           = "${var.name}-redis"
    private_connection_resource_id = var.use_redis_enterprise ? azurerm_redis_enterprise_cluster.this[0].id : azurerm_redis_cache.this[0].id
    is_manual_connection           = false
    subresource_names              = var.use_redis_enterprise ? ["redisEnterprise"] : ["redisCache"]
  }
}

# DNS zone for Redis private endpoint
resource "azurerm_private_dns_zone" "redis" {
  name                = var.use_redis_enterprise ? "privatelink.redisenterprise.cache.azure.net" : "privatelink.redis.cache.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

# Link the private DNS zone to the virtual network
resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "${var.name}-redis"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

# Add A record for the Redis cache's private endpoint
resource "azurerm_private_dns_a_record" "redis" {
  name                = var.use_redis_enterprise ? azurerm_redis_enterprise_cluster.this[0].name : azurerm_redis_cache.this[0].name
  zone_name           = azurerm_private_dns_zone.redis.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address]
}
