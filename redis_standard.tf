# Standard Redis Cache resource
resource "azurerm_redis_cache" "this" {
  count                         = var.use_redis_enterprise ? 0 : 1
  name                          = "${local.globally_unique_prefix}${var.name}"
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
