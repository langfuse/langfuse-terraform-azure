![GitHub Banner](https://github.com/langfuse/langfuse-k8s/assets/2834609/2982b65d-d0bc-4954-82ff-af8da3a4fac8)

# Azure Langfuse Terraform Module (Container Apps)

> **Note**: This is the Container Apps version. For production deployments, this provides a simpler, more cost-effective alternative to AKS.

This repository contains a Terraform configuration for deploying [Langfuse](https://langfuse.com/) - the open-source LLM observability platform - on Azure using **Azure Container Apps**.

## Features

- ✅ **Serverless**: Azure Container Apps with auto-scaling
- ✅ **Cost-effective**: 25-50% cheaper than AKS-based deployment (dev: $41-77/mo, can be optimized to $22-36/mo)
- ✅ **Fully managed**: PostgreSQL, Redis, Storage, Log Analytics
- ✅ **Secure**: Private Endpoints for databases and cache
- ✅ **Simple**: No Kubernetes/Helm knowledge required
- ✅ **Fast deployment**: 10-18 minutes vs 20-30 minutes for AKS
- ✅ **Persistent storage**: ClickHouse data persists across restarts with Azure File Share

## Architecture

```
Internet
    ↓
Container Apps (Langfuse + ClickHouse sidecar)
    ↓ Private Endpoints
PostgreSQL + Redis + Storage (Blob + File Share)
```

**Components**:
- **Langfuse**: Main application container
- **ClickHouse**: Analytics database (sidecar container with persistent Azure File Share)
- **PostgreSQL**: Primary database with Private Endpoint
- **Redis**: Caching layer with Private Endpoint
- **Storage**: Blob storage for uploads + File Share for ClickHouse data

## Quick Start

### Prerequisites

- Azure CLI installed and authenticated
- Terraform >= 1.0
- Azure subscription

### Minimal Setup (Development/Test)

Create a `main.tf`:

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Use the module directly
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
  suffix  = ["langfuse"]
}

# Include all resources from this repository
# (Clone this repo and reference it locally, or use remote source)
```

**Or use it standalone** (simpler for getting started):

```bash
# Clone the repository
git clone https://github.com/langfuse/langfuse-terraform-azure.git
cd langfuse-terraform-azure

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
location = "japaneast"
name     = "langfuse-dev"

# Optional: Set domain if you want custom domain
# domain = "langfuse.example.com"

# Development environment settings (cost-optimized)
container_app_cpu          = 0.5
container_app_memory       = 1
container_app_min_replicas = 0  # Scale to zero
container_app_max_replicas = 3

postgres_instance_count = 1      # No HA
postgres_sku_name      = "B_Standard_B1ms"
postgres_storage_mb    = 32768

redis_sku_name = "Balanced_B0"

use_ddos_protection = false
EOF

# Deploy
terraform init
terraform apply
```

### After Deployment

Get the Container App URL:

```bash
terraform output container_app_url
```

Access Langfuse:
```
https://<container-app-fqdn>
```

If you didn't set a domain, you'll get a default Container Apps URL like:
```
https://langfuse.xxxxx.japaneast.azurecontainerapps.io
```

### Initial Admin User

Langfuse automatically creates an initial admin user on first deployment:

- **Email**: `admin@example.com` (configurable via `LANGFUSE_INIT_USER_EMAIL`)
- **Name**: `Admin User` (configurable via `LANGFUSE_INIT_USER_NAME`)
- **Password**: Randomly generated 32-character password

To retrieve the admin password:

```bash
# View the password (stored in Terraform state)
terraform output -raw langfuse_admin_password
```

> **Note**: For production deployments, change the default email address by setting `LANGFUSE_INIT_USER_EMAIL` in the `additional_env` variable, or change the password immediately after first login.

## Configuration Options

### Required Variables

| Name | Description | Default |
|------|-------------|---------|
| `location` | Azure region | `"westeurope"` |

### Optional Variables

#### Basic Settings

| Name | Description | Default |
|------|-------------|---------|
| `name` | Resource name prefix | `"langfuse"` |
| `domain` | Custom domain (optional) | `null` |

#### Container Apps

| Name | Description | Default |
|------|-------------|---------|
| `container_app_cpu` | CPU cores | `1.0` |
| `container_app_memory` | Memory in Gi | `2` |
| `container_app_min_replicas` | Min replicas | `1` |
| `container_app_max_replicas` | Max replicas | `10` |
| `langfuse_image_tag` | Docker image tag | `"2"` |

#### Database

| Name | Description | Default |
|------|-------------|---------|
| `postgres_instance_count` | Number of instances (1=no HA, 2=HA) | `2` |
| `postgres_sku_name` | PostgreSQL SKU | `"GP_Standard_D2s_v3"` |
| `postgres_storage_mb` | Storage in MB | `32768` |

#### Cache

| Name | Description | Default |
|------|-------------|---------|
| `redis_sku_name` | Azure Managed Redis SKU | `"Balanced_B0"` |

#### Security

| Name | Description | Default |
|------|-------------|---------|
| `use_encryption_key` | Use encryption key | `true` |
| `use_ddos_protection` | Use DDoS protection | `true` |

## Cost Estimates

### Development Environment (Current Configuration)

```hcl
# terraform.tfvars
location = "japaneast"
name     = "langfuse-dev"

container_app_cpu          = 0.5
container_app_memory       = 1
container_app_min_replicas = 0  # Scale to zero
container_app_max_replicas = 3

postgres_instance_count = 1  # No HA
postgres_sku_name      = "B_Standard_B1ms"
postgres_storage_mb    = 32768

redis_sku_name = "Balanced_B0"

use_ddos_protection = false
```

**Monthly cost**: $41-77

**Optimizations applied**:
- ✅ NAT Gateway removed
- ✅ DNS Zone removed (using Container Apps default domain)
- ✅ Key Vault removed
- ✅ Storage Private Endpoint removed
- ✅ Storage using LRS (instead of GRS)
- ✅ ClickHouse with persistent storage (Azure File Share 50GB)

See [COST_OPTIMIZATION.md](./COST_OPTIMIZATION.md) for further cost reduction options (down to $22-36/month).

### Production Environment

```hcl
# terraform.tfvars
location = "japaneast"
name     = "langfuse-prod"

container_app_cpu          = 2.0
container_app_memory       = 4
container_app_min_replicas = 2
container_app_max_replicas = 20

postgres_instance_count = 2  # HA enabled
postgres_sku_name      = "GP_Standard_D4s_v3"
postgres_storage_mb    = 131072

redis_sku_name = "Balanced_B1"

use_ddos_protection = false
```

**Monthly cost**: $242-504

**Note**: Production deployments may need NAT Gateway (+$30), DNS Zone (+$0.50), and Key Vault (+$0.03) depending on requirements.

## Outputs

| Name | Description |
|------|-------------|
| `container_app_fqdn` | Container App FQDN |
| `container_app_url` | Container App URL (with https) |
| `log_analytics_workspace_id` | Log Analytics Workspace ID |
| `postgres_server_name` | PostgreSQL server name |
| `redis_host` | Redis hostname |
| `storage_account_name` | Storage account name |

## Custom Domain Setup (Optional)

If you want to use a custom domain:

1. Set the `domain` variable in `terraform.tfvars`:
   ```hcl
   domain = "langfuse.example.com"
   ```

2. After deployment, configure your DNS:
   - Point your domain to the Container App FQDN (CNAME record)
   - Or use the output `container_app_fqdn` value

3. Add custom domain in Azure Portal:
   - Navigate to Container App → Custom domains
   - Add your domain and certificate

## Network Configuration

Default network settings:

| Subnet | CIDR | Purpose |
|--------|------|---------|
| Container Apps | `10.224.0.0/23` | Container Apps infrastructure |
| Database | `10.226.0.0/24` | PostgreSQL |

All resources are deployed in the same region for zero data transfer costs.

## Monitoring

Access logs via:

```bash
az containerapp logs show \
  --name langfuse \
  --resource-group <resource-group-name> \
  --follow
```

Or use Log Analytics in Azure Portal.

## Upgrading Langfuse

Update the image tag:

```hcl
langfuse_image_tag = "2.x.x"
```

Then apply:

```bash
terraform apply
```

## Security Considerations

### Development/Test Environment
- ✅ Private Endpoints for PostgreSQL and Redis
- ⚠️ Public access to Storage (with firewall rules)
- ⚠️ No custom domain/SSL (uses Container Apps managed certificate)

### Production Environment Recommendations
- ✅ All Private Endpoints
- ✅ Custom domain with managed certificate
- ✅ DDoS Protection
- ✅ PostgreSQL HA enabled
- ✅ Redis Standard tier or higher

## Troubleshooting

### Container App won't start

Check logs:
```bash
az containerapp logs show --name langfuse --resource-group <rg-name>
```

### Database connection errors

Verify Private Endpoint:
```bash
az network private-endpoint list --resource-group <rg-name> --output table
```

### High costs

Check actual usage:
```bash
az consumption usage list --start-date 2025-11-01 --end-date 2025-11-30
```

## Documentation

- [Setup Guide](./SETUP_GUIDE.md) - Step-by-step from Azure account creation
- [Cost Optimization Guide](./COST_OPTIMIZATION.md) - Ways to reduce costs
- [Migration Guide](./MIGRATION_TO_CONTAINER_APPS.md) - AKS to Container Apps migration

## Comparison: Container Apps vs AKS

| Feature | Container Apps (Current) | AKS (Previous) |
|---------|-------------------------|----------------|
| **Deployment Time** | 10-18 min | 20-30 min |
| **Cost (Dev)** | $39-75/mo* | $53-117/mo |
| **Cost (Prod)** | $242-504/mo | $275-704/mo |
| **Complexity** | Low | High |
| **Kubernetes Knowledge** | Not required | Required |
| **Auto-scaling** | Built-in | Manual setup |
| **Monitoring** | Built-in | Manual setup |

\* Can be further reduced to $20-34/mo with additional optimizations (see [COST_OPTIMIZATION.md](./COST_OPTIMIZATION.md))

## Support

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [Join Langfuse Discord](https://langfuse.com/discord)
- [Report Issues](https://github.com/langfuse/langfuse-terraform-azure/issues)

## License

MIT License - See LICENSE for details

## Contributing

Contributions are welcome! Please open an issue or PR.

## Changelog

### v2.2.0 - ClickHouse Persistent Storage & Admin User (2025-11-16)
- Added persistent storage for ClickHouse data using Azure File Share (50GB)
- ClickHouse data now persists across container restarts
- Added automatic initial admin user creation with configurable credentials
- Added LANGFUSE_INIT_USER_* environment variables for headless setup
- Development environment cost: $41-77/mo (+$2/mo for File Share)

### v2.1.0 - Development Environment Optimization (2025-11-15)
- Removed NAT Gateway for cost reduction
- Removed DNS Zone (using Container Apps default domain)
- Removed Key Vault (no custom domain)
- Removed Storage Private Endpoint
- Changed Storage to LRS (from GRS)
- Development environment cost: $39-75/mo (25-50% reduction from initial Container Apps version)

### v2.0.0 - Container Apps Migration (2025-11-13)
- Migrated from AKS to Azure Container Apps
- Removed Kubernetes/Helm dependencies
- Simplified architecture
- 25-50% cost reduction vs AKS
- Faster deployment times (10-18 min vs 20-30 min)

### v0.4.4 - Last AKS version
- AKS-based deployment (deprecated)
