locals {
  tag_name = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"

  # Convert domain to globally unique name format, supporting only lowercase letters and numbers (e.g., company.com -> companycom)
  # If domain is not set, use the resource name
  globally_unique_prefix = var.domain != null ? replace(lower(var.domain), ".", "") : var.name
}
