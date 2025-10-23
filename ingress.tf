locals {
  ingress_nginx_values = <<-EOT
controller:
  replicaCount: 2
  ingressClass: nginx
  ingressClassResource:
    default: true
  service:
    annotations:
      service.beta.kubernetes.io/azure-load-balancer-internal: "true"
      service.beta.kubernetes.io/azure-load-balancer-internal-subnet: ${azurerm_subnet.aks.name}
      service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
%{if length(trimspace(var.ingress_controller_private_ip)) > 0}
    loadBalancerIP: ${var.ingress_controller_private_ip}
%{endif}
    externalTrafficPolicy: Cluster
EOT
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    local.ingress_nginx_values
  ]

  depends_on = [
    azurerm_kubernetes_cluster.this
  ]
}

data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "${helm_release.ingress_nginx.name}-controller"
    namespace = "ingress-nginx"
  }

  wait_for_load_balancer = true

  depends_on = [
    helm_release.ingress_nginx
  ]
}
