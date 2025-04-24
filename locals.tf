locals {
  tag_name = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"

  # Convert domain to globally unique name format, supporting only lowercase letters and numbers (e.g., company.com -> companycom)
  globally_unique_prefix = replace(lower(var.domain), ".", "")
}
