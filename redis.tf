# Azure Cache for Redis (Standard tier - Basic/Standard/Premium)
resource "azurerm_redis_cache" "this" {
  count = var.redis_tier == "standard" ? 1 : 0

  name                          = module.naming.redis_cache.name_unique
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  capacity                      = var.redis_capacity
  family                        = var.redis_family
  sku_name                      = var.redis_sku_name
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  redis_configuration {
    maxmemory_policy = "noeviction"
  }

  tags = {
    application = local.tag_name
  }
}

# Azure Cache for Redis Enterprise (Enterprise tier)
resource "azurerm_redis_enterprise_cluster" "this" {
  count = var.redis_tier == "enterprise" ? 1 : 0

  name                = module.naming.redis_cache.name_unique
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = var.redis_enterprise_sku_name
  minimum_tls_version = "1.2"

  tags = {
    application = local.tag_name
  }
}

resource "azurerm_redis_enterprise_database" "this" {
  count = var.redis_tier == "enterprise" ? 1 : 0

  name                = "default"
  resource_group_name = azurerm_resource_group.this.name
  cluster_id          = azurerm_redis_enterprise_cluster.this[0].id

  client_protocol   = "Encrypted"
  clustering_policy = "EnterpriseCluster"
  eviction_policy   = "NoEviction"
  port              = 10000
}

# Private Endpoint for Redis (Standard tier)
resource "azurerm_private_endpoint" "redis_standard" {
  count = var.redis_tier == "standard" ? 1 : 0

  name                = "${module.naming.private_endpoint.name}-redis"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.name}-redis"
    private_connection_resource_id = azurerm_redis_cache.this[0].id
    is_manual_connection           = false
    subresource_names              = ["redisCache"]
  }
}

# Private Endpoint for Redis (Enterprise tier)
resource "azurerm_private_endpoint" "redis_enterprise" {
  count = var.redis_tier == "enterprise" ? 1 : 0

  name                = "${module.naming.private_endpoint.name}-redis"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.name}-redis-enterprise"
    private_connection_resource_id = azurerm_redis_enterprise_cluster.this[0].id
    is_manual_connection           = false
    subresource_names              = ["redisEnterprise"]
  }
}

# Private DNS Zone for Redis
resource "azurerm_private_dns_zone" "redis" {
  name                = var.redis_tier == "standard" ? "privatelink.redis.cache.windows.net" : "privatelink.redisenterprise.cache.azure.net"
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
  name                = var.redis_tier == "standard" ? azurerm_redis_cache.this[0].name : azurerm_redis_enterprise_cluster.this[0].name
  zone_name           = azurerm_private_dns_zone.redis.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records = [
    var.redis_tier == "standard" ?
      azurerm_private_endpoint.redis_standard[0].private_service_connection[0].private_ip_address :
      azurerm_private_endpoint.redis_enterprise[0].private_service_connection[0].private_ip_address
  ]
}

# Locals for Redis connection info
locals {
  redis_host     = var.redis_tier == "standard" ? azurerm_private_endpoint.redis_standard[0].private_service_connection[0].private_ip_address : azurerm_private_endpoint.redis_enterprise[0].private_service_connection[0].private_ip_address
  redis_port     = var.redis_tier == "standard" ? "6380" : "10000"
  redis_password = var.redis_tier == "standard" ? azurerm_redis_cache.this[0].primary_access_key : azurerm_redis_enterprise_database.this[0].primary_access_key
}
