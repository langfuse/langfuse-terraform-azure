# Random bytes for Langfuse secrets
resource "random_bytes" "salt" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> SALT
  length = 32
}

resource "random_bytes" "nextauth_secret" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> NEXTAUTH_SECRET
  length = 32
}

resource "random_bytes" "encryption_key" {
  count = var.use_encryption_key ? 1 : 0
  # Must be exactly 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> ENCRYPTION_KEY
  length = 32
}

# Random password for Langfuse initial admin user
resource "random_password" "langfuse_admin_password" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}|;:,.<>?"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}
