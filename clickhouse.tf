# Random password for ClickHouse
# Using a alphanumeric password to avoid issues with special characters on bash entrypoint
resource "random_password" "clickhouse_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# Dedicated ClickHouse Container App
# This replaces the sidecar pattern to ensure single ClickHouse instance
# regardless of Langfuse scaling
resource "azurerm_container_app" "clickhouse" {
  name                         = "${var.name}-clickhouse"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    revision_suffix = "auth-enabled"

    container {
      name   = "clickhouse"
      image  = "clickhouse/clickhouse-server:latest-alpine"
      cpu    = 1.0
      memory = "2Gi"

      # Enable network access for internal communication
      # Setting empty password allows network access without authentication
      env {
        name  = "CLICKHOUSE_USER"
        value = "default"
      }

      env {
        name  = "CLICKHOUSE_PASSWORD"
        value = ""
      }

      volume_mounts {
        name = "clickhouse-data"
        path = "/var/lib/clickhouse"
      }
    }

    # Persistent volume for ClickHouse data
    volume {
      name         = "clickhouse-data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.clickhouse.name
    }

    # Always keep exactly 1 replica
    min_replicas = 1
    max_replicas = 1
  }

  # Internal Ingress for ClickHouse native protocol (port 9000)
  ingress {
    external_enabled = false  # Internal only
    target_port      = 9000   # ClickHouse native protocol
    exposed_port     = 9000   # Required for TCP transport
    transport        = "tcp"  # TCP transport for native protocol

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    application = local.tag_name
  }
}
