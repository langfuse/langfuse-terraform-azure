<img width="2400" height="600" alt="hero-b" src="https://github.com/user-attachments/assets/b6e99f6a-eb6f-4e25-ac5e-c96759c36c54" />

# Azure Langfuse Terraform module

This repository contains a Terraform module for deploying [Langfuse](https://langfuse.com/) - the open-source LLM observability platform - on Azure.
This module aims to provide a production-ready, secure, and scalable deployment using managed services whenever possible.

## Usage

1. Set up the module with the settings that suit your needs. A minimal installation requires a `domain` which is under your control and a `resource_group_name`. Configure the kubernetes and helm providers to connect to the AKS cluster.

> [!IMPORTANT]
> The Key Vault is secured with Azure RBAC and this module creates the role assignments itself, so the identity running `terraform apply` needs `Microsoft.Authorization/roleAssignments/write` on the target scope — the built-in **Owner** or **User Access Administrator** role. Contributor alone is not sufficient.

```hcl
module "langfuse" {
  source = "github.com/langfuse/langfuse-terraform-azure?ref=1.0.1"

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
  kubernetes_version = "1.36"
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
  
  # Optional: Configure Azure Managed Redis
  redis_sku_name          = "Balanced_B3"  # Options: Balanced_B0, Balanced_B1, Balanced_B3, Balanced_B5, etc.
  redis_high_availability = true           # Disable to save cost in dev/test

  # Optional: Configure Application Gateway
  app_gateway_capacity = 1

  # Optional: Security features
  use_encryption_key = true
  use_ddos_protection = true

  # Optional: Configure Langfuse Helm chart version
  langfuse_helm_chart_version = "2.0.2"

  # Optional: Pin the Langfuse application version. Defaults to the latest
  # release at the time this module version was published.
  app_version = "4.19.0"
  
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

2. Apply the DNS zone and the AKS cluster.

```bash
terraform init
terraform apply --target module.langfuse.azurerm_dns_zone.this --target module.langfuse.azurerm_kubernetes_cluster.this
```

> [!IMPORTANT]
> **This two-stage apply is the supported installation flow, not a workaround.** The `kubernetes` and `helm` providers are configured from this module's outputs, so the AKS cluster has to exist before Terraform can plan any Kubernetes or Helm resource. The same applies when you embed this module in a larger configuration: create the cluster in a first targeted apply, or a separate pipeline stage, before applying the full stack.

3. Set up the Nameserver delegation on your DNS provider. The name servers to delegate to are available as an output:

```bash
terraform output dns_name_servers
```

4. Apply the full stack:

```bash
terraform apply
```

## Langfuse version

The module deploys the Langfuse Helm chart v2 (`langfuse_helm_chart_version`), which ships [Langfuse v4](https://langfuse.com/docs/v4). The Langfuse application version is pinned explicitly through the `app_version` variable, which defaults to the latest Langfuse release at the time the module version was published. To upgrade Langfuse, set `app_version` to a newer [release](https://github.com/langfuse/langfuse/releases):

```hcl
module "langfuse" {
  # ...
  app_version = "4.19.0"
}
```

## ClickHouse

By default the Langfuse Helm chart v2 deploys a ClickHouse cluster into the AKS cluster through the official [ClickHouse Kubernetes operator](https://github.com/ClickHouse/clickhouse-operator) (`ClickHouseCluster` and `KeeperCluster` resources). To support this, the module installs:

- [cert-manager](https://cert-manager.io/) (required by the operator to issue its admission webhook certificates)
- The ClickHouse operator (`oci://ghcr.io/clickhouse/clickhouse-operator-helm`)

The deployment can be sized with the `clickhouse_replicas`, `clickhouse_resources`, `clickhouse_storage_size`, `clickhouse_storage_class`, `clickhouse_keeper_replicas`, and `clickhouse_keeper_storage_size` variables.

### External ClickHouse (bring your own)

To use an existing ClickHouse instead — for example [ClickHouse Cloud](https://clickhouse.com/cloud) — set `external_clickhouse`. The module then skips cert-manager, the operator, and the in-cluster ClickHouse entirely. See [examples/external-clickhouse](examples/external-clickhouse/external-clickhouse.tf) for a full example.

```hcl
module "langfuse" {
  source = "github.com/langfuse/langfuse-terraform-azure"

  domain = "langfuse.example.com"

  external_clickhouse = {
    host = "https://abc123.westeurope.azure.clickhouse.cloud"
    # Defaults: http_port = 8443, native_port = 9440, username = "default",
    # database = "default", cluster_enabled = true, migration_ssl = true

    # ClickHouse Cloud on Azure runs without ON CLUSTER DDL:
    cluster_enabled = false
  }
  external_clickhouse_password = var.clickhouse_password
}
```

Set `cluster_enabled = false` for ClickHouse Cloud on Azure or for single-node deployments. Make sure the AKS cluster can reach the external ClickHouse (for ClickHouse Cloud, check the IP allowlist or use Private Link).

## Upgrading from 0.4.x to 1.x

`1.x` is a **clean Langfuse v4 installation on Helm chart v2**. It does not migrate an existing deployment for you, and it changes infrastructure that already exists. New installations can skip this section.

**Migrate the Langfuse deployment yourself first.** `0.4.x` ran Langfuse v3 on the Bitnami-based Helm chart v1, where ClickHouse (and ZooKeeper) were Bitnami subcharts. The operator-managed ClickHouse in chart v2 starts empty, and the chart deliberately refuses an in-place `helm upgrade` that would replace leftover Bitnami volumes:

1. Migrate the chart deployment, copying the ClickHouse data, following the [chart v1 → v2 migration guide](https://github.com/langfuse/langfuse-k8s/tree/main/examples/upgrade-v1-to-v2).
2. Upgrade the application following the [Langfuse v3 → v4 upgrade guide](https://langfuse.com/self-hosting/upgrade/upgrade-guides/upgrade-v3-to-v4).

**Then expect these changes when you switch the module version:**

| Change                                                                                                                                                                                  | What it means for you                                                                                                                                                                               |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Azure Cache for Redis is replaced by Azure Managed Redis. `redis_family` and `redis_capacity` are **removed**, and `redis_sku_name` now takes Managed Redis SKUs such as `Balanced_B3`. | Update your module block, using `redis_high_availability` in place of the old capacity settings. The cache itself is **recreated**, so anything queued in Redis is lost — drain the workers first.  |
| The Key Vault is secured with Azure RBAC instead of access policies.                                                                                                                    | Access policies no longer apply, and the identity running `terraform apply` needs **Owner** or **User Access Administrator**.                                                                       |
| The `azurerm` provider requirement moves to `~> 5.0`.                                                                                                                                   | Private DNS zone links and A records changed arguments in azurerm 5. Check the plan: if they are reported as replacements, private endpoint name resolution drops briefly while they are recreated. |
| Terraform `>= 1.3` and the `helm` provider `>= 2.7` are required.                                                                                                                       | Run `terraform init -upgrade`.                                                                                                                                                                      |
| cert-manager and the ClickHouse operator are installed as new releases.                                                                                                                 | Additive prerequisites of chart v2.                                                                                                                                                                 |

**Read the plan before you apply**, and treat anything reported as *must be replaced* or *will be destroyed* as a stop sign. If you are not ready for any of this, pin the module to `0.4.x`.

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
- Azure Managed Redis with:
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
| terraform  | >= 1.3  |
| azurerm    | >= 5.0  |
| kubernetes | >= 2.10 |
| helm       | >= 2.7  |

## Providers

| Name       | Version |
|------------|---------|
| azurerm    | >= 5.0  |
| kubernetes | >= 2.10 |
| helm       | >= 2.7  |
| random     | >= 3.0  |
| tls        | >= 3.0  |
| time       | >= 0.9  |

## Resources

| Name                                    | Type     |
|-----------------------------------------|----------|
| azurerm_kubernetes_cluster.this         | resource |
| azurerm_postgresql_flexible_server.this | resource |
| azurerm_managed_redis.this              | resource |
| azurerm_storage_account.this            | resource |
| azurerm_key_vault_certificate.this      | resource |
| azurerm_dns_zone.this                   | resource |
| azurerm_user_assigned_identity.aks      | resource |
| azurerm_network_security_group.this     | resource |
| azurerm_application_gateway.this        | resource |
| azurerm_private_endpoint.this           | resource |
| azurerm_ddos_protection_plan.this       | resource |
| helm_release.cert_manager               | resource |
| helm_release.clickhouse_operator        | resource |
| helm_release.langfuse                   | resource |

## Inputs

| Name                              | Description                                                                                                                                              | Type   | Default                       | Required |
|-----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|--------|-------------------------------|:--------:|
| name                              | Name prefix for resources                                                                                                                                | string | "langfuse"                    |    no    |
| domain                            | Domain name used for resource naming                                                                                                                     | string | n/a                           |   yes    |
| location                          | Azure region to deploy resources                                                                                                                         | string | "westeurope"                  |    no    |
| virtual_network_address_prefix    | VNET address prefix                                                                                                                                      | string | "10.224.0.0/12"               |    no    |
| aks_subnet_address_prefix         | AKS subnet address prefix                                                                                                                                | string | "10.224.0.0/16"               |    no    |
| app_gateway_subnet_address_prefix | Application Gateway subnet address prefix                                                                                                                | string | "10.225.0.0/16"               |    no    |
| db_subnet_address_prefix          | Database subnet address prefix                                                                                                                           | string | "10.226.0.0/24"               |    no    |
| redis_subnet_address_prefix       | Redis subnet address prefix                                                                                                                              | string | "10.226.1.0/24"               |    no    |
| storage_subnet_address_prefix     | Storage subnet address prefix                                                                                                                            | string | "10.226.2.0/24"               |    no    |
| kubernetes_version                | Kubernetes version for AKS cluster                                                                                                                       | string | "1.36"                        |    no    |
| aks_service_cidr                  | Network range used by Kubernetes service                                                                                                                 | string | "192.168.0.0/20"              |    no    |
| aks_dns_service_ip                | IP address for cluster service discovery                                                                                                                 | string | "192.168.0.10"                |    no    |
| use_encryption_key                | Whether to use encryption key for credentials                                                                                                            | bool   | true                          |    no    |
| node_pool_vm_size                 | VM size for AKS node pool                                                                                                                                | string | "Standard_D2s_v6"             |    no    |
| node_pool_min_count               | Minimum number of nodes in AKS node pool                                                                                                                 | number | 2                             |    no    |
| node_pool_max_count               | Maximum number of nodes in AKS node pool                                                                                                                 | number | 10                            |    no    |
| postgres_instance_count           | Number of PostgreSQL instances                                                                                                                           | number | 2                             |    no    |
| postgres_ha_mode                  | HA mode for PostgreSQL                                                                                                                                   | string | "SameZone"                    |    no    |
| postgres_sku_name                 | SKU name for PostgreSQL                                                                                                                                  | string | "GP_Standard_D2s_v3"          |    no    |
| postgres_storage_mb               | Storage size in MB for PostgreSQL                                                                                                                        | number | 32768                         |    no    |
| redis_sku_name                    | SKU name for Azure Managed Redis                                                                                                                         | string | "Balanced_B3"                 |    no    |
| redis_high_availability           | Enable high availability for Redis                                                                                                                       | bool   | true                          |    no    |
| app_gateway_capacity              | Capacity for Application Gateway                                                                                                                         | number | 1                             |    no    |
| use_ddos_protection               | Whether to use DDoS protection                                                                                                                           | bool   | true                          |    no    |
| clickhouse_replicas               | Number of in-cluster ClickHouse replicas                                                                                                                 | number | 3                             |    no    |
| clickhouse_keeper_replicas        | Number of ClickHouse Keeper replicas (1, 3 or 5)                                                                                                         | number | 3                             |    no    |
| clickhouse_storage_size           | Persistent volume size per ClickHouse replica                                                                                                            | string | "100Gi"                       |    no    |
| clickhouse_keeper_storage_size    | Persistent volume size per Keeper replica                                                                                                                | string | "10Gi"                        |    no    |
| clickhouse_storage_class          | StorageClass for ClickHouse and Keeper volumes                                                                                                           | string | "managed-csi-premium"         |    no    |
| clickhouse_resources              | Resource requests and limits per ClickHouse replica                                                                                                      | object | { cpu = "2", memory = "8Gi" } |    no    |
| clickhouse_operator_chart_version | Version of the ClickHouse operator Helm chart                                                                                                            | string | "0.0.5"                       |    no    |
| cert_manager_chart_version        | Version of the cert-manager Helm chart                                                                                                                   | string | "v1.20.2"                     |    no    |
| external_clickhouse               | Use an external ClickHouse (e.g. ClickHouse Cloud) instead of the in-cluster deployment. See [External ClickHouse](#external-clickhouse-bring-your-own). | object | null                          |    no    |
| external_clickhouse_password      | Password for the external ClickHouse user                                                                                                                | string | ""                            |    no    |
| langfuse_helm_chart_version       | Version of the Langfuse Helm chart to deploy                                                                                                             | string | "2.0.2"                       |    no    |
| app_version                       | Langfuse application version (Docker image tag) to deploy. Defaults to the latest release at the time this module version was published.                 | string | "4.19.0"                      |    no    |
| additional_env                    | Additional environment variables for Langfuse                                                                                                            | list   | []                            |    no    |

## Outputs

| Name                       | Description                                            |
|----------------------------|--------------------------------------------------------|
| cluster_name               | The name of the AKS cluster                            |
| cluster_host               | The host of the AKS cluster                            |
| cluster_client_certificate | The client certificate for the AKS cluster             |
| cluster_client_key         | The client key for the AKS cluster                     |
| cluster_ca_certificate     | The CA certificate for the AKS cluster                 |
| dns_name_servers           | Name servers of the DNS zone, for the delegation step  |

## Support

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [Join Langfuse Discord](https://langfuse.com/discord)

## License

MIT Licensed. See LICENSE for full details.
