# Deploys Langfuse against an external ClickHouse (e.g. ClickHouse Cloud)
# instead of running ClickHouse inside the AKS cluster. With an external
# ClickHouse configured, the module does not install cert-manager, the
# ClickHouse operator, or an in-cluster ClickHouse.

provider "azurerm" {
  subscription_id = "<yourAzureSubscriptionID>"
  features {}
}

variable "clickhouse_password" {
  description = "Password of the external ClickHouse user"
  type        = string
  sensitive   = true
}

module "langfuse" {
  source = "../.."

  domain = "langfuse.example.com"

  # ClickHouse Cloud connection. The defaults match ClickHouse Cloud:
  # HTTPS on port 8443 and the TLS native protocol on port 9440.
  external_clickhouse = {
    host = "https://abc123.westeurope.azure.clickhouse.cloud"

    # ClickHouse Cloud on Azure runs single-replica services without
    # ON CLUSTER DDL:
    cluster_enabled = false

    # For a self-managed ClickHouse without TLS instead:
    # host          = "clickhouse.internal.example.com"
    # http_port     = 8123
    # native_port   = 9000
    # migration_ssl = false
  }
  external_clickhouse_password = var.clickhouse_password
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
