locals {
  tag_name = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"

  # Convert domain to globally unique name format, supporting only lowercase letters and numbers (e.g., company.com -> companycom)
  globally_unique_prefix = replace(lower(var.domain), ".", "")

  # Use external certificate secret ID if provided, otherwise use the self-signed certificate
  ssl_certificate_secret_id = var.ssl_certificate_secret_id != null ? var.ssl_certificate_secret_id : azurerm_key_vault_certificate.this[0].versionless_secret_id
}
