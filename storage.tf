resource "azurerm_subnet" "storage" {
  name                 = "${module.naming.subnet.name}-storage"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.storage_subnet_address_prefix]
  service_endpoints    = ["Microsoft.Storage"]
}

# Associate NAT Gateway with storage subnet
resource "azurerm_subnet_nat_gateway_association" "storage" {
  subnet_id      = azurerm_subnet.storage.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_storage_account" "this" {
  name                            = replace(module.naming.storage_account.name_unique, "-", "")
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.storage.id]
  }
}

resource "azurerm_storage_container" "this" {
  name                  = module.naming.storage_container.name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "storage" {
  name                = "${module.naming.private_endpoint.name}-storage"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.aks.id

  private_service_connection {
    name                           = "${var.name}-storage"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
}

resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  name                  = "${var.name}-storage"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

# Add A record for the storage account's private endpoint
resource "azurerm_private_dns_a_record" "storage" {
  name                = azurerm_storage_account.this.name
  zone_name           = azurerm_private_dns_zone.storage.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address]
}
