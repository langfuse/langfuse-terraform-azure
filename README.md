![GitHub Banner](https://github.com/langfuse/langfuse-k8s/assets/2834609/2982b65d-d0bc-4954-82ff-af8da3a4fac8)

# Azure Langfuse Terraform module

> This module is a pre-release version and its interface may change. Please review the changelog between each release and create a GitHub issue for any problems or feature requests.

This repository contains a Terraform module for deploying [Langfuse](https://langfuse.com/) - the open-source LLM observability platform - on Azure.
This module aims to provide a production-ready, secure, and scalable deployment using managed services whenever possible.

## Usage

1. Set up the module with the settings that suit your needs. A minimal installation requires a `domain` which is under your control and a `resource_group_name`. Configure the kubernetes and helm providers to connect to the AKS cluster.

```hcl
module "langfuse" {
  source = "github.com/langfuse/langfuse-terraform-azure?ref=0.3.0"

  domain              = "langfuse.example.com"
  location            = "westeurope"  # Optional: defaults to westeurope
  
  # Optional use a different name for your installation
  # e.g. when using the module multiple times on the same Azure subscription
  name = "langfuse"
  
  # Optional: Configure the Virtual Network
  virtual_network_address_prefix = "10.224.0.0/12"
  aks_subnet_address_prefix     = "10.224.0.0/16"
  app_gateway_subnet_address_prefix = "10.225.0.0/16"
  db_subnet_address_prefix      = "10.226.0.0/24"
  redis_subnet_address_prefix   = "10.226.1.0/24"
  storage_subnet_address_prefix = "10.226.2.0/24"

  # Optional: Configure the Kubernetes cluster
  kubernetes_version = "1.32"
  aks_service_cidr   = "192.168.0.0/20"
  aks_dns_service_ip = "192.168.0.10"
  node_pool_vm_size  = "Standard_D8s_v6"
  node_pool_min_count = 2
  node_pool_max_count = 10

  # Optional: Configure the database instances
  postgres_instance_count = 2
  postgres_ha_mode       = "SameZone"
  postgres_sku_name      = "GP_Standard_D2s_v3"
  postgres_storage_mb    = 32768
  
  # Optional: Configure the cache
  redis_sku_name = "Basic"
  redis_family   = "C"
  redis_capacity = 1

  # Optional: Configure Application Gateway
  app_gateway_capacity = 1

  # Optional: Security features
  use_encryption_key = true
  use_ddos_protection = true

  # Optional: Configure Langfuse Helm chart version
  langfuse_helm_chart_version = "1.3.3"
  
  # Optional: Add additional environment variables
  additional_env = [
    {
      name  = "CUSTOM_ENV_VAR"
      value = "custom-value"
    },
    {
      name = "DATABASE_PASSWORD"
      valueFrom = {
        secretKeyRef = {
          name = "my-database-secret"
          key  = "password"
        }
      }
    },
    {
      name = "CONFIG_VALUE"
      valueFrom = {
        configMapKeyRef = {
          name = "my-config-map"
          key  = "config-key"
        }
      }
    }
  ]
}

provider "kubernetes" {
  host                   = module.langfuse.cluster_host
  client_certificate     = base64decode(module.langfuse.cluster_client_certificate)
  client_key             = base64decode(module.langfuse.cluster_client_key)
  cluster_ca_certificate = base64decode(module.langfuse.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = module.langfuse.cluster_host
    client_certificate     = base64decode(module.langfuse.cluster_client_certificate)
    client_key             = base64decode(module.langfuse.cluster_client_key)
    cluster_ca_certificate = base64decode(module.langfuse.cluster_ca_certificate)
  }
}
```

2. Apply the DNS zone

```bash
terraform init
terraform apply --target module.langfuse.azurerm_dns_zone.this
```

3. Set up the Nameserver delegation on your DNS provider, likely using (check on your created DNS zone):

```bash
ns1-05.azure-dns.com.
ns2-05.azure-dns.net.
ns3-05.azure-dns.org.
ns4-05.azure-dns.info.
```

4. Apply the full stack:

```bash
terraform apply
```

## Architecture

The module creates a complete Langfuse stack with the following Azure components:

- Resource Group for all resources
- Virtual Network with dedicated subnets for:
  - AKS cluster
  - Application Gateway
  - PostgreSQL database
  - Redis cache
  - Storage account
- Azure Kubernetes Service (AKS) cluster with:
  - System node pool
  - User node pool
  - Managed identities
  - Network security groups
- Azure Database for PostgreSQL Flexible Server with:
  - High availability configuration
  - Private endpoint
  - Network security rules
- Azure Cache for Redis with:
  - Private endpoint
  - Network security rules
- Azure Storage Account with:
  - Blob storage
  - Private endpoint
  - Network security rules
- Azure DNS Zone and Key Vault for TLS certificates
- Azure Application Gateway for ingress with:
  - Web Application Firewall (WAF)
  - SSL termination
  - Private endpoint
- Azure Files CSI Driver for persistent storage
- Optional DDoS Protection Plan
- Optional encryption key for LLM API credentials

## Requirements

| Name       | Version |
|------------|---------|
| terraform  | >= 1.0  |
| azurerm    | >= 3.0  |
| kubernetes | >= 2.10 |
| helm       | >= 2.5  |

## Providers

| Name       | Version |
|------------|---------|
| azurerm    | >= 3.0  |
| kubernetes | >= 2.10 |
| helm       | >= 2.5  |
| random     | >= 3.0  |
| tls        | >= 3.0  |

## Resources

| Name                                    | Type     |
|-----------------------------------------|----------|
| azurerm_kubernetes_cluster.this         | resource |
| azurerm_postgresql_flexible_server.this | resource |
| azurerm_redis_cache.this                | resource |
| azurerm_storage_account.this            | resource |
| azurerm_key_vault_certificate.this      | resource |
| azurerm_dns_zone.this                   | resource |
| azurerm_user_assigned_identity.aks      | resource |
| azurerm_network_security_group.this     | resource |
| azurerm_application_gateway.this        | resource |
| azurerm_private_endpoint.this           | resource |
| azurerm_ddos_protection_plan.this       | resource |

## Inputs

| Name                              | Description                                   | Type   | Default              | Required |
|-----------------------------------|-----------------------------------------------|--------|----------------------|:--------:|
| name                              | Name prefix for resources                     | string | "langfuse"           |    no    |
| domain                            | Domain name used for resource naming          | string | n/a                  |   yes    |
| location                          | Azure region to deploy resources              | string | "westeurope"         |    no    |
| virtual_network_address_prefix    | VNET address prefix                           | string | "10.224.0.0/12"      |    no    |
| aks_subnet_address_prefix         | AKS subnet address prefix                     | string | "10.224.0.0/16"      |    no    |
| app_gateway_subnet_address_prefix | Application Gateway subnet address prefix     | string | "10.225.0.0/16"      |    no    |
| db_subnet_address_prefix          | Database subnet address prefix                | string | "10.226.0.0/24"      |    no    |
| redis_subnet_address_prefix       | Redis subnet address prefix                   | string | "10.226.1.0/24"      |    no    |
| storage_subnet_address_prefix     | Storage subnet address prefix                 | string | "10.226.2.0/24"      |    no    |
| kubernetes_version                | Kubernetes version for AKS cluster            | string | "1.32"               |    no    |
| aks_service_cidr                  | Network range used by Kubernetes service      | string | "192.168.0.0/20"     |    no    |
| aks_dns_service_ip                | IP address for cluster service discovery      | string | "192.168.0.10"       |    no    |
| use_encryption_key                | Whether to use encryption key for credentials | bool   | true                 |    no    |
| node_pool_vm_size                 | VM size for AKS node pool                     | string | "Standard_D2s_v6"    |    no    |
| node_pool_min_count               | Minimum number of nodes in AKS node pool      | number | 2                    |    no    |
| node_pool_max_count               | Maximum number of nodes in AKS node pool      | number | 10                   |    no    |
| postgres_instance_count           | Number of PostgreSQL instances                | number | 2                    |    no    |
| postgres_ha_mode                  | HA mode for PostgreSQL                        | string | "SameZone"           |    no    |
| postgres_sku_name                 | SKU name for PostgreSQL                       | string | "GP_Standard_D2s_v3" |    no    |
| postgres_storage_mb               | Storage size in MB for PostgreSQL             | number | 32768                |    no    |
| redis_sku_name                    | SKU name for Redis                            | string | "Basic"              |    no    |
| redis_family                      | Cache family for Redis                        | string | "C"                  |    no    |
| redis_capacity                    | Capacity of Redis                             | number | 1                    |    no    |
| app_gateway_capacity              | Capacity for Application Gateway              | number | 1                    |    no    |
| use_ddos_protection               | Whether to use DDoS protection                | bool   | true                 |    no    |
| langfuse_helm_chart_version       | Version of the Langfuse Helm chart to deploy  | string | "1.3.3"              |    no    |
| additional_env                    | Additional environment variables for Langfuse | list   | []                   |    no    |

## Outputs

| Name                       | Description                                         |
|----------------------------|-----------------------------------------------------|
| cluster_name               | The name of the AKS cluster                         |
| cluster_host               | The host of the AKS cluster                         |
| cluster_client_certificate | The client certificate for the AKS cluster          |
| cluster_client_key         | The client key for the AKS cluster                  |
| cluster_ca_certificate     | The CA certificate for the AKS cluster              |
| postgres_server_name       | The name of the PostgreSQL server                   |
| postgres_server_fqdn       | The FQDN of the PostgreSQL server                   |
| postgres_admin_username    | The administrator username of the PostgreSQL server |
| postgres_admin_password    | The administrator password of the PostgreSQL server |
| redis_host                 | The hostname of the Redis instance                  |
| redis_ssl_port             | The SSL port of the Redis instance                  |
| redis_primary_key          | The primary access key for the Redis instance       |
| storage_account_name       | The name of the storage account                     |
| storage_account_key        | The primary access key for the storage account      |
| dns_name_servers           | The name servers for the DNS zone                   |

## Support

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [Join Langfuse Discord](https://langfuse.com/discord)

## License

MIT Licensed. See LICENSE for full details.
