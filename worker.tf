# Langfuse Worker Container App
# Processes events asynchronously from Redis queue
resource "azurerm_container_app" "langfuse_worker" {
  name                         = "langfuse-worker"
  container_app_environment_id = azapi_resource.container_app_environment.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    revision_suffix = "v3-ch-single"

    container {
      name   = "langfuse-worker"
      image  = "langfuse/langfuse-worker:${var.langfuse_image_tag}"
      cpu    = var.worker_cpu
      memory = "${var.worker_memory}Gi"

      # Database connection
      env {
        name  = "DATABASE_URL"
        value = "postgresql://${azurerm_postgresql_flexible_server.this.administrator_login}:${azurerm_postgresql_flexible_server.this.administrator_password}@${azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address}:5432/${azurerm_postgresql_flexible_server_database.langfuse.name}?sslmode=require"
      }

      env {
        name  = "DIRECT_URL"
        value = "postgresql://${azurerm_postgresql_flexible_server.this.administrator_login}:${azurerm_postgresql_flexible_server.this.administrator_password}@${azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address}:5432/${azurerm_postgresql_flexible_server_database.langfuse.name}?sslmode=require"
      }

      # Redis connection
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

      # Secrets (shared with web container)
      env {
        name        = "NEXTAUTH_SECRET"
        secret_name = "nextauth-secret"
      }

      env {
        name        = "SALT"
        secret_name = "salt"
      }

      # S3/Azure Blob Storage
      env {
        name  = "S3_ENDPOINT"
        value = "https://${azurerm_storage_account.this.name}.blob.core.windows.net"
      }

      env {
        name  = "S3_BUCKET_NAME"
        value = azurerm_storage_container.this.name
      }

      # Worker requires this specific env var for S3 bucket
      env {
        name  = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET"
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

      # ClickHouse connection
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

      # Encryption key (optional)
      dynamic "env" {
        for_each = var.use_encryption_key ? [1] : []
        content {
          name        = "ENCRYPTION_KEY"
          secret_name = "encryption-key"
        }
      }

      # Additional environment variables
      dynamic "env" {
        for_each = var.additional_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
    }

    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas
  }

  # Secrets (same as web container)
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
    name  = "clickhouse-password"
    value = random_password.clickhouse_password.result
  }

  dynamic "secret" {
    for_each = var.use_encryption_key ? [1] : []
    content {
      name  = "encryption-key"
      value = random_bytes.encryption_key[0].hex
    }
  }

  # Worker does not need external ingress - it only processes from Redis queue
  # No ingress block means internal-only access

  tags = {
    application = local.tag_name
  }

  depends_on = [
    azurerm_container_app.clickhouse
  ]
}
