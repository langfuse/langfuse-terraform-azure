resource "azapi_resource" "container_app_environment" {
  type      = "Microsoft.App/managedEnvironments@2024-03-01"
  name      = module.naming.container_app_environment.name
  location  = azurerm_resource_group.this.location
  parent_id = azurerm_resource_group.this.id
  tags = {
    application = local.tag_name
  }

  body = {
    properties = {
      appLogsConfiguration = {
        destination = "log-analytics"
        logAnalyticsConfiguration = {
          customerId = azurerm_log_analytics_workspace.this.workspace_id
          sharedKey  = azurerm_log_analytics_workspace.this.primary_shared_key
        }
      }
      vnetConfiguration = {
        infrastructureSubnetId = azurerm_subnet.container_apps.id
        internal               = true
      }
      zoneRedundant = false
    }
  }

  # Export properties for Private DNS Zone configuration
  response_export_values = ["properties.defaultDomain", "properties.staticIp"]

  depends_on = [
    azurerm_subnet.container_apps,
    azurerm_resource_provider_registration.app
  ]
}

# Private DNS Zone for Internal Container Apps Environment
# Required for Application Gateway to resolve internal Container Apps FQDNs
resource "azurerm_private_dns_zone" "container_apps" {
  name                = azapi_resource.container_app_environment.output.properties.defaultDomain
  resource_group_name = azurerm_resource_group.this.name

  tags = {
    application = local.tag_name
  }
}

# Link Private DNS Zone to VNet
# This allows Application Gateway (and other resources in VNet) to resolve Container Apps FQDNs
resource "azurerm_private_dns_zone_virtual_network_link" "container_apps" {
  name                  = "link-${var.name}-container-apps"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.container_apps.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

# Wildcard A record pointing to Container Apps Environment static IP
# This resolves all *.{defaultDomain} to the Environment's internal load balancer
resource "azurerm_private_dns_a_record" "container_apps_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.container_apps.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azapi_resource.container_app_environment.output.properties.staticIp]
}

