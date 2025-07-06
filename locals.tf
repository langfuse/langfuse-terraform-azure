locals {
  tag_name = lower(var.name) == "langfuse" ? "Langfuse" : "Langfuse ${var.name}"

  # Convert domain to globally unique name format, supporting only lowercase letters and numbers 
  # Supports naming convention required by azure resources used for this deployment
  # MD5 substr enables traceability for domains used
  # lf3 prefix helps identify langfuse v3 resource
  globally_unique_prefix = "lf3${substr(md5(var.domain), 0, 6)}"
}
