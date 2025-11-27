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
# Premium Storage Account for ClickHouse NFS
# NFS requires Premium FileStorage and Secure Transfer Disabled
resource "azurerm_storage_account" "clickhouse_nfs" {
  name                          = "${substr(replace(module.naming.storage_account.name_unique, "-", ""), 0, 16)}nfs"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  account_tier                  = "Premium"
  account_kind                  = "FileStorage"
  account_replication_type      = "LRS"
  https_traffic_only_enabled    = false # Must be false for NFS
  public_network_access_enabled = true  # Controlled via VNet rules

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.container_apps.id]
  }
}

# NFS File Share
resource "azurerm_storage_share" "clickhouse_nfs" {
  name                 = "clickhouse-data-nfs"
  storage_account_id   = azurerm_storage_account.clickhouse_nfs.id
  quota                = 100
  enabled_protocol     = "NFS"
}
