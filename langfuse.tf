locals {
  langfuse_values = <<EOT
langfuse:
  image:
    tag: ${jsonencode(var.app_version)}
  salt:
    secretKeyRef:
      name: langfuse
      key: salt
  nextauth:
    url: "https://${var.domain}"
    secret:
      secretKeyRef:
        name: langfuse
        key: nextauth-secret
postgresql:
  deploy: false
  host: ${azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address}:5432
  auth:
    username: ${azurerm_postgresql_flexible_server.this.administrator_login}
    database: langfuse
    existingSecret: langfuse
    secretKeys:
      userPasswordKey: postgres-password
redis:
  deploy: false
  host: ${azurerm_managed_redis.this.hostname}
  port: ${azurerm_managed_redis.this.default_database[0].port}
  tls:
    enabled: true
  auth:
    existingSecret: langfuse
    existingSecretPasswordKey: redis-password
s3:
  deploy: false
  storageProvider: "azure"
  endpoint: https://${azurerm_storage_account.this.name}.blob.core.windows.net
  bucket: ${azurerm_storage_container.this.name}
  region: ${azurerm_storage_account.this.location}
  accessKeyId:
    value: ${azurerm_storage_account.this.name}
  secretAccessKey:
    secretKeyRef:
      name: ${kubernetes_secret_v1.langfuse.metadata[0].name}
      key: storage-access-key
  forcePathStyle: false
  eventUpload:
    prefix: "events/"
  batchExport:
    prefix: "exports/"
  mediaUpload:
    prefix: "media/"
EOT

  # In-cluster ClickHouse: the Langfuse Helm chart v2 renders ClickHouseCluster
  # and KeeperCluster resources reconciled by the ClickHouse operator (see
  # clickhouse.tf).
  clickhouse_internal_values = !local.deploy_clickhouse ? "" : <<EOT
clickhouse:
  deploy: true
  auth:
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
  cluster:
    replicas: ${var.clickhouse_replicas}
    storage:
      size: ${var.clickhouse_storage_size}
      className: ${var.clickhouse_storage_class}
    resources:
      requests:
        cpu: ${jsonencode(var.clickhouse_resources.cpu)}
        memory: ${jsonencode(var.clickhouse_resources.memory)}
      limits:
        cpu: ${jsonencode(var.clickhouse_resources.cpu)}
        memory: ${jsonencode(var.clickhouse_resources.memory)}
  keeper:
    replicas: ${var.clickhouse_keeper_replicas}
    storage:
      size: ${var.clickhouse_keeper_storage_size}
      className: ${var.clickhouse_storage_class}
EOT

  # External ClickHouse: skip the in-cluster deployment and point Langfuse at
  # the provided instance.
  clickhouse_external_values = local.deploy_clickhouse ? "" : <<EOT
clickhouse:
  deploy: false
  host: ${jsonencode(var.external_clickhouse.host)}
  httpPort: ${var.external_clickhouse.http_port}
  nativePort: ${var.external_clickhouse.native_port}
  database: ${jsonencode(var.external_clickhouse.database)}
  cluster:
    enabled: ${var.external_clickhouse.cluster_enabled}
  auth:
    username: ${jsonencode(var.external_clickhouse.username)}
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
  migration:
    ssl: ${var.external_clickhouse.migration_ssl}
EOT

  clickhouse_values = local.deploy_clickhouse ? local.clickhouse_internal_values : local.clickhouse_external_values

  encryption_values     = var.use_encryption_key == false ? "" : <<EOT
langfuse:
  encryptionKey:
    secretKeyRef:
      name: ${kubernetes_secret_v1.langfuse.metadata[0].name}
      key: encryption-key
EOT
  additional_env_values = length(var.additional_env) == 0 ? "" : <<EOT
langfuse:
  additionalEnv:
%{for env in var.additional_env}
  - name: ${env.name}
%{if env.value != null}
    value: ${jsonencode(env.value)}
%{endif}
%{if env.valueFrom != null}
    valueFrom:
%{if env.valueFrom.secretKeyRef != null}
      secretKeyRef:
        name: ${env.valueFrom.secretKeyRef.name}
        key: ${env.valueFrom.secretKeyRef.key}
%{endif}
%{if env.valueFrom.configMapKeyRef != null}
      configMapKeyRef:
        name: ${env.valueFrom.configMapKeyRef.name}
        key: ${env.valueFrom.configMapKeyRef.key}
%{endif}
%{endif}
%{endfor}
EOT

  # Dedicated AGIC Ingress for the AI gateway so web keeps its default
  # Application Gateway timeout. Gateway streams can run up to 600s, so the
  # backend request timeout is raised to 620s and health probes check /ready.
  # Azure Managed Redis uses a publicly trusted CA (DigiCert Global Root G2 /
  # Microsoft RSA Root CA 2017, both in the UBI9 system trust store), so no
  # custom Redis CA mount is needed; chart >= 2.3 derives
  # LANGFUSE_AI_GATEWAY_REDIS_URL (rediss://) and auth from top-level redis.*.
  gateway_values = !var.enable_ai_gateway ? "" : <<EOT
langfuse:
  gateway:
    enabled: true
    ingress:
      enabled: true
      className: azure-application-gateway
      annotations:
        appgw.ingress.kubernetes.io/ssl-redirect: "true"
        appgw.ingress.kubernetes.io/appgw-ssl-certificate: ${jsonencode(local.gateway_ssl_certificate_name)}
        appgw.ingress.kubernetes.io/request-timeout: "620"
        appgw.ingress.kubernetes.io/health-probe-path: "/ready"
      hosts:
        - ${jsonencode(local.gateway_domain)}
EOT
}

