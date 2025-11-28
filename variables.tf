variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "langfuse"
}

variable "domain" {
  description = "Domain name for custom domain (optional, uses Container Apps default domain if not set)"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "westeurope"
}

variable "virtual_network_address_prefix" {
  type        = string
  description = "VNET address prefix."
  default     = "10.224.0.0/12"
}

variable "container_apps_subnet_address_prefix" {
  description = "Container Apps subnet address prefix."
  type        = string
  default     = "10.224.0.0/23"
}

variable "private_endpoints_subnet_address_prefix" {
  description = "Private Endpoints subnet address prefix (for PostgreSQL and Redis)."
  type        = string
  default     = "10.224.2.0/28"
}

variable "db_subnet_address_prefix" {
  description = "Subnet address prefix."
  type        = string
  default     = "10.226.0.0/24"
}

variable "use_encryption_key" {
  description = "Whether or not to use an Encryption key for LLM API credential and integration credential store"
  type        = bool
  default     = true
}

variable "container_app_cpu" {
  description = "CPU cores for Container App"
  type        = number
  default     = 1.0
}

variable "container_app_memory" {
  description = "Memory in Gi for Container App"
  type        = number
  default     = 2
}

variable "container_app_min_replicas" {
  description = "Minimum number of replicas for Container App"
  type        = number
  default     = 1
}

variable "container_app_max_replicas" {
  description = "Maximum number of replicas for Container App"
  type        = number
  default     = 10
}

# Worker Container App settings
variable "worker_cpu" {
  description = "CPU cores for Worker Container App"
  type        = number
  default     = 1.0
}

variable "worker_memory" {
  description = "Memory in Gi for Worker Container App"
  type        = number
  default     = 2
}

variable "worker_min_replicas" {
  description = "Minimum number of replicas for Worker Container App"
  type        = number
  default     = 1
}

variable "worker_max_replicas" {
  description = "Maximum number of replicas for Worker Container App"
  type        = number
  default     = 1
}

variable "langfuse_image_tag" {
  description = "Langfuse Docker image tag (v3+ required for worker)"
  type        = string
  default     = "3"
}

variable "postgres_instance_count" {
  description = "Number of PostgreSQL instances to create"
  type        = number
  default     = 2 # Default to 2 instances for high availability
}

variable "postgres_ha_mode" {
  description = "HA Mode to use for Postgres. Ensure this is supported in your region https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview#azure-regions"
  type        = string
  default     = "SameZone"
}

variable "postgres_sku_name" {
  description = "SKU name for Azure Database for PostgreSQL"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "postgres_storage_mb" {
  description = "Maximum storage size in MB for PostgreSQL"
  type        = number
  default     = 32768
}

variable "redis_sku_name" {
  description = "SKU name for Azure Cache for Redis. Valid values: Basic, Standard, Premium."
  type        = string
  default     = "Standard"
}

variable "redis_family" {
  description = "Redis family. C (Basic/Standard) or P (Premium)."
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  description = "Redis capacity. 0-6 for C family, 1-4 for P family."
  type        = number
  default     = 1
}

variable "use_ddos_protection" {
  description = "Wheter or not to use a DDoS protection plan"
  type        = bool
  default     = true
}

variable "additional_env" {
  description = "Additional environment variables to pass to the Langfuse deployment"
  type = list(object({
    name  = string
    value = optional(string)
    valueFrom = optional(object({
      secretKeyRef = optional(object({
        name = string
        key  = string
      }))
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for env in var.additional_env : (env.value != null) != (env.valueFrom != null)
    ])
    error_message = "Each environment variable must have either 'value' or 'valueFrom' specified, but not both."
  }
}
