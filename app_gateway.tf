resource "azurerm_application_gateway" "this" {
  name                = "agw-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "port_80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appGatewayFrontendIp"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name  = "langfuse-backend"
    fqdns = [azurerm_container_app.langfuse.ingress[0].fqdn]
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    # Host header is required for Container Apps
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = "listener"
    frontend_ip_configuration_name = "appGatewayFrontendIp"
    frontend_port_name             = "port_80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule1"
    rule_type                  = "Basic"
    http_listener_name         = "listener"
    backend_address_pool_name  = "langfuse-backend"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }

  tags = {
    application = local.tag_name
  }
}