resource "azurerm_container_app" "langfuse" {
  name                         = "langfuse"
  container_app_environment_id = azapi_resource.container_app_environment.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    revision_suffix = "v3-redis-tls"

    container {
      name   = "langfuse"
      image  = "langfuse/langfuse:${var.langfuse_image_tag}"
      cpu    = var.container_app_cpu
      memory = "${var.container_app_memory}Gi"

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${azurerm_postgresql_flexible_server.this.administrator_login}:${azurerm_postgresql_flexible_server.this.administrator_password}@${azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address}:5432/${azurerm_postgresql_flexible_server_database.langfuse.name}?sslmode=require"
      }

      env {
        name  = "DIRECT_URL"
        value = "postgresql://${azurerm_postgresql_flexible_server.this.administrator_login}:${azurerm_postgresql_flexible_server.this.administrator_password}@${azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address}:5432/${azurerm_postgresql_flexible_server_database.langfuse.name}?sslmode=require"
      }

      env {
        name  = "REDIS_HOST"
        value = local.redis_host
      }

      env {
        name  = "REDIS_PORT"
        value = local.redis_port
      }

      env {
        name        = "REDIS_AUTH"
        secret_name = "redis-password"
      }

      # Azure Cache for Redis requires TLS
      env {
        name  = "REDIS_TLS_ENABLED"
        value = "true"
      }

      # Bypass TLS certificate validation for Private Endpoint (IP not in cert SANs)
      env {
        name  = "REDIS_TLS_REJECT_UNAUTHORIZED"
        value = "false"
      }

      env {
        name  = "REDIS_TLS_CHECK_SERVER_IDENTITY"
        value = "false"
      }

      env {
        name  = "NEXTAUTH_URL"
        # Use custom domain with HTTPS if set, otherwise use App Gateway public IP FQDN with HTTP
        value = var.domain != null ? "https://${var.domain}" : "http://${random_id.dns_label.hex}.${var.location}.cloudapp.azure.com"
      }

      env {
        name        = "NEXTAUTH_SECRET"
        secret_name = "nextauth-secret"
      }

      env {
        name        = "SALT"
        secret_name = "salt"
      }

      env {
        name  = "LANGFUSE_CSP_ENFORCE_HTTPS"
        # Disable HTTPS enforcement when using HTTP (no custom domain with TLS)
        value = var.domain != null ? "true" : "false"
      }

      env {
        name  = "S3_ENDPOINT"
        value = "https://${azurerm_storage_account.this.name}.blob.core.windows.net"
      }

      env {
        name  = "S3_BUCKET_NAME"
        value = azurerm_storage_container.this.name
      }

      # Required for S3 event uploads (Langfuse v3 requires LANGFUSE_S3_EVENT_UPLOAD_* variables)
      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET"
        value = azurerm_storage_container.this.name
      }

      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_REGION"
        value = azurerm_storage_account.this.location
      }

      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID"
        value = azurerm_storage_account.this.name
      }

      env {
        name        = "LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY"
        secret_name = "storage-access-key"
      }

      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT"
        value = "https://${azurerm_storage_account.this.name}.blob.core.windows.net"
      }

      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE"
        value = "true"
      }

      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_PREFIX"
        value = "events/"
      }

      # Legacy S3_* variables (kept for compatibility)
      env {
        name  = "S3_REGION"
        value = azurerm_storage_account.this.location
      }

      env {
        name  = "S3_ACCESS_KEY_ID"
        value = azurerm_storage_account.this.name
      }

      env {
        name        = "S3_SECRET_ACCESS_KEY"
        secret_name = "storage-access-key"
      }

      env {
        name  = "LANGFUSE_S3_BATCH_EXPORT_PREFIX"
        value = "exports/"
      }

      env {
        name  = "LANGFUSE_S3_MEDIA_UPLOAD_PREFIX"
        value = "media/"
      }

      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_ENABLED"
        value = "true"
      }

      env {
        name  = "LANGFUSE_S3_BATCH_EXPORT_ENABLED"
        value = "true"
      }

      env {
        name  = "LANGFUSE_S3_MEDIA_UPLOAD_ENABLED"
        value = "true"
      }

      env {
        name  = "LANGFUSE_S3_STORAGE_PROVIDER"
        value = "azure"
      }

      env {
        name  = "CLICKHOUSE_MIGRATION_URL"
        value = "clickhouse://${azurerm_container_app.clickhouse.name}:9000"
      }

      env {
        name  = "CLICKHOUSE_URL"
        value = "http://${azurerm_container_app.clickhouse.name}:8123"
      }

      env {
        name  = "CLICKHOUSE_USER"
        value = "default"
      }

      env {
        name        = "CLICKHOUSE_PASSWORD"
        secret_name = "clickhouse-password"
      }

      # Single node ClickHouse - disable cluster mode
      env {
        name  = "CLICKHOUSE_CLUSTER_ENABLED"
        value = "false"
      }

      env {
        name  = "LANGFUSE_INIT_USER_EMAIL"
        value = "admin@example.com"
      }

      env {
        name  = "LANGFUSE_INIT_USER_NAME"
        value = "Admin User"
      }

      env {
        name        = "LANGFUSE_INIT_USER_PASSWORD"
        secret_name = "langfuse-admin-password"
      }

      dynamic "env" {
        for_each = var.use_encryption_key ? [1] : []
        content {
          name        = "ENCRYPTION_KEY"
          secret_name = "encryption-key"
        }
      }

      dynamic "env" {
        for_each = var.additional_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      dynamic "env" {
        for_each = [for env in var.additional_env : env if env.valueFrom != null && env.valueFrom.secretKeyRef != null]
        content {
          name        = env.value.name
          secret_name = env.value.valueFrom.secretKeyRef.name
        }
      }
    }

    # ClickHouse sidecar removed - now using dedicated Container App
    # See clickhouse.tf for dedicated ClickHouse Container App

    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas
  }

  secret {
    name  = "redis-password"
    value = local.redis_password
  }

  secret {
    name  = "nextauth-secret"
    value = random_bytes.nextauth_secret.base64
  }

  secret {
    name  = "salt"
    value = random_bytes.salt.base64
  }

  secret {
    name  = "storage-access-key"
    value = azurerm_storage_account.this.primary_access_key
  }

  # ClickHouse password for authentication
  # Langfuse uses CLICKHOUSE_USER and CLICKHOUSE_PASSWORD separately from the URLs
  secret {
    name  = "clickhouse-password"
    value = random_password.clickhouse_password.result
  }

  secret {
    name  = "langfuse-admin-password"
    value = random_password.langfuse_admin_password.result
  }

  dynamic "secret" {
    for_each = var.use_encryption_key ? [1] : []
    content {
      name  = "encryption-key"
      value = random_bytes.encryption_key[0].hex
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
    allow_insecure_connections = true
  }

  tags = {
    application = local.tag_name
  }
}

# Azure File Share storage for ClickHouse persistence
# Register NFS Storage in Container App Environment using AzAPI
resource "azapi_resource" "clickhouse_nfs" {
  type                      = "Microsoft.App/managedEnvironments/storages@2023-11-02-preview"
  name                      = "clickhouse-nfs"
  parent_id                 = azapi_resource.container_app_environment.id
  schema_validation_enabled = false

  body = {
    properties = {
      nfsAzureFile = {
        accessMode = "ReadWrite"
        server     = azurerm_storage_account.clickhouse_nfs.primary_file_host
        shareName  = "/${azurerm_storage_account.clickhouse_nfs.name}/${azurerm_storage_share.clickhouse_nfs.name}"
      }
    }
  }
}
