resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.environment}-app-secrets-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  recovery_window_in_days = 0 # Allows instant recreation on destroy
  
  tags = {
    Name = "${var.environment}-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets_val" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  # All environment variables stored together securely as JSON
  secret_string = jsonencode({
    DB_HOST = var.db_host
    DB_USER = var.db_user
    DB_PASS = var.db_password
    DB_NAME = var.db_name
    PORT    = var.app_port
  })
}