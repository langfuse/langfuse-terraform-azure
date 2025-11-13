output "container_app_fqdn" {
  description = "The FQDN of the Container App"
  value       = azurerm_container_app.langfuse.ingress[0].fqdn
}

output "container_app_url" {
  description = "The URL of the Container App"
  value       = "https://${azurerm_container_app.langfuse.ingress[0].fqdn}"
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.id
}

output "postgres_server_name" {
  description = "The name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.this.name
}

output "postgres_server_fqdn" {
  description = "The FQDN of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "postgres_admin_username" {
  description = "The administrator username of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.this.administrator_login
  sensitive   = true
}

output "postgres_admin_password" {
  description = "The administrator password of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.this.administrator_password
  sensitive   = true
}

output "redis_host" {
  description = "The hostname of the Redis instance"
  value       = azurerm_redis_cache.this.hostname
}

output "redis_ssl_port" {
  description = "The SSL port of the Redis instance"
  value       = azurerm_redis_cache.this.ssl_port
}

output "redis_primary_key" {
  description = "The primary access key for the Redis instance"
  value       = azurerm_redis_cache.this.primary_access_key
  sensitive   = true
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.this.name
}

output "storage_account_key" {
  description = "The primary access key for the storage account"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "dns_name_servers" {
  description = "The name servers for the DNS zone"
  value       = azurerm_dns_zone.this.name_servers
}
