# Plans the TLS certificate selection. Run with `terraform test` (Terraform 1.7 or later).

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "pkcs12" {}

variables {
  domain = "langfuse.example.com"
}

run "generated_certificate_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault_certificate.this) == 1
    error_message = "A self-signed Key Vault certificate is created when no custom certificate is set."
  }

  assert {
    condition     = length(azurerm_key_vault_secret.ssl_certificate) == 0
    error_message = "No uploaded certificate secret is created when no custom certificate is set."
  }

  assert {
    condition     = length(pkcs12_from_pem.ssl_certificate) == 0
    error_message = "No PKCS#12 bundle is built when no custom certificate is set."
  }

  assert {
    condition     = length(azurerm_role_assignment.keyvault_secrets_officer) == 0
    error_message = "The default deployment does not add a Key Vault Secrets Officer assignment."
  }

}

run "uploaded_certificate_replaces_self_signed" {
  command = plan

  variables {
    ssl_certificate_body        = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
    ssl_certificate_private_key = "-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----"
    ssl_certificate_ca          = "-----BEGIN CERTIFICATE-----\nCA\n-----END CERTIFICATE-----"
  }

  assert {
    condition     = length(azurerm_key_vault_certificate.this) == 0
    error_message = "The self-signed certificate is omitted when a custom certificate is set."
  }

  assert {
    condition     = length(azurerm_key_vault_secret.ssl_certificate) == 1
    error_message = "The custom certificate is stored in Key Vault."
  }

  assert {
    condition     = length(azurerm_role_assignment.keyvault_secrets_officer) == 1
    error_message = "Terraform is granted Key Vault Secrets Officer when it stores an uploaded certificate."
  }

  assert {
    condition     = azurerm_key_vault_secret.ssl_certificate[0].content_type == "application/x-pkcs12"
    error_message = "The uploaded certificate secret is a PKCS#12 bundle."
  }

  assert {
    condition     = pkcs12_from_pem.ssl_certificate[0].ca_pem == "-----BEGIN CERTIFICATE-----\nCA\n-----END CERTIFICATE-----"
    error_message = "The CA chain is included in the PKCS#12 bundle."
  }

  assert {
    condition     = pkcs12_from_pem.ssl_certificate[0].encoding == "legacyDES"
    error_message = "The PKCS#12 bundle uses TripleDES-SHA1."
  }

}

run "existing_key_vault_secret" {
  command = plan

  variables {
    ssl_certificate_key_vault_secret_id = "https://corp.vault.azure.net/secrets/langfuse-tls"
  }

  assert {
    condition     = length(azurerm_key_vault_certificate.this) == 0 && length(azurerm_key_vault_secret.ssl_certificate) == 0
    error_message = "An existing Key Vault secret is used as-is."
  }

  assert {
    condition = alltrue([
      for cert in azurerm_application_gateway.this.ssl_certificate : cert.key_vault_secret_id == "https://corp.vault.azure.net/secrets/langfuse-tls"
    ])
    error_message = "The Application Gateway listener uses the provided Key Vault secret."
  }

  assert {
    condition     = output.ssl_certificate_key_vault_secret_id == "https://corp.vault.azure.net/secrets/langfuse-tls"
    error_message = "The secret ID output matches the provided Key Vault secret."
  }
}

run "certificate_requires_private_key" {
  command = plan

  variables {
    ssl_certificate_body = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
  }

  expect_failures = [
    azurerm_application_gateway.this,
  ]
}

run "ca_requires_certificate" {
  command = plan

  variables {
    ssl_certificate_ca = "-----BEGIN CERTIFICATE-----\nCA\n-----END CERTIFICATE-----"
  }

  expect_failures = [
    azurerm_application_gateway.this,
  ]
}

run "secret_id_conflicts_with_uploaded_certificate" {
  command = plan

  variables {
    ssl_certificate_body                = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
    ssl_certificate_private_key         = "-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----"
    ssl_certificate_key_vault_secret_id = "https://corp.vault.azure.net/secrets/langfuse-tls"
  }

  expect_failures = [
    azurerm_application_gateway.this,
  ]
}

run "rejects_encrypted_private_key" {
  command = plan

  variables {
    ssl_certificate_body        = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
    ssl_certificate_private_key = "-----BEGIN ENCRYPTED PRIVATE KEY-----\nMIIB\n-----END ENCRYPTED PRIVATE KEY-----"
  }

  expect_failures = [
    var.ssl_certificate_private_key,
  ]
}

run "rejects_non_pem_certificate" {
  command = plan

  variables {
    ssl_certificate_body        = "not-a-certificate"
    ssl_certificate_private_key = "-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----"
  }

  expect_failures = [
    var.ssl_certificate_body,
  ]
}
