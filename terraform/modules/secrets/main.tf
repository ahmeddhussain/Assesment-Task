resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.environment}-app-secrets"
  recovery_window_in_days = 0 # instant recreation on destroy (assessment only - use 7-30 in production)

  tags = {
    Name = "${var.environment}-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets_val" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  # All environment variables stored together as one JSON secret
  secret_string = jsonencode({
    DB_HOST = var.db_host
    DB_USER = var.db_user
    DB_PASS = var.db_password
    DB_NAME = var.db_name
    PORT    = var.app_port
  })
}
