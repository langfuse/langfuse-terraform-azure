resource "azurerm_container_app_environment" "this" {
  name                       = module.naming.container_app_environment.name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id   = azurerm_subnet.container_apps.id

  tags = {
    application = local.tag_name
  }

  # Ensure subnet and provider registration are fully complete before creating the environment
  depends_on = [
    azurerm_subnet.container_apps,
    azurerm_resource_provider_registration.app
  ]
}

resource "azurerm_container_app" "langfuse" {
  name                         = "langfuse"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    revision_suffix = "clickhouse-pw"

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

      env {
        name  = "NEXTAUTH_URL"
        # If domain is not set, use a placeholder. After first deploy, update with actual Container App FQDN
        value = var.domain != null ? "https://${var.domain}" : "https://placeholder.local"
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
        value = "true"
      }

      env {
        name  = "S3_ENDPOINT"
        value = "https://${azurerm_storage_account.this.name}.blob.core.windows.net"
      }

      env {
        name  = "S3_BUCKET_NAME"
        value = azurerm_storage_container.this.name
      }

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
        name  = "LANGFUSE_S3_EVENT_UPLOAD_PREFIX"
        value = "events/"
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
        name        = "CLICKHOUSE_MIGRATION_URL"
        secret_name = "clickhouse-migration-url"
      }

      env {
        name        = "CLICKHOUSE_URL"
        secret_name = "clickhouse-url"
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

  secret {
    name  = "clickhouse-migration-url"
    value = "clickhouse://default:${random_password.clickhouse_password.result}@${azurerm_container_app.clickhouse.ingress[0].fqdn}:9000/default"
  }

  secret {
    name  = "clickhouse-url"
    value = "clickhouse://default:${random_password.clickhouse_password.result}@${azurerm_container_app.clickhouse.ingress[0].fqdn}:9000/default"
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
  }

  tags = {
    application = local.tag_name
  }
}

# Azure File Share storage for ClickHouse persistence
resource "azurerm_container_app_environment_storage" "clickhouse" {
  name                         = "clickhouse-storage"
  container_app_environment_id = azurerm_container_app_environment.this.id
  account_name                 = azurerm_storage_account.this.name
  share_name                   = azurerm_storage_share.clickhouse.name
  access_key                   = azurerm_storage_account.this.primary_access_key
  access_mode                  = "ReadWrite"
}
