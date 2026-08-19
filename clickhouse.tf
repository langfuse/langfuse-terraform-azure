# Random password for ClickHouse
# Using a alphanumeric password to avoid issues with special characters on bash entrypoint
resource "random_password" "clickhouse_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

locals {
  # Deploy ClickHouse into the AKS cluster unless an external one is configured
  deploy_clickhouse = var.external_clickhouse == null
}

# cert-manager issues the TLS certificates for the ClickHouse operator's
# admission webhooks. Only required while ClickHouse runs in-cluster.
resource "helm_release" "cert_manager" {
  count = local.deploy_clickhouse ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = "cert-manager"
  create_namespace = true

  values = [<<EOT
crds:
  enabled: true
EOT
  ]
}

# Official ClickHouse Kubernetes operator. The Langfuse Helm chart v2 renders
# ClickHouseCluster and KeeperCluster resources that this operator reconciles.
# Both CRD sets (cert-manager and the operator) must exist before the Langfuse
# chart is installed.
resource "helm_release" "clickhouse_operator" {
  count = local.deploy_clickhouse ? 1 : 0

  name             = "clickhouse-operator"
  repository       = "oci://ghcr.io/clickhouse"
  chart            = "clickhouse-operator-helm"
  version          = var.clickhouse_operator_chart_version
  namespace        = "clickhouse-operator-system"
  create_namespace = true

  depends_on = [helm_release.cert_manager]
}
