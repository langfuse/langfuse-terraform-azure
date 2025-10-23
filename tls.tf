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

resource "tls_private_key" "ingress" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ingress" {
  private_key_pem       = tls_private_key.ingress.private_key_pem
  validity_period_hours = 8760

  subject {
    common_name = var.domain
  }

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]

  dns_names = [var.domain]
}

resource "azurerm_key_vault_secret" "ingress_certificate" {
  name         = "${var.name}-ingress-crt"
  value        = tls_self_signed_cert.ingress.cert_pem
  content_type = "application/x-pem-file"
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [
    azurerm_key_vault_access_policy.this
  ]
}

resource "azurerm_key_vault_secret" "ingress_private_key" {
  name         = "${var.name}-ingress-key"
  value        = tls_private_key.ingress.private_key_pem
  content_type = "application/x-pem-file"
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [
    azurerm_key_vault_access_policy.this
  ]
}
