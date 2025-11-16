resource "azurerm_storage_account" "this" {
  name                            = replace(module.naming.storage_account.name_unique, "-", "")
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"  # Changed from GRS to LRS for cost savings
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = true  # Enable public access for dev environment
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action             = "Allow"  # Allow access from Container Apps
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.container_apps.id]
  }
}

resource "azurerm_storage_container" "this" {
  name                  = module.naming.storage_container.name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Azure File Share for ClickHouse persistent storage
resource "azurerm_storage_share" "clickhouse" {
  name                 = "clickhouse-data"
  storage_account_name = azurerm_storage_account.this.name
  quota                = 50  # 50 GB quota - adjust based on needs
  enabled_protocol     = "SMB"
}
