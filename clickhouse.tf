# Random password for ClickHouse
# Using a alphanumeric password to avoid issues with special characters on bash entrypoint
resource "random_password" "clickhouse_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1

  # Change this value to force password regeneration
  # Useful when NFS data is cleared and ClickHouse needs reinitialization
  keepers = {
    version = "2"
  }
}

# Dedicated ClickHouse Container App
# This replaces the sidecar pattern to ensure single ClickHouse instance
# regardless of Langfuse scaling
resource "azurerm_container_app" "clickhouse" {
  name                         = "${var.name}-clickhouse"
  container_app_environment_id = azapi_resource.container_app_environment.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  secret {
    name  = "listen-xml"
    value = "<clickhouse><listen_host>0.0.0.0</listen_host></clickhouse>"
  }

  # Explicit password configuration for default user
  # This ensures password is set regardless of initialization state
  secret {
    name  = "users-xml"
    value = <<-EOT
      <clickhouse>
        <users>
          <default>
            <password>${random_password.clickhouse_password.result}</password>
            <networks>
              <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
          </default>
        </users>
      </clickhouse>
    EOT
  }

  template {

    container {
      name   = "clickhouse"
      image  = "clickhouse/clickhouse-server:latest-alpine"
      cpu    = 2.0
      memory = "4Gi"

      # Enable network access for internal communication
      # Using a simple password for internal-only access (secured by Internal Ingress)
      env {
        name  = "CLICKHOUSE_USER"
        value = "default"
      }

      env {
        name  = "CLICKHOUSE_PASSWORD"
        value = random_password.clickhouse_password.result
      }

      # Force revision update
      env {
        name  = "CLICKHOUSE_REVISION"
        value = "8"
      }

      volume_mounts {
        name = "clickhouse-data"
        path = "/var/lib/clickhouse"
      }

      volume_mounts {
        name = "clickhouse-config"
        path = "/etc/clickhouse-server/config.d"
      }

      volume_mounts {
        name = "clickhouse-users"
        path = "/etc/clickhouse-server/users.d"
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 8123
        path                    = "/ping"
        initial_delay           = 30
        interval_seconds        = 10
        failure_count_threshold = 30 # Allow up to 5 minutes for startup
      }
    }

    # Persistent volume for ClickHouse data
    volume {
      name         = "clickhouse-data"
      storage_type = "EmptyDir"
    }

    # Configuration volume from secret
    volume {
      name         = "clickhouse-config"
      storage_type = "Secret"
    }

    # Users configuration volume from secret
    volume {
      name         = "clickhouse-users"
      storage_type = "Secret"
    }

    # Always keep exactly 1 replica
    min_replicas = 1
    max_replicas = 1
  }

  # Internal Ingress for ClickHouse native protocol (port 9000)
  # TCP transport required for native ClickHouse protocol used by CLICKHOUSE_MIGRATION_URL
  # HTTP (8123) is added via additionalPortMappings in azapi_update_resource
  ingress {
    external_enabled = false   # Internal only
    target_port      = 9000    # ClickHouse native protocol
    exposed_port     = 9000    # Required for TCP transport
    transport        = "tcp"   # TCP transport for native protocol

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    application = local.tag_name
  }

  lifecycle {
    ignore_changes = [
      ingress,
      template[0].revision_suffix,
      template[0].volume  # Volume is updated by azapi_update_resource to use NFS
    ]
  }
}

# Update ClickHouse Container App with NFS volume and TCP+HTTP ingress configuration
# Using azapi_update_resource because azurerm_container_app doesn't support:
# - NFS volumes
# - additionalPortMappings for multiple ports
resource "azapi_update_resource" "clickhouse_volumes" {
  type        = "Microsoft.App/containerApps@2024-03-01"
  resource_id = azurerm_container_app.clickhouse.id

  body = {
    properties = {
      configuration = {
        secrets = [
          {
            name  = "listen-xml"
            value = "<clickhouse><listen_host>0.0.0.0</listen_host></clickhouse>"
          },
          {
            name  = "users-xml"
            value = <<-EOT
              <clickhouse>
                <users>
                  <default>
                    <password>${random_password.clickhouse_password.result}</password>
                    <networks>
                      <ip>::/0</ip>
                    </networks>
                    <profile>default</profile>
                    <quota>default</quota>
                    <access_management>1</access_management>
                  </default>
                </users>
              </clickhouse>
            EOT
          }
        ]
        ingress = {
          external    = false
          targetPort  = 9000
          exposedPort = 9000
          transport   = "Tcp"  # Azure API returns PascalCase
          traffic = [
            {
              weight         = 100
              latestRevision = true
            }
          ]
          # HTTP (8123) for CLICKHOUSE_URL - internal communication
          additionalPortMappings = [
            {
              external    = false
              targetPort  = 8123
              exposedPort = 8123
            }
          ]
        }
      }
      template = {
        volumes = [
          {
            name        = "clickhouse-data"
            storageType = "NfsAzureFile"
            storageName = azapi_resource.clickhouse_nfs.name
          },
          {
            name        = "clickhouse-config"
            storageType = "Secret"
            secrets = [
              {
                secretRef = "listen-xml"
                path      = "listen.xml"
              }
            ]
          },
          {
            name        = "clickhouse-users"
            storageType = "Secret"
            secrets = [
              {
                secretRef = "users-xml"
                path      = "default-password.xml"
              }
            ]
          }
        ]
      }
    }
  }

  depends_on = [azurerm_container_app.clickhouse]
}
