provider "azurerm" {
  subscription_id = "<yourAzureSubscriptionID>"
  features {}
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

module "langfuse" {
  source = "../.."

  domain   = "langfuse.example.com"
  location = "westeurope" # Optional: defaults to westeurope

  # Optional: use a different name for your installation
  # e.g. when using the module multiple times on the same Azure subscription
  name = "langfuse"

  # Optional: Configure langfuse
  use_encryption_key = true

  # Optional: Configure the Virtual Network
  virtual_network_address_prefix    = "10.224.0.0/12"
  aks_subnet_address_prefix         = "10.224.0.0/16"
  app_gateway_subnet_address_prefix = "10.225.0.0/16"
  db_subnet_address_prefix          = "10.226.0.0/24"
  redis_subnet_address_prefix       = "10.226.1.0/24"
  storage_subnet_address_prefix     = "10.226.2.0/24"

  # Optional: Configure the Kubernetes cluster
  kubernetes_version  = "1.32"
  aks_service_cidr    = "192.168.0.0/20"
  aks_dns_service_ip  = "192.168.0.10"
  node_pool_vm_size   = "Standard_D8s_v6"
  node_pool_min_count = 2
  node_pool_max_count = 10

  # Optional: Configure the database instances
  postgres_instance_count = 2
  postgres_ha_mode        = "SameZone"
  postgres_sku_name       = "GP_Standard_D2s_v3"
  postgres_storage_mb     = 32768

  # Optional: Configure the cache
  redis_sku_name = "Basic"
  redis_family   = "C"
  redis_capacity = 1

  # Optional: Configure Application Gateway
  app_gateway_capacity = 1

  # Optional: Security features
  use_ddos_protection = true

  # Optional: Configure Langfuse Helm chart version
  langfuse_helm_chart_version = "1.3.3"
}