resource "kubernetes_namespace_v1" "langfuse" {
  metadata {
    name = "langfuse"
  }
}

resource "random_bytes" "salt" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> SALT
  length = 32
}

resource "random_bytes" "nextauth_secret" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> NEXTAUTH_SECRET
  length = 32
}

resource "random_bytes" "encryption_key" {
  count = var.use_encryption_key ? 1 : 0
  # Must be exactly 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> ENCRYPTION_KEY
  length = 32
}

resource "kubernetes_secret_v1" "langfuse" {
  metadata {
    name      = "langfuse"
    namespace = kubernetes_namespace_v1.langfuse.metadata[0].name
  }

  data = {
    "redis-password"      = azurerm_managed_redis.this.default_database[0].primary_access_key
    "postgres-password"   = azurerm_postgresql_flexible_server.this.administrator_password
    "storage-access-key"  = azurerm_storage_account.this.primary_access_key
    "salt"                = random_bytes.salt.base64
    "nextauth-secret"     = random_bytes.nextauth_secret.base64
    "clickhouse-password" = local.deploy_clickhouse ? random_password.clickhouse_password.result : var.external_clickhouse_password
    "encryption-key"      = var.use_encryption_key ? random_bytes.encryption_key[0].hex : ""
  }
}

resource "helm_release" "langfuse" {
  name       = "langfuse"
  repository = "https://langfuse.github.io/langfuse-k8s"
  version    = var.langfuse_helm_chart_version
  chart      = "langfuse"
  namespace  = kubernetes_namespace_v1.langfuse.metadata[0].name

  values = [
    local.langfuse_values,
    local.clickhouse_values,
    local.ingress_values,
    local.encryption_values,
    local.additional_env_values,
    local.gateway_values
  ]

  depends_on = [
    kubernetes_secret_v1.langfuse,
    helm_release.clickhouse_operator,
  ]

  lifecycle {
    precondition {
      condition     = var.external_clickhouse == null || var.external_clickhouse_password != ""
      error_message = "external_clickhouse_password must be set when external_clickhouse is configured."
    }

    precondition {
      condition = !var.enable_ai_gateway ? true : (
        try(tonumber(regex("^(\\d+)\\.(\\d+)", var.langfuse_helm_chart_version)[0]), 99) > 2 ||
        (try(tonumber(regex("^(\\d+)\\.(\\d+)", var.langfuse_helm_chart_version)[0]), 99) == 2 &&
        try(tonumber(regex("^(\\d+)\\.(\\d+)", var.langfuse_helm_chart_version)[1]), 99) >= 3)
      )
      error_message = "The AI gateway needs langfuse_helm_chart_version >= 2.3, which wires Redis for spend limits into langfuse.gateway.*. Helm ignores unknown values silently, so an older chart would deploy without gateway Redis or without the gateway."
    }

    precondition {
      condition     = !var.enable_ai_gateway ? true : lower(local.gateway_domain) != lower(var.domain)
      error_message = "gateway_domain must be different from domain."
    }

    precondition {
      condition     = !var.enable_ai_gateway ? true : (endswith(lower(local.gateway_domain), ".${lower(var.domain)}") && local.gateway_dns_record_name != "")
      error_message = "gateway_domain must be a subdomain of domain, because the module creates DNS records in the Azure DNS zone for domain."
    }
  }
}
