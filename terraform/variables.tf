variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment (used as a prefix in every resource name)"
  default     = "dev"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "devopsdb"
}

variable "alert_email" {
  type        = string
  description = "Email that receives CloudWatch alarm notifications (supplied via TF_VAR_alert_email / tfvars)"
}
