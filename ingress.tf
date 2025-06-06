locals {
  ingress_values = <<EOT
langfuse:
  ingress:
    enabled: true
    className: azure-application-gateway
    annotations:
      appgw.ingress.kubernetes.io/ssl-redirect: "true"
      appgw.ingress.kubernetes.io/appgw-ssl-certificate: ${var.name}
    hosts:
    - host: ${var.domain}
      paths:
      - path: /
        pathType: Prefix
EOT
}

resource "azurerm_subnet" "appgw" {
  name                 = "${module.naming.subnet.name}-appgw"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.app_gateway_subnet_address_prefix]
}


resource "azurerm_network_security_group" "appgw" {
  name                = "${module.naming.network_security_group.name}-appgw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

# Allow Traffic from Infrastructure ports
resource "azurerm_network_security_rule" "appgw_management" {
  name                        = "AllowAppGwManagement"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["65200-65535"]
  source_address_prefix       = "GatewayManager"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.appgw.name
}

# Allow Traffic for Azure Load Balancer probes
resource "azurerm_network_security_rule" "appgw_loadbalancer" {
  name                        = "AllowAzureLoadBalancer"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.appgw.name
}

# Allow inbound HTTP traffic
resource "azurerm_network_security_rule" "http_inbound" {
  name                        = "AllowHttpInbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.appgw.name
}

# Allow inbound HTTPS traffic
resource "azurerm_network_security_rule" "https_inbound" {
  name                        = "AllowHttpsInbound"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.appgw.name
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

# Create User Assigned Identity for Application Gateway
resource "azurerm_user_assigned_identity" "appgw" {
  name                = "${module.naming.user_assigned_identity.name}-appgw-identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

# Grant the identity access to the Key Vault
resource "azurerm_key_vault_access_policy" "appgw" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.appgw.principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Enable Azure Application Gateway Ingress Controller
resource "azurerm_application_gateway" "this" {
  name                = module.naming.application_gateway.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = var.app_gateway_capacity
  }

  zones = [1, 2, 3]

  gateway_ip_configuration {
    name      = var.name
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  frontend_port {
    name = "https"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-configuration"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  ssl_certificate {
    name                = var.name
    key_vault_secret_id = azurerm_key_vault_certificate.this.versionless_secret_id
  }

  backend_address_pool {
    name = "backend-address-pool"
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 1
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "https"
    protocol                       = "Https"
    ssl_certificate_name           = var.name
  }

  request_routing_rule {
    name                       = "http-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-address-pool"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 1
  }

  request_routing_rule {
    name                       = "https-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "backend-address-pool"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 2
  }

  # The AppGW is later managed by the  Ingress Controller, but the Backend address
  # Pool is required to creat the resource. Therefore, "lifecycle:ignore_changes" is 
  # used to prevent TF from managing the gateway.
  lifecycle {
    ignore_changes = [
      tags,
      backend_address_pool,
      backend_http_settings,
      http_listener,
      probe,
      request_routing_rule,
      frontend_port,
    ]
  }
}

resource "azurerm_public_ip" "appgw" {
  name                = "${module.naming.public_ip.name}-appgw"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [1, 2, 3]
}
