# Redis Enterprise Cluster resource
resource "azurerm_redis_enterprise_cluster" "this" {
  count               = var.use_redis_enterprise ? 1 : 0
  name                = "${local.globally_unique_prefix}${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku_name            = "${var.redis_enterprise_sku}-${var.redis_capacity}"
  
  tags = {
    application = local.tag_name
  }
}

# Redis Enterprise Database resource
resource "azurerm_redis_enterprise_database" "this" {
  count                     = var.use_redis_enterprise ? 1 : 0
  name                      = "default"
  cluster_id                = azurerm_redis_enterprise_cluster.this[0].id
  client_protocol           = "Encrypted"
  eviction_policy           = "NoEviction"
  port                      = 10000
  clustering_policy         = "EnterpriseCluster"
  module {
    name = "RedisJSON"
  }
}
