# Make sure to use a historic globally unique name, since they key vault is created with soft deletion
resource "random_string" "key_vault_postfix" {
  length  = 4
  lower   = true
  numeric = false
  special = false
  upper   = false
}

resource "azurerm_key_vault" "this" {
  name                       = module.naming.key_vault.name_unique
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}

resource "azurerm_key_vault_access_policy" "this" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  certificate_permissions = [
    "Create",
    "Delete",
    "DeleteIssuers",
    "Get",
    "GetIssuers",
    "Import",
    "List",
    "ListIssuers",
    "ManageContacts",
    "ManageIssuers",
    "SetIssuers",
    "Update",
  ]

  key_permissions = [
    "Create",
    "Delete",
    "Get",
    "Import",
    "List",
    "Update",
  ]

  secret_permissions = [
    "Delete",
    "Get",
    "List",
    "Purge",
    "Recover",
    "Set",
  ]
}

# Add Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "key_vault" {
  name                = "${module.naming.private_endpoint.name}-keyvault"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.aks.id

  private_service_connection {
    name                           = "${var.name}-keyvault"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "${var.name}-keyvault"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
}

# Add A record for the key vault's private endpoint
resource "azurerm_private_dns_a_record" "key_vault" {
  name                = azurerm_key_vault.this.name
  zone_name           = azurerm_private_dns_zone.key_vault.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address]
}

resource "azurerm_key_vault_certificate" "this" {
  name         = module.naming.key_vault_certificate.name
  key_vault_id = azurerm_key_vault.this.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "digitalSignature",
        "keyEncipherment"
      ]

      subject            = "CN=${var.domain}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [var.domain]
      }
    }
  }

  depends_on = [
    azurerm_dns_zone.this
  ]
}
