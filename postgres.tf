resource "azurerm_subnet" "db" {
  name                 = "${module.naming.subnet.name}db"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.db_subnet_address_prefix]
  service_endpoints    = ["Microsoft.Sql"]

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = module.naming.postgresql_server.name_unique
  resource_group_name           = azurerm_resource_group.this.name
  location                      = var.location
  version                       = "15"
  storage_mb                    = var.postgres_storage_mb
  auto_grow_enabled             = true
  sku_name                      = var.postgres_sku_name
  public_network_access_enabled = false

  administrator_login    = "postgres"
  administrator_password = random_password.postgres_password.result

  dynamic "high_availability" {
    for_each = var.postgres_instance_count > 1 ? [1] : []
    content {
      mode = var.postgres_ha_mode
    }
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 0
    start_minute = 0
  }

  backup_retention_days = 7

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
  }

  tags = {
    application = local.tag_name
  }

  lifecycle {
    ignore_changes = [
      zone,
      authentication[0].tenant_id,
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "langfuse" {
  name      = module.naming.postgresql_database.name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Random password for PostgreSQL
# Using a alphanumeric password to avoid issues with special characters on bash entrypoint
resource "random_password" "postgres_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# Add Private Endpoint for PostgreSQL
resource "azurerm_private_endpoint" "postgres" {
  name                = "${module.naming.private_endpoint.name}-postgres"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.aks.id

  private_service_connection {
    name                           = "${var.name}-postgres"
    private_connection_resource_id = azurerm_postgresql_flexible_server.this.id
    is_manual_connection           = false
    subresource_names              = ["postgresqlServer"]
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.name}-postgres"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}
