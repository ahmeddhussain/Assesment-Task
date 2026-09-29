variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "db_name" {
  type    = string
  default = "devopsdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "SuperSecurePassword123!" # Override via TF_VAR_db_password or tfvars
}

variable "alert_email" {
  type        = string
  description = "Email to receive CloudWatch 5XX error alerts"
  default     = "ahmed@example.com" # Replace with your email
}