resource "azurerm_private_dns_zone" "langfuse" {
  name                = var.domain
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "langfuse" {
  name                  = "${var.name}-langfuse"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.langfuse.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

resource "azurerm_private_dns_a_record" "langfuse" {
  name                = "@"
  zone_name           = azurerm_private_dns_zone.langfuse.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records = [
    data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
  ]

  depends_on = [
    helm_release.ingress_nginx
  ]
}
