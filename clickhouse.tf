# Random password for ClickHouse
# Using a alphanumeric password to avoid issues with special characters on bash entrypoint
resource "random_password" "clickhouse_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# ClickHouse Container App
resource "azurerm_container_app" "clickhouse" {
  name                         = "clickhouse"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    container {
      name   = "clickhouse"
      image  = "clickhouse/clickhouse-server:24.3-alpine"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "CLICKHOUSE_DB"
        value = "default"
      }

      env {
        name  = "CLICKHOUSE_USER"
        value = "default"
      }

      env {
        name        = "CLICKHOUSE_PASSWORD"
        secret_name = "clickhouse-password"
      }
    }

    min_replicas = 1
    max_replicas = 1
  }

  secret {
    name  = "clickhouse-password"
    value = random_password.clickhouse_password.result
  }

  # Internal ingress only - accessible within Container App Environment
  ingress {
    external_enabled = false
    target_port      = 8123
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    application = local.tag_name
  }
}
