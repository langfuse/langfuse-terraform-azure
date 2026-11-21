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
  rbac_authorization_enabled = true
}

# Grant the Terraform deployer "Key Vault Certificates Officer" role for certificate management
resource "azurerm_role_assignment" "keyvault_certificates_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role assignments are eventually consistent: the Key Vault data plane keeps
# rejecting requests for a while after an assignment is created, so creating the
# certificate right away fails with a 403. depends_on only orders the calls, it
# does not wait for the assignment to take effect.
resource "time_sleep" "key_vault_rbac_propagation" {
  create_duration = "60s"

  depends_on = [
    azurerm_role_assignment.keyvault_certificates_officer,
    azurerm_role_assignment.keyvault_secrets_user,
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
  name                 = "${var.name}-keyvault"
  private_dns_zone_id  = azurerm_private_dns_zone.key_vault.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
}

# Add A record for the key vault's private endpoint
resource "azurerm_private_dns_a_record" "key_vault" {
  name                = azurerm_key_vault.this.name
  private_dns_zone_id = azurerm_private_dns_zone.key_vault.id
  ttl                 = 300
  records             = [azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address]
}

locals {
  # Certificate material uploaded into this module's Key Vault. An incomplete
  # set still selects this path so the gateway preconditions can reject it.
  use_uploaded_ssl_certificate = var.ssl_certificate_key_vault_secret_id == "" && (
    var.ssl_certificate_body != "" ||
    var.ssl_certificate_private_key != "" ||
    var.ssl_certificate_ca != ""
  )

  use_generated_ssl_certificate = var.ssl_certificate_key_vault_secret_id == "" && !local.use_uploaded_ssl_certificate

  # Exactly one of the three sources is configured: an existing secret, an
  # uploaded certificate, or the self-signed certificate. Splatting keeps a
  # count of zero from being indexed.
  application_gateway_ssl_certificate_secret_id = element(concat(
    var.ssl_certificate_key_vault_secret_id != "" ? [var.ssl_certificate_key_vault_secret_id] : [],
    azurerm_key_vault_secret.ssl_certificate[*].versionless_id,
    azurerm_key_vault_certificate.this[*].versionless_secret_id,
  ), 0)
}

# Grant the Terraform deployer Key Vault Secrets Officer so an uploaded
# certificate can be stored in this vault.
resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  count                = local.use_uploaded_ssl_certificate ? 1 : 0
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role assignments are eventually consistent: the Key Vault data plane keeps
# rejecting requests for a while after an assignment is created, so creating the
# secret right away fails with a 403.
resource "time_sleep" "key_vault_secrets_officer_rbac_propagation" {
  count           = local.use_uploaded_ssl_certificate ? 1 : 0
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.keyvault_secrets_officer]
}

# Application Gateway accepts a PKCS#12 (PFX) secret. TripleDES-SHA1 is the
# encoding it can parse, including an empty password. The leaf is the first
# certificate in the body; further certificates in the body and ssl_certificate_ca
# are the chain sent to clients.
resource "pkcs12_from_pem" "ssl_certificate" {
  count           = local.use_uploaded_ssl_certificate ? 1 : 0
  password        = ""
  cert_pem        = replace(var.ssl_certificate_body, "\r\n", "\n")
  private_key_pem = replace(var.ssl_certificate_private_key, "\r\n", "\n")
  ca_pem          = replace(var.ssl_certificate_ca, "\r\n", "\n")
  encoding        = "legacyDES"

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_key_vault_secret" "ssl_certificate" {
  count        = local.use_uploaded_ssl_certificate ? 1 : 0
  name         = module.naming.key_vault_secret.name
  value        = pkcs12_from_pem.ssl_certificate[0].result
  key_vault_id = azurerm_key_vault.this.id
  content_type = "application/x-pkcs12"

  depends_on = [
    time_sleep.key_vault_secrets_officer_rbac_propagation,
    time_sleep.key_vault_rbac_propagation,
  ]
}

resource "azurerm_key_vault_certificate" "this" {
  count        = local.use_generated_ssl_certificate ? 1 : 0
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
    time_sleep.key_vault_rbac_propagation,
    azurerm_dns_zone.this
  ]
}

moved {
  from = azurerm_key_vault_certificate.this
  to   = azurerm_key_vault_certificate.this[0]
}
