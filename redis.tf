# Azure Managed Redis
resource "azurerm_managed_redis" "this" {
  name                = module.naming.redis_cache.name_unique
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = var.redis_sku_name

  default_database {
    access_keys_authentication_enabled = true
    client_protocol                    = "Plaintext"
    clustering_policy                  = "OSSCluster"
    eviction_policy                    = "VolatileLRU"
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
    private_connection_resource_id = azurerm_managed_redis.this.id
    is_manual_connection           = false
    subresource_names              = ["redisEnterprise"]
  }
}

# Private DNS Zone for Redis
resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redisenterprise.cache.azure.net"
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
  name                = azurerm_managed_redis.this.name
  zone_name           = azurerm_private_dns_zone.redis.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address]
}

# Locals for Redis connection info
locals {
  redis_host     = azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address
  redis_port     = tostring(azurerm_managed_redis.this.default_database[0].port)
  redis_password = azurerm_managed_redis.this.default_database[0].primary_access_key
}
