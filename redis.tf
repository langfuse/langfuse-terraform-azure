# Azure Cache for Redis (Standard - non-clustered)
# Using Standard tier to avoid CROSSSLOT issues with Bull queues
resource "azurerm_redis_cache" "this" {
  name                          = module.naming.redis_cache.name_unique
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  capacity                      = var.redis_capacity
  family                        = var.redis_family
  sku_name                      = var.redis_sku_name
  non_ssl_port_enabled          = false
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  redis_configuration {
    maxmemory_policy = "volatile-lru"
  }

  tags = {
    application = local.tag_name
  }
}

# Private Endpoint for Redis
resource "azurerm_private_endpoint" "redis" {
  name                = "${module.naming.private_endpoint.name}-redis"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.name}-redis"
    private_connection_resource_id = azurerm_redis_cache.this.id
    is_manual_connection           = false
    subresource_names              = ["redisCache"]
  }
}

# Private DNS Zone for Redis
resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "${var.name}-redis"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

# A record for Redis private endpoint
resource "azurerm_private_dns_a_record" "redis" {
  name                = azurerm_redis_cache.this.name
  zone_name           = azurerm_private_dns_zone.redis.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address]
}

# Locals for Redis connection info
locals {
  redis_host     = azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address
  redis_port     = "6380"  # SSL port for Azure Cache for Redis
  redis_password = azurerm_redis_cache.this.primary_access_key
}
