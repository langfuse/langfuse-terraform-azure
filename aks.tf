resource "azurerm_subnet" "aks" {
  name                 = "${module.naming.subnet.name}-aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

# Associate NAT Gateway with AKS subnet
resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${module.naming.user_assigned_identity.name}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = module.naming.kubernetes_cluster.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                        = "default"
    vm_size                     = var.node_pool_vm_size
    vnet_subnet_id              = azurerm_subnet.aks.id
    auto_scaling_enabled        = true
    min_count                   = var.node_pool_min_count
    max_count                   = var.node_pool_max_count
    os_disk_size_gb             = 50
    temporary_name_for_rotation = "update"
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = var.aks_dns_service_ip
    service_cidr   = var.aks_service_cidr
    outbound_type  = "userAssignedNATGateway"
  }

  ingress_application_gateway {
    # Use a manual created AppGW due to limitations of AKS managed through terraform
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/22831
    # and better control when the AGW is actually created.
    gateway_id = azurerm_application_gateway.this.id
  }
}

# Grant Network Contributor role to AGIC
resource "azurerm_role_assignment" "aks_agic_integration" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

# Grant Reader role on the resource group to AGIC
resource "azurerm_role_assignment" "aks_agic_reader" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.this.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

# Grant Contributor role on the Application Gateway to AGIC
resource "azurerm_role_assignment" "aks_agic_contributor" {
  scope                = azurerm_application_gateway.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

# Grant Managed Identity Operator to AGIC for assigning the User Assigned Identity
resource "azurerm_role_assignment" "agic_identity_operator" {
  scope                = azurerm_user_assigned_identity.appgw.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_kubernetes_cluster.this.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}


resource "azurerm_network_security_group" "aks" {
  name                = "${module.naming.network_security_group.name}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  # Allow outbound connections from AKS
  security_rule {
    name                       = "AllowOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}
