![GitHub Banner](https://github.com/langfuse/langfuse-k8s/assets/2834609/2982b65d-d0bc-4954-82ff-af8da3a4fac8)

# Azure Langfuse Terraform module

> This module is a pre-release version and its interface may change. Please review the changelog between each release and create a GitHub issue for any problems or feature requests.

This repository contains a Terraform module for deploying [Langfuse](https://langfuse.com/) - the open-source LLM observability platform - on Azure.
This module aims to provide a production-ready, secure, and scalable deployment using managed services whenever possible.

## Usage

1. Set up the module with the settings that suit your needs. A minimal installation requires a `domain` which is under your control and a `resource_group_name`. Configure the kubernetes and helm providers to connect to the AKS cluster.

```hcl
module "langfuse" {
  source = "github.com/langfuse/langfuse-terraform-azure?ref=0.4.3"

  domain              = "langfuse.example.com"
  location            = "westeurope"  # Optional: defaults to westeurope
  
  # Optional use a different name for your installation
  # e.g. when using the module multiple times on the same Azure subscription
  name = "langfuse"
  
  # Optional: Configure the Virtual Network
  virtual_network_address_prefix = "10.224.0.0/12"
  aks_subnet_address_prefix      = "10.224.0.0/16"
  db_subnet_address_prefix       = "10.226.0.0/24"
  redis_subnet_address_prefix    = "10.226.1.0/24"
  storage_subnet_address_prefix  = "10.226.2.0/24"

  # Optional: Configure the Kubernetes cluster
  kubernetes_version = "1.32"
  aks_service_cidr   = "192.168.0.0/20"
  aks_dns_service_ip = "192.168.0.10"
  node_pool_vm_size   = "Standard_D8s_v6"
  node_pool_min_count = 2
  node_pool_max_count = 10

  # Optional: Configure the internal ingress controller
  ingress_controller_private_ip = "10.224.0.240"
  ingress_nginx_chart_version   = "4.11.2"

  # Optional: Configure the database instances
  postgres_instance_count = 2
  postgres_ha_mode       = "SameZone"
  postgres_sku_name      = "GP_Standard_D2s_v3"
  postgres_storage_mb    = 32768
  
  # Optional: Configure the cache
  redis_sku_name = "Basic"
  redis_family   = "C"
  redis_capacity = 1

  # Optional: Security features
  use_encryption_key = true
  use_ddos_protection = true

  # Optional: Configure Langfuse Helm chart version
  langfuse_helm_chart_version = "1.5.7"
  
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

2. Apply the module:

```bash
terraform init
terraform apply
```

## Architecture

The module creates a complete Langfuse stack with the following Azure components:

- Resource Group for all resources
- Private virtual network with dedicated subnets for:
  - AKS cluster nodes
  - PostgreSQL database
  - Redis cache
  - Storage account
- Azure Kubernetes Service (AKS) cluster configured as a private cluster with:
  - System node pool
  - User node pool
  - Managed identities
  - Network security group on the worker subnet
- Ingress based on the `ingress-nginx` Helm chart providing:
  - An internal load balancer scoped to the AKS subnet
  - Optional static private IP assignment
  - Private DNS zone for the Langfuse endpoint
- Access to Langfuse is only available through the virtual network (for example via VNet peering); no public IPs or public DNS records are created by the module
- Azure Database for PostgreSQL Flexible Server with:
  - High availability configuration
  - Private endpoint and DNS zone linkage
  - Network security rules
- Azure Cache for Redis with private endpoint and DNS zone linkage
- Azure Storage Account (Blob) with private endpoint and DNS zone linkage
- Azure Key Vault with private endpoint storing Langfuse secrets and TLS material (the module provisions a self-signed certificate by default; supply your own by rotating the stored secrets)
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

| Name                                           | Type     |
|------------------------------------------------|----------|
| azurerm_kubernetes_cluster.this                | resource |
| helm_release.ingress_nginx                    | resource |
| helm_release.langfuse                         | resource |
| azurerm_private_dns_zone.langfuse             | resource |
| azurerm_private_dns_a_record.langfuse         | resource |
| azurerm_postgresql_flexible_server.this       | resource |
| azurerm_redis_cache.this                      | resource |
| azurerm_storage_account.this                  | resource |
| azurerm_key_vault.this                        | resource |
| azurerm_key_vault_secret.ingress_certificate  | resource |
| azurerm_key_vault_secret.ingress_private_key  | resource |
| azurerm_private_endpoint.postgres             | resource |
| azurerm_private_endpoint.redis                | resource |
| azurerm_private_endpoint.storage              | resource |
| azurerm_private_endpoint.key_vault            | resource |
| azurerm_user_assigned_identity.aks            | resource |
| azurerm_network_security_group.aks            | resource |
| tls_self_signed_cert.ingress                  | resource |
| tls_private_key.ingress                       | resource |
| azurerm_ddos_protection_plan.this             | resource |

## Inputs

| Name                           | Description                                        | Type                     | Default             | Required |
|--------------------------------|----------------------------------------------------|--------------------------|---------------------|:--------:|
| name                           | Name prefix for resources                          | string                   | "langfuse"          |    no    |
| domain                         | Domain name used for resource naming               | string                   | n/a                 |   yes    |
| location                       | Azure region to deploy resources                   | string                   | "westeurope"        |    no    |
| virtual_network_address_prefix | VNET address prefix                                | string                   | "10.224.0.0/12"     |    no    |
| aks_subnet_address_prefix      | AKS subnet address prefix                          | string                   | "10.224.0.0/16"     |    no    |
| db_subnet_address_prefix       | Database subnet address prefix                     | string                   | "10.226.0.0/24"     |    no    |
| redis_subnet_address_prefix    | Redis subnet address prefix                        | string                   | "10.226.1.0/24"     |    no    |
| storage_subnet_address_prefix  | Storage subnet address prefix                      | string                   | "10.226.2.0/24"     |    no    |
| kubernetes_version             | Kubernetes version for AKS cluster                 | string                   | "1.32"              |    no    |
| aks_service_cidr               | Network range used by Kubernetes service           | string                   | "192.168.0.0/20"    |    no    |
| aks_dns_service_ip             | IP address for cluster service discovery           | string                   | "192.168.0.10"      |    no    |
| ingress_controller_private_ip  | Optional static IP for the internal ingress LB     | string                   | ""                  |    no    |
| ingress_nginx_chart_version    | Version of the ingress-nginx Helm chart            | string                   | "4.11.2"            |    no    |
| use_encryption_key             | Whether to use encryption key for credentials      | bool                     | true                |    no    |
| node_pool_vm_size              | VM size for AKS node pool                          | string                   | "Standard_D8s_v6"   |    no    |
| node_pool_min_count            | Minimum number of nodes in AKS node pool           | number                   | 2                   |    no    |
| node_pool_max_count            | Maximum number of nodes in AKS node pool           | number                   | 10                  |    no    |
| postgres_instance_count        | Number of PostgreSQL instances                     | number                   | 2                   |    no    |
| postgres_ha_mode               | HA mode for PostgreSQL                             | string                   | "SameZone"          |    no    |
| postgres_sku_name              | SKU name for PostgreSQL                            | string                   | "GP_Standard_D2s_v3" |    no    |
| postgres_storage_mb            | Storage size in MB for PostgreSQL                  | number                   | 32768               |    no    |
| redis_sku_name                 | SKU name for Redis                                 | string                   | "Basic"             |    no    |
| redis_family                   | Cache family for Redis                             | string                   | "C"                 |    no    |
| redis_capacity                 | Capacity of Redis                                  | number                   | 1                   |    no    |
| use_ddos_protection            | Whether to use DDoS protection                     | bool                     | true                |    no    |
| langfuse_helm_chart_version    | Version of the Langfuse Helm chart to deploy       | string                   | "1.5.7"             |    no    |
| additional_env                 | Additional environment variables for Langfuse      | list(object)             | []                  |    no    |

## Outputs

| Name                       | Description                                         |
|----------------------------|-----------------------------------------------------|
| cluster_name               | The name of the AKS cluster                         |
| cluster_host               | The host of the AKS cluster                         |
| cluster_client_certificate | The client certificate for the AKS cluster          |
| cluster_client_key         | The client key for the AKS cluster                  |
| cluster_ca_certificate     | The CA certificate for the AKS cluster              |
| ingress_private_ip         | The private IP assigned to the internal ingress LB  |

## Support

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [Join Langfuse Discord](https://langfuse.com/discord)

## License

MIT Licensed. See LICENSE for full details.
