locals {
  tag_name = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"

  # Convert domain to globally unique name format, supporting only lowercase letters and numbers (e.g., company.com -> companycom)
  globally_unique_prefix = replace(lower(var.domain), ".", "")

  gateway_domain          = var.gateway_domain != null ? var.gateway_domain : "gateway.${var.domain}"
  gateway_dns_record_name = trimsuffix(lower(local.gateway_domain), ".${lower(var.domain)}")

  # Create a dedicated self-signed Key Vault certificate for gateway_domain unless
  # the caller supplied gateway_ssl_certificate_key_vault_secret_id or a custom
  # ssl_certificate_key_vault_secret_id (e.g. a wildcard/SAN cert covering both).
  create_gateway_self_signed_cert = var.enable_ai_gateway && var.gateway_ssl_certificate_key_vault_secret_id == "" && var.ssl_certificate_key_vault_secret_id == ""
  use_dedicated_gateway_ssl_cert  = var.enable_ai_gateway && (var.gateway_ssl_certificate_key_vault_secret_id != "" || local.create_gateway_self_signed_cert)
  gateway_ssl_certificate_name    = !var.enable_ai_gateway ? "" : (local.use_dedicated_gateway_ssl_cert ? "${var.name}-gateway" : var.name)
}
